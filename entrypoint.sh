#!/bin/bash
# Fix volume permissions
for dir in "$HOME/.cache" "$HOME/.local" "$HOME/.claude" "$HOME/.ssh"; do
  if [ -d "$dir" ] && [ ! -O "$dir" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$dir" 2>/dev/null || true
  fi
done

if [ ! -O "$HOME" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$HOME" 2>/dev/null || true
fi

# ============================================================
# Configure user environment
# ============================================================

# Git config from env vars
if [ -n "$GIT_AUTHOR_NAME" ]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

# Timezone
if [ -n "$TZ" ]; then
  sudo ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" | sudo tee /etc/timezone >/dev/null
fi

# SSH key from env var (base64 encoded)
if [ -n "$SSH_PRIVATE_KEY" ]; then
  _old_umask=$(umask)
  umask 077
  mkdir -p "$HOME/.ssh"
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

# Export ANTHROPIC_OAUTH_TOKEN for tools that read it (e.g. Pi)
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then
  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
fi

# Seed Pi settings if missing
PI_AGENT_DIR="$HOME/.pi/agent"
if [ ! -f "$PI_AGENT_DIR/settings.json" ] || [ ! -s "$PI_AGENT_DIR/settings.json" ]; then
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    mkdir -p "$PI_AGENT_DIR"
    cat >"$PI_AGENT_DIR/settings.json" <<'PIEOF'
{"defaultProvider":"anthropic","defaultModel":"claude-opus-4-6"}
PIEOF
  fi
fi

# Ensure Claude Code onboarding + theme are always set
if [ -f "$HOME/.claude.json" ] && [ -s "$HOME/.claude.json" ]; then
  jq '. + {"hasCompletedOnboarding": true, "theme": (.theme // "dark-daltonized")}' \
    "$HOME/.claude.json" >"$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
else
  echo '{"hasCompletedOnboarding": true, "theme": "dark-daltonized"}' >"$HOME/.claude.json"
fi

# Seed opencode config if missing
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
if [ ! -f "$OPENCODE_CONFIG_DIR/opencode.json" ] || [ ! -s "$OPENCODE_CONFIG_DIR/opencode.json" ]; then
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -f /opt/opencode-config/opencode-anthropic.json ]; then
    mkdir -p "$OPENCODE_CONFIG_DIR"
    cp /opt/opencode-config/opencode-anthropic.json "$OPENCODE_CONFIG_DIR/opencode.json"
    # Seed OAuth credentials for opencode's Anthropic provider
    OPENCODE_DATA_DIR="$HOME/.local/share/opencode"
    mkdir -p "$OPENCODE_DATA_DIR"
    cat >"$OPENCODE_DATA_DIR/auth.json" <<AUTHEOF
{"anthropic":{"type":"oauth","access":"${CLAUDE_CODE_OAUTH_TOKEN}","refresh":"","expires":9999999999999}}
AUTHEOF
  elif [ -n "$OPENAI_API_KEY" ] && [ -f /opt/opencode-config/opencode.json ]; then
    mkdir -p "$OPENCODE_CONFIG_DIR"
    cp /opt/opencode-config/opencode.json "$OPENCODE_CONFIG_DIR/opencode.json"
  fi
fi

# Seed openclaw auth if missing
OPENCLAW_AUTH_DIR="$HOME/.openclaw/agents/main/agent"
if [ ! -f "$OPENCLAW_AUTH_DIR/auth-profiles.json" ] || [ ! -s "$OPENCLAW_AUTH_DIR/auth-profiles.json" ]; then
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    mkdir -p "$OPENCLAW_AUTH_DIR"
    cat >"$OPENCLAW_AUTH_DIR/auth-profiles.json" <<CLAWEOF
{"version":1,"profiles":{"anthropic:oauth":{"type":"oauth","provider":"anthropic","access":"${CLAUDE_CODE_OAUTH_TOKEN}","refresh":"","expires":9999999999999}}}
CLAWEOF
  fi
fi

# Seed codex config if missing
CODEX_CONFIG_DIR="$HOME/.codex"
if [ ! -f "$CODEX_CONFIG_DIR/config.toml" ] || [ ! -s "$CODEX_CONFIG_DIR/config.toml" ]; then
  if [ -n "$OPENAI_API_KEY" ] && [ -f /opt/codex-config/config.toml ]; then
    mkdir -p "$CODEX_CONFIG_DIR"
    cp /opt/codex-config/config.toml "$CODEX_CONFIG_DIR/config.toml"
  fi
fi

# ============================================================
# SearXNG MCP server (web search via MCP)
# ============================================================
# Seed the MCP server config into Claude Code settings so the
# searxng tool always appears in the tool schema. This works
# regardless of provider type (direct API or proxy).
if [ -d /opt/searxng-mcp ]; then
  SETTINGS="$HOME/.claude/settings.json"
  SEARXNG_MCP_URL="${SEARXNG_BASE_URL:-http://searxng:8080}"
  mkdir -p "$HOME/.claude"
  if [ ! -f "$SETTINGS" ] || [ ! -s "$SETTINGS" ]; then
    echo '{}' >"$SETTINGS"
  fi
  if command -v jq >/dev/null 2>&1; then
    jq --arg url "$SEARXNG_MCP_URL" '
      .defaultMode = "bypassPermissions" |
      .skipDangerousModePermissionPrompt = true |
      .mcpServers.searxng = {
        "command": "/opt/searxng-mcp/.venv/bin/python",
        "args": ["/opt/searxng-mcp/server.py"],
        "env": {
          "SEARXNG_BASE_URL": $url,
          "TRANSPORT": "stdio"
        }
      }
    ' "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  fi
fi

# ============================================================
# Claude Code Proxy (Anthropic Messages API -> OpenAI)
# ============================================================
# Source the shared proxy startup function, then invoke it.
# The same function is sourced by interactive shells so the proxy
# auto-recovers even if it was not running at container start.
# shellcheck source=/dev/null
. /usr/local/lib/claude-proxy.sh
start_claude_proxy

# ============================================================
# VNC stack (Xvfb + fluxbox + x11vnc + noVNC)
# ============================================================
if [ "${ENABLE_VNC:-false}" = "true" ]; then
  VNC_RESOLUTION="${VNC_RESOLUTION:-1280x1024x24}"
  VNC_PORT="${VNC_PORT:-5900}"
  NOVNC_PORT="${NOVNC_PORT:-6080}"
  export DISPLAY="${DISPLAY:-:99}"

  Xvfb "${DISPLAY}" -screen 0 "${VNC_RESOLUTION}" -ac +extension GLX +render -noreset >/dev/null 2>&1 &

  # Background readiness check + dependent daemons — does NOT block entrypoint
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
