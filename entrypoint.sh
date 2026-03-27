#!/bin/bash
# ============================================================
# Configure user environment (env-var-dependent only)
# ============================================================

if [ -n "$GIT_AUTHOR_NAME" ]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
  export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"
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

# ============================================================
# gogcli (gog) — restore OAuth credentials and refresh token
# ============================================================
if [ -n "$GOG_CREDENTIALS_JSON" ]; then
  GOG_CONFIG_DIR="$HOME/.config/gogcli"
  mkdir -p "$GOG_CONFIG_DIR"
  echo "$GOG_CREDENTIALS_JSON" | base64 -d >"$GOG_CONFIG_DIR/credentials.json"
  chmod 600 "$GOG_CONFIG_DIR/credentials.json"

  if [ -n "$GOG_TOKEN_JSON" ]; then
    _gog_tmp="$(mktemp)"
    echo "$GOG_TOKEN_JSON" | base64 -d >"$_gog_tmp"
    export GOG_KEYRING_BACKEND=file
    export GOG_KEYRING_PASSWORD="${GOG_KEYRING_PASSWORD:-gogcli-container}"
    gog auth tokens import "$_gog_tmp" >/dev/null 2>&1 || true
    rm -f "$_gog_tmp"
  fi
fi
if [ -n "$GOG_ACCOUNT" ]; then
  export GOG_ACCOUNT
fi

# ============================================================
# Google Workspace CLI (gws) — restore OAuth credentials
# ============================================================
if [ -n "$GWS_CLIENT_SECRET_JSON" ]; then
  GWS_CONFIG_DIR="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}"
  mkdir -p "$GWS_CONFIG_DIR"
  echo "$GWS_CLIENT_SECRET_JSON" | base64 -d >"$GWS_CONFIG_DIR/client_secret.json"
  chmod 600 "$GWS_CONFIG_DIR/client_secret.json"

  if [ -n "$GWS_ENCRYPTION_KEY" ] && [ -n "$GWS_CREDENTIALS_ENC" ]; then
    echo "$GWS_ENCRYPTION_KEY" >"$GWS_CONFIG_DIR/.encryption_key"
    chmod 600 "$GWS_CONFIG_DIR/.encryption_key"
    echo "$GWS_CREDENTIALS_ENC" | base64 -d >"$GWS_CONFIG_DIR/credentials.enc"
    chmod 600 "$GWS_CONFIG_DIR/credentials.enc"
    export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file
  fi
  if [ -n "$GWS_TOKEN_CACHE" ]; then
    echo "$GWS_TOKEN_CACHE" | base64 -d >"$GWS_CONFIG_DIR/token_cache.json"
    chmod 600 "$GWS_CONFIG_DIR/token_cache.json"
  fi
fi

if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then
  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
fi

# ============================================================
# Derive intermediate variables from LITELLM_API_KEY and LITELLM_BASE_URL.
# Both OpenCode providers and Claude Code share the same LiteLLM server.
# Must happen before auto-approve and the opencode.json sed substitution.
# ============================================================
if [ -n "$LITELLM_API_KEY" ]; then
  export OPENAI_API_KEY="$LITELLM_API_KEY"
  export ANTHROPIC_API_KEY="$LITELLM_API_KEY"
fi
if [ -n "$LITELLM_BASE_URL" ]; then
  export OPENAI_BASE_URL="${LITELLM_BASE_URL}/api/v1"
  export OPENAI_API_BASE="${LITELLM_BASE_URL}/api/v1"
  export ANTHROPIC_BASE_URL="${LITELLM_BASE_URL}/anthropic"
fi

# ============================================================
# Override Claude Code's default date-suffixed model IDs with
# short names the LiteLLM proxy accepts.
# ============================================================
if [ -n "$LITELLM_BASE_URL" ]; then
  export ANTHROPIC_SMALL_FAST_MODEL="claude-haiku-4-5"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-6"
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
  cp "$OPENCODE_CONFIG_DIR/oh-my-opencode-anthropic.json" "$OPENCODE_CONFIG_DIR/oh-my-opencode.json"
  cat >"$HOME/.local/share/opencode/auth.json" <<AUTHEOF
{"anthropic":{"type":"oauth","access":"${CLAUDE_CODE_OAUTH_TOKEN}","refresh":"","expires":9999999999999}}
AUTHEOF
elif [ -n "$LITELLM_API_KEY" ]; then
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
# Fix plugin script permissions (issue #648)
# Three-layer fix:
#   1. Immediate chmod sweep for non-session contexts (self-test)
#   2. SessionStart hook injected into settings.json so Claude
#      Code re-applies chmod AFTER its plugin sync overwrites
#      build-time permissions.
#   3. PostToolUse hook (matcher: Skill) catches mid-session
#      plugin reloads via /reload-plugins that arrive after
#      SessionStart has already fired.
# Remove all three when upstream issue #648 is resolved.
# ============================================================
find "${HOME}/.claude/plugins" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null || true

# Inject SessionStart + PostToolUse hooks into runtime settings.json if missing
SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sys
p = '${SETTINGS}'
with open(p) as f: s = json.load(f)
cmd = \"find ~/.claude/plugins -name '*.sh' -type f ! -perm -u+x -exec chmod +x {} +\"
session_hook = [{'matcher':'','hooks':[{'type':'command','command':cmd,'timeout':10}]}]
skill_hook = [{'matcher':'Skill','hooks':[{'type':'command','command':cmd,'timeout':10}]}]
h = s.get('hooks',{})
if h.get('SessionStart') == session_hook and h.get('PostToolUse') == skill_hook: sys.exit(0)
s.setdefault('hooks',{})['SessionStart'] = session_hook
s['hooks']['PostToolUse'] = skill_hook
with open(p,'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null || true
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
