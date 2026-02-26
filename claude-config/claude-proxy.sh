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
# exports ANTHROPIC_BASE_URL and OPENAI_BASE_URL so Claude Code,
# Codex, and OpenCode all route through it.
# ============================================================

start_claude_proxy() {
  # Nothing to do if proxy mode is not requested
  if [ -z "$OPENAI_API_KEY" ] || [ ! -d /opt/claude-code-proxy ]; then
    return 0
  fi

  local proxy_port="${PROXY_PORT:-8082}"
  local proxy_url="http://localhost:${proxy_port}"

  # Save the original (upstream) OPENAI_BASE_URL before we overwrite it.
  # Guard against re-source: only save if not already redirected to the proxy.
  if [ -z "$_UPSTREAM_OPENAI_BASE_URL" ] && [ "${OPENAI_BASE_URL:-}" != "$proxy_url" ]; then
    export _UPSTREAM_OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
  fi

  # Always point Claude Code at the local proxy
  export ANTHROPIC_BASE_URL="$proxy_url"

  # If the proxy is already reachable, redirect OPENAI_BASE_URL and return
  if curl -sf --connect-timeout 1 "${proxy_url}/" >/dev/null 2>&1; then
    export OPENAI_BASE_URL="$proxy_url"
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
      OPENAI_BASE_URL="${_UPSTREAM_OPENAI_BASE_URL:-}" \
      ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      BIG_MODEL="${BIG_MODEL:-}" \
      MIDDLE_MODEL="${MIDDLE_MODEL:-}" \
      SMALL_MODEL="${SMALL_MODEL:-}" \
      LOG_LEVEL="${LOG_LEVEL:-WARNING}" \
      MAX_TOKENS_LIMIT="${MAX_TOKENS_LIMIT:-64000}" \
      REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-120}" \
      uv run python start_proxy.py >>/tmp/claude-proxy.log 2>&1
  ) &

  # Wait for the proxy to become ready (up to ~30 s)
  # Poll every 0.2s for the first 5 attempts (proxy typically starts in ~300ms),
  # then fall back to 1s intervals for the remaining attempts.
  local retries=0
  while [ "$retries" -lt 30 ]; do
    if curl -sf --connect-timeout 1 "${proxy_url}/" >/dev/null 2>&1; then
      $quiet || echo "Claude Code proxy ready on port ${proxy_port}"
      export OPENAI_BASE_URL="$proxy_url"
      return 0
    fi
    if [ "$retries" -lt 5 ]; then
      sleep 0.2
    else
      sleep 1
    fi
    retries=$((retries + 1))
  done

  echo "Warning: Claude Code proxy failed to start (check /tmp/claude-proxy.log)" >&2
  return 1
}
