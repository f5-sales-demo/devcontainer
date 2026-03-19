#!/bin/bash
# ============================================================
# Configure user environment (env-var-dependent only)
# ============================================================

if [ -n "$GIT_AUTHOR_NAME" ]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

git config --global --add safe.directory /workspace

if [ -n "$TZ" ]; then
  sudo ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" | sudo tee /etc/timezone >/dev/null
fi

if [ -n "$SSH_PRIVATE_KEY" ]; then
  _old_umask=$(umask)
  umask 077
  echo "$SSH_PRIVATE_KEY" | base64 -d >"$HOME/.ssh/id_ed25519"
  umask "$_old_umask"
  ssh-keygen -y -f "$HOME/.ssh/id_ed25519" >"$HOME/.ssh/id_ed25519.pub" 2>/dev/null
  if [ ! -f "$HOME/.ssh/config" ]; then
    cat >"$HOME/.ssh/config" <<'SSHCONF'
Host github.com
    StrictHostKeyChecking accept-new
    IdentityFile ~/.ssh/id_ed25519
Host *
    StrictHostKeyChecking accept-new
SSHCONF
    chmod 600 "$HOME/.ssh/config"
  fi
fi

if [ -n "$GH_TOKEN" ]; then
  gh auth setup-git 2>/dev/null || true
fi

if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then
  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
fi

# ============================================================
# Detect LiteLLM direct mode (reused in multiple blocks below)
# ============================================================
_is_litellm_direct=false
if [ -n "$ANTHROPIC_BASE_URL" ]; then
  case "$ANTHROPIC_BASE_URL" in
  http://localhost:* | http://localhost) ;;
  *) _is_litellm_direct=true ;;
  esac
fi

# ============================================================
# Derive ANTHROPIC_API_KEY from OPENAI_API_KEY when not set.
# Both providers share the same LiteLLM server and API key.
# Must happen before auto-approve and the opencode.json sed substitution.
# ============================================================
if [ -n "$OPENAI_API_KEY" ]; then
  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-$OPENAI_API_KEY}"
fi

if [ "$_is_litellm_direct" = true ]; then
  export ANTHROPIC_1M_CONTEXT="false"
  sed -i 's|"ANTHROPIC_1M_CONTEXT": "true"|"ANTHROPIC_1M_CONTEXT": "false"|' \
    "$HOME/.claude/settings.json"
else
  export ANTHROPIC_1M_CONTEXT="true"
fi

# ============================================================
# Auto-approve ANTHROPIC_API_KEY in Claude Code state
# ============================================================
if [ -n "$ANTHROPIC_API_KEY" ] && [ -f "$HOME/.claude.json" ]; then
  jq --arg key "$ANTHROPIC_API_KEY" '
    .customApiKeyResponses.approved = (
      (.customApiKeyResponses.approved // []) + [$key[-20:]] | unique
    )' "$HOME/.claude.json" >"$HOME/.claude.json.tmp" &&
    mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
fi

# ============================================================
# OpenCode config switching (OAuth vs proxy mode)
# ============================================================
# All config variants are baked into the image at final paths.
# This block only activates the correct variant based on env vars.
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  cp "$OPENCODE_CONFIG_DIR/opencode-anthropic.json" "$OPENCODE_CONFIG_DIR/opencode.json"
  cat >"$HOME/.local/share/opencode/auth.json" <<AUTHEOF
{"anthropic":{"type":"oauth","access":"${CLAUDE_CODE_OAUTH_TOKEN}","refresh":"","expires":9999999999999}}
AUTHEOF
elif [ -n "$OPENAI_API_KEY" ]; then
  _esc_base_url=$(printf '%s' "$OPENAI_BASE_URL" | sed 's/[&\\/]/\\&/g')
  _esc_api_key=$(printf '%s' "$OPENAI_API_KEY" | sed 's/[&\\/]/\\&/g')
  _esc_anthropic_base_url=$(printf '%s' "$ANTHROPIC_BASE_URL" | sed 's/[&\\/]/\\&/g')
  _esc_anthropic_api_key=$(printf '%s' "$ANTHROPIC_API_KEY" | sed 's/[&\\/]/\\&/g')
  sed -e "s|{env:OPENAI_BASE_URL}|${_esc_base_url}|g" \
    -e "s|{env:OPENAI_API_KEY}|${_esc_api_key}|g" \
    -e "s|{env:ANTHROPIC_BASE_URL}|${_esc_anthropic_base_url}|g" \
    -e "s|{env:ANTHROPIC_API_KEY}|${_esc_anthropic_api_key}|g" \
    "$OPENCODE_CONFIG_DIR/opencode.json" \
    >"$OPENCODE_CONFIG_DIR/opencode.json.tmp" &&
    mv "$OPENCODE_CONFIG_DIR/opencode.json.tmp" "$OPENCODE_CONFIG_DIR/opencode.json"
  unset _esc_base_url _esc_api_key _esc_anthropic_base_url _esc_anthropic_api_key
  cp "$OPENCODE_CONFIG_DIR/oh-my-opencode-proxy.json" \
    "$OPENCODE_CONFIG_DIR/oh-my-opencode.json"
fi

# ============================================================
# Auth mode env defaults
# ============================================================
if [ "$_is_litellm_direct" = true ]; then
  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-${OPENAI_API_KEY:-litellm-proxy}}"
elif [ -n "$OPENAI_API_KEY" ] && [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-openai-proxy}"
  export BIG_MODEL="${BIG_MODEL:-claude-opus-4-6}"
  export MIDDLE_MODEL="${MIDDLE_MODEL:-claude-sonnet-4-6}"
  export SMALL_MODEL="${SMALL_MODEL:-claude-haiku-4-5}"
fi
unset _is_litellm_direct

# ============================================================
# Claude Code Proxy (Anthropic Messages API -> OpenAI)
# ============================================================
# shellcheck source=/dev/null
. /usr/local/lib/claude-proxy.sh
start_claude_proxy

# ============================================================
# Chrome DevTools MCP (symlink + shared browser)
# ============================================================
fix_chrome_symlink() {
  if [ -L /opt/google/chrome/chrome ] && [ -e /opt/google/chrome/chrome ]; then
    return 0
  fi
  local chrome_bin
  chrome_bin=$(find "$HOME/.cache/ms-playwright" \
    -name chrome -path '*/chromium-*/chrome-linux*/chrome' -print -quit 2>/dev/null || true)
  if [ -n "$chrome_bin" ]; then
    sudo mkdir -p /opt/google/chrome
    sudo ln -sf "$chrome_bin" /opt/google/chrome/chrome
  fi
}
fix_chrome_symlink

# shellcheck source=/dev/null
. /usr/local/lib/chrome-browser.sh

# ============================================================
# VNC stack (Xvfb + fluxbox + x11vnc + noVNC)
# ============================================================
if [ "${ENABLE_VNC:-false}" = "true" ]; then
  VNC_RESOLUTION="${VNC_RESOLUTION:-1280x1024x24}"
  VNC_PORT="${VNC_PORT:-5900}"
  NOVNC_PORT="${NOVNC_PORT:-6080}"
  export DISPLAY="${DISPLAY:-:99}"

  Xvfb "${DISPLAY}" -screen 0 "${VNC_RESOLUTION}" -ac +extension GLX +render -noreset >/dev/null 2>&1 &

  (
    retries=0
    while [ $retries -lt 50 ]; do
      xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1 && break
      sleep 0.1
      retries=$((retries + 1))
    done

    fluxbox >/dev/null 2>&1 &
    x11vnc -display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" \
      -nopw -xkb -noxrecord -noxfixes -noxdamage >/dev/null 2>&1 &

    NOVNC_LAUNCHER=""
    for candidate in \
      /usr/share/novnc/utils/novnc_proxy \
      /usr/share/novnc/utils/launch.sh \
      /usr/share/novnc/utils/websockify/run; do
      if [ -x "$candidate" ]; then
        NOVNC_LAUNCHER="$candidate"
        break
      fi
    done

    if [ -n "$NOVNC_LAUNCHER" ]; then
      "$NOVNC_LAUNCHER" --vnc localhost:"${VNC_PORT}" --listen "${NOVNC_PORT}" >/dev/null 2>&1 &
    else
      websockify --web /usr/share/novnc "${NOVNC_PORT}" localhost:"${VNC_PORT}" >/dev/null 2>&1 &
    fi

  ) &
fi

# ============================================================
# Shared Chrome browser (remote debugging on port 9222)
# ============================================================
start_chrome_browser

# ============================================================
# Tailscale (userspace networking)
# ============================================================
if [ "${ENABLE_TAILSCALE:-false}" = "true" ]; then
  sudo tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state >/dev/null 2>&1 &
  if [ -n "$TAILSCALE_AUTHKEY" ]; then
    (
      retries=0
      while [ $retries -lt 50 ]; do
        sudo tailscale status >/dev/null 2>&1 && break
        sleep 0.1
        retries=$((retries + 1))
      done
      sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --accept-routes >/dev/null 2>&1
    ) &
  fi
fi

exec "$@"
