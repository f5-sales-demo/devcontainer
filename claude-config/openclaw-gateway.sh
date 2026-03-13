#!/bin/bash
# ============================================================
# OpenClaw Gateway — shared startup function
# ============================================================
# Installed to /usr/local/lib/openclaw-gateway.sh in the container image.
#
# Sourced by:
#   1. entrypoint.sh          — runs at container start
#   2. /etc/profile.d/ hook   — runs when opening a bash login shell
#   3. /etc/zsh/zshenv        — runs when opening any zsh shell
#
# Exposes one function: start_openclaw_gateway
#
# The function is idempotent — safe to call from multiple places.
# It checks whether the openclaw config exists, whether the gateway
# is already running, starts it if needed, and waits for readiness.
# ============================================================

start_openclaw_gateway() {
  local config="$HOME/.openclaw/openclaw.json"

  # Nothing to do if openclaw is not configured or not installed
  if [ ! -f "$config" ] || [ ! -s "$config" ]; then
    return 0
  fi
  command -v openclaw >/dev/null 2>&1 || return 0

  local gateway_log="$HOME/.local/share/openclaw-gateway/gateway.log"
  mkdir -p "$(dirname "$gateway_log")"

  # If the gateway is already running, nothing to do
  if openclaw health >/dev/null 2>&1; then
    return 0
  fi

  # Suppress output in non-interactive shells (e.g. zshenv in scripts)
  local quiet=false
  case "$-" in
  *i*) ;; # interactive — print status
  *) quiet=true ;;
  esac

  $quiet || echo "Starting OpenClaw gateway..."
  openclaw gateway run >>"$gateway_log" 2>&1 &

  # Wait for the gateway to become ready (up to ~30 s)
  # Poll every 0.2s for the first 5 attempts, then fall back to 1s intervals.
  local retries=0
  while [ "$retries" -lt 30 ]; do
    if openclaw health >/dev/null 2>&1; then
      $quiet || echo "OpenClaw gateway ready"
      return 0
    fi
    if [ "$retries" -lt 5 ]; then
      sleep 0.2
    else
      sleep 1
    fi
    retries=$((retries + 1))
  done

  echo "Warning: OpenClaw gateway failed to start (check ~/.local/share/openclaw-gateway/gateway.log)" >&2
  return 1
}
