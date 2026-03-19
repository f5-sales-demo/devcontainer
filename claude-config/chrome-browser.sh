#!/bin/bash
# ============================================================
# Shared Chrome Browser — persistent headless instance
# ============================================================
# Installed to /usr/local/lib/chrome-browser.sh in the container image.
#
# Sourced by:
#   1. entrypoint.sh — runs at container start
#
# Exposes one function: start_chrome_browser
#
# The function is idempotent — safe to call multiple times.
# It launches a persistent headless Chrome with remote debugging
# on port 9222. All Claude Code sessions connect to this shared
# instance via --browserUrl, eliminating profile lock conflicts
# and sharing cookies/auth across projects.
# ============================================================

start_chrome_browser() {
  local chrome_bin="/opt/google/chrome/chrome"
  local debug_port="9222"
  local debug_url="http://localhost:${debug_port}"
  local log_dir="${HOME}/.local/share/chrome-browser"
  local log_file="${log_dir}/chrome.log"

  # Chrome binary must exist
  if [ -e "$chrome_bin" ] || [ -L "$chrome_bin" ]; then
    : # proceed
  else
    return 0
  fi

  # Already running — nothing to do
  if curl -sf --connect-timeout 2 "${debug_url}/json/version" >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p "$log_dir"

  # Build Chrome flags
  local chrome_flags=(
    --no-sandbox
    --disable-gpu
    --remote-debugging-port="${debug_port}"
    --remote-debugging-address=127.0.0.1
    --user-data-dir="${HOME}/.cache/chrome-devtools-mcp/chrome-profile"
    --no-first-run
    --no-default-browser-check
    --disable-extensions
    --disable-background-timer-throttling
    --disable-backgrounding-occluded-windows
    "--disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades,HttpsFirstModeV2"
  )

  # If DISPLAY is set and working, run headed (VNC visibility)
  # Otherwise run headless
  if [ -n "${DISPLAY:-}" ] && xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    : # headed mode — no extra flags
  else
    chrome_flags+=(--headless=new)
  fi

  # Suppress output in non-interactive shells
  local quiet=false
  case "$-" in
  *i*) ;; # interactive — print status
  *) quiet=true ;;
  esac

  $quiet || echo "Starting shared Chrome browser on port ${debug_port}..."

  # Launch in background with restart loop
  (
    while true; do
      "$chrome_bin" "${chrome_flags[@]}" >>"$log_file" 2>&1
      sleep 1
    done
  ) &

  # Poll readiness up to ~10s
  local retries=0
  while [ "$retries" -lt 20 ]; do
    if curl -sf --connect-timeout 1 "${debug_url}/json/version" >/dev/null 2>&1; then
      $quiet || echo "Shared Chrome browser ready on port ${debug_port}"
      return 0
    fi
    sleep 0.5
    retries=$((retries + 1))
  done

  echo "Warning: Chrome browser failed to start on port ${debug_port} (check ${log_file})" >&2
  return 1
}
