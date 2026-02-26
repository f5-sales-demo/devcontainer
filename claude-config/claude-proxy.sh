#!/bin/bash
# ============================================================
# Claude Code Proxy — shared startup function
# ============================================================
# Installed to /usr/local/lib/claude-proxy.sh in the container image.
#
# Sourced by:
#   1. entrypoint.sh          — runs at container start
#   2. /etc/profile.d/ hook   — runs when opening a bash login shell
#   3. /etc/zsh/zshenv        — runs when opening any zsh shell
#
# Exposes one function: start_claude_proxy
#
# The function is idempotent — safe to call from multiple places.
# It checks whether proxy mode is requested (OPENAI_API_KEY set),
# whether the proxy is already running, starts it if needed, and
# exports ANTHROPIC_BASE_URL so Claude Code routes through it.
# ============================================================

start_claude_proxy() {
  # Nothing to do if proxy mode is not requested
  if [ -z "$OPENAI_API_KEY" ] || [ ! -d /opt/claude-code-proxy ]; then
    return 0
  fi

  local proxy_port="${PROXY_PORT:-8082}"

  # Always point Claude Code at the local proxy
  export ANTHROPIC_BASE_URL="http://localhost:${proxy_port}"

  # If the proxy is already reachable, nothing more to do
  if curl -sf --connect-timeout 1 "http://localhost:${proxy_port}/" >/dev/null 2>&1; then
    return 0
  fi

  # Suppress output in non-interactive shells (e.g. zshenv in scripts)
  local quiet=false
  case "$-" in
  *i*) ;; # interactive — print status
  *) quiet=true ;;
  esac

  $quiet || echo "Starting Claude Code proxy on port ${proxy_port}..."
  (
    cd /opt/claude-code-proxy || exit 1
    HOST=0.0.0.0 PORT="$proxy_port" \
      OPENAI_API_KEY="$OPENAI_API_KEY" \
      OPENAI_BASE_URL="${OPENAI_BASE_URL:-}" \
      ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      BIG_MODEL="${BIG_MODEL:-}" \
      MIDDLE_MODEL="${MIDDLE_MODEL:-}" \
      SMALL_MODEL="${SMALL_MODEL:-}" \
      LOG_LEVEL="${LOG_LEVEL:-WARNING}" \
      MAX_TOKENS_LIMIT="${MAX_TOKENS_LIMIT:-64000}" \
      REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-120}" \
      uv run python start_proxy.py >>/tmp/claude-proxy.log 2>&1
  ) &

  # Wait for the proxy to become ready (up to 30 s)
  local retries=0
  while [ "$retries" -lt 30 ]; do
    if curl -sf --connect-timeout 1 "http://localhost:${proxy_port}/" >/dev/null 2>&1; then
      $quiet || echo "Claude Code proxy ready on port ${proxy_port}"
      return 0
    fi
    sleep 1
    retries=$((retries + 1))
  done

  echo "Warning: Claude Code proxy failed to start (check /tmp/claude-proxy.log)" >&2
  return 1
}
