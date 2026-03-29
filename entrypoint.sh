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

# Ensure Homebrew npm global directory exists (issue #677)
mkdir -p "${HOME}/.npm-global/lib" 2>/dev/null || true

sudo cron 2>/dev/null || true

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
  # claude-mem strips ANTHROPIC_API_KEY from process.env for security;
  # it only reads the key from its own ~/.claude-mem/.env file.
  mkdir -p "$HOME/.claude-mem"
  printf 'ANTHROPIC_API_KEY=%s\n' "$LITELLM_API_KEY" >"$HOME/.claude-mem/.env"
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
# Hermes Agent config (LiteLLM proxy vs Anthropic OAuth)
# Writes ~/.hermes/.env so Hermes picks up credentials at startup.
# Hermes reads OPENAI_BASE_URL + OPENAI_API_KEY for custom endpoints
# and ANTHROPIC_TOKEN for Anthropic native auth.
# ============================================================
HERMES_HOME_DIR="$HOME/.hermes"
mkdir -p "$HERMES_HOME_DIR"
if [ -n "$LITELLM_API_KEY" ]; then
  printf 'OPENAI_BASE_URL=%s\nOPENAI_API_KEY=%s\nLLM_MODEL=claude-opus-4-6\n' \
    "$OPENAI_BASE_URL" "$OPENAI_API_KEY" \
    >"$HERMES_HOME_DIR/.env"
elif [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  printf 'ANTHROPIC_TOKEN=%s\n' "$ANTHROPIC_OAUTH_TOKEN" \
    >"$HERMES_HOME_DIR/.env"
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
# Clean up stale processes on claude-mem worker port (issue #676)
# Prevents port 37777 conflict when SessionStart hook triggers
# the claude-mem worker before a previous instance has released.
# ============================================================
if command -v fuser >/dev/null 2>&1; then
  fuser -k 37777/tcp >/dev/null 2>&1 || true
fi

# ============================================================
# Fix plugin script permissions and neutralize disabled hooks
#
# Two upstream bugs require workarounds:
#   - Issue #648: Plugin syncs reset .sh permissions to 644
#   - cc#40013: Claude Code fires hooks from ALL plugins, not
#     just enabled ones (causes SessionStart errors)
#
# Three-layer fix:
#   1. Persistent background daemon (inotifywait or polling)
#      watches for plugin syncs and immediately re-applies
#      chmod +x and neutralizes non-enabled plugin hooks
#   2. SessionStart hook — immediate chmod + neutralize when
#      a new session starts (concurrent with plugin hooks)
#   3. PostToolUse hook (matcher: Skill) — catches mid-session
#      /reload-plugins
#
# Build-time: install-plugins.sh also sets permissions and
# neutralizes at image build time (baseline state).
#
# Remove all when upstream issues #648 and cc#40013 are resolved.
# ============================================================

# Ensure every enabled cached plugin has a marketplace directory entry.
# Claude Code resolves plugin paths from marketplaces/<mkt>/plugins/<name>/
# Plugins installed from external sources (GitHub clones) only exist in
# cache — create marketplace symlinks so Claude Code can find them.
ensure_marketplace_dirs() {
  local settings="${HOME}/.claude/settings.json"
  [ -f "$settings" ] || return 0
  local plugin_base="${HOME}/.claude/plugins"

  local key name mkt mkt_dir cache_entry
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    name="${key%%@*}"
    mkt="${key#*@}"
    mkt_dir="${plugin_base}/marketplaces/${mkt}/plugins/${name}"

    # Skip if marketplace dir already exists
    [ -d "$mkt_dir" ] && continue

    # Find the cache entry for this plugin (use first version found)
    cache_entry=$(find "${plugin_base}/cache/${mkt}/${name}" \
      -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
    [ -n "$cache_entry" ] || continue

    # Create parent dir and symlink
    mkdir -p "$(dirname "$mkt_dir")" 2>/dev/null || true
    ln -sf "$cache_entry" "$mkt_dir" 2>/dev/null || true
  done < <(jq -r '.enabledPlugins | keys[]' "$settings" 2>/dev/null)
}

# Neutralize hooks from non-enabled marketplace plugins (cc#40013)
# Claude Code loads hooks from ALL installed plugins, not just enabled ones.
# Replace hooks.json with {} for any plugin not in enabledPlugins.
neutralize_non_enabled_hooks() {
  local settings="${HOME}/.claude/settings.json"
  [ -f "$settings" ] || return 0
  for mkt_dir in "${HOME}/.claude/plugins/marketplaces"/*/; do
    [ -d "$mkt_dir" ] || continue
    local mkt_name
    mkt_name=$(basename "$mkt_dir")
    local plugin_dir="${mkt_dir}plugins"
    [ -d "$plugin_dir" ] || continue
    for plugin in "$plugin_dir"/*/; do
      [ -d "$plugin" ] || continue
      local plugin_name
      plugin_name=$(basename "$plugin")
      local key="${plugin_name}@${mkt_name}"
      local hooks_file="${plugin}hooks/hooks.json"
      local hooks_dir="${plugin}hooks"
      [ -f "$hooks_file" ] || continue
      if jq -e --arg k "$key" '.enabledPlugins[$k]' "$settings" >/dev/null 2>&1; then
        # Enabled plugin: restore normal permissions (handles disable->enable)
        chmod 755 "$hooks_dir" 2>/dev/null || true
        chmod 644 "$hooks_file" 2>/dev/null || true
        continue
      fi
      # Skip if already neutralized (idempotent)
      local current
      current=$(cat "$hooks_file" 2>/dev/null || true)
      if [ "$current" = "{}" ]; then
        chmod 755 "$hooks_dir" 2>/dev/null || true
        chmod 444 "$hooks_file" 2>/dev/null || true
        continue
      fi
      # Non-enabled plugin: neutralize and lock with chmod
      chmod 755 "$hooks_dir" 2>/dev/null || true
      chmod 644 "$hooks_file" 2>/dev/null || true
      echo '{}' >"$hooks_file"
      chmod 444 "$hooks_file"
    done
  done

  # Second pass: neutralize hooks.json at non-standard paths (monorepo marketplaces)
  # e.g. thedotmack/cursor-hooks/hooks.json (not under plugins/)
  local plugin_base="${HOME}/.claude/plugins"
  local hf hd hf_parent hf_parent_real skip link link_target link_name link_mkt current
  while IFS= read -r hf; do
    [ -f "$hf" ] || continue
    echo "$hf" | grep -q '/marketplaces/[^/]*/plugins/[^/]*/hooks/hooks.json$' && continue
    hd=$(dirname "$hf")
    hf_parent=$(dirname "$hd")
    hf_parent_real=$(readlink -f "$hf_parent" 2>/dev/null || echo "$hf_parent")
    skip=false
    for link in "$plugin_base"/marketplaces/*/plugins/*/; do
      [ -L "${link%/}" ] || continue
      link_target=$(readlink -f "${link%/}" 2>/dev/null || true)
      [ -n "$link_target" ] || continue
      if [ "$hf_parent_real" = "$link_target" ]; then
        link_name=$(basename "${link%/}")
        link_mkt=$(basename "$(dirname "$(dirname "${link%/}")")")
        if jq -e --arg k "${link_name}@${link_mkt}" '.enabledPlugins[$k]' "$settings" >/dev/null 2>&1; then
          skip=true
          break
        fi
      fi
    done
    if [ "$skip" = true ]; then
      continue
    fi
    current=$(cat "$hf" 2>/dev/null || true)
    if [ "$current" = "{}" ]; then
      chmod 755 "$hd" 2>/dev/null || true
      chmod 444 "$hf" 2>/dev/null || true
      continue
    fi
    chmod 755 "$hd" 2>/dev/null || true
    chmod 644 "$hf" 2>/dev/null || true
    echo '{}' >"$hf" 2>/dev/null || true
    chmod 444 "$hf" 2>/dev/null || true
  done < <(find "$plugin_base/marketplaces" -name "hooks.json" 2>/dev/null)
}

ensure_marketplace_dirs
find "${HOME}/.claude/plugins" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null || true
neutralize_non_enabled_hooks

# Persistent background daemon (Layer 1)
# Phase 1: poll every 1-2s for 60s (catches initial dual plugin syncs
#   and staging marketplace creation)
# Phase 2: inotifywait or 10s polling indefinitely (catches plugin
#   re-syncs when new sessions start in long-lived containers)
(
  # Phase 1: aggressive polling — 1s for first 10s, then 2s for 50s
  elapsed=0
  while [ "$elapsed" -lt 60 ]; do
    if [ "$elapsed" -lt 10 ]; then
      sleep 1
    else
      sleep 2
    fi
    ensure_marketplace_dirs
    find "${HOME}/.claude/plugins" -name "*.sh" -type f \
      ! -perm -u+x -exec chmod +x {} + 2>/dev/null
    neutralize_non_enabled_hooks
    elapsed=$((elapsed + $([ "$elapsed" -lt 10 ] && echo 1 || echo 2)))
  done

  # Phase 2: event-driven watch (falls back to polling if inotifywait unavailable)
  if command -v inotifywait >/dev/null 2>&1; then
    while true; do
      inotifywait -qq -r -e modify,create,moved_to,moved_from \
        "${HOME}/.claude/plugins/marketplaces" 2>/dev/null
      # No sleep — neutralize IMMEDIATELY after filesystem event
      ensure_marketplace_dirs
      find "${HOME}/.claude/plugins" -name "*.sh" -type f \
        ! -perm -u+x -exec chmod +x {} + 2>/dev/null
      neutralize_non_enabled_hooks
    done
  else
    while true; do
      sleep 10
      ensure_marketplace_dirs
      find "${HOME}/.claude/plugins" -name "*.sh" -type f \
        ! -perm -u+x -exec chmod +x {} + 2>/dev/null
      neutralize_non_enabled_hooks
    done
  fi
) >/dev/null 2>&1 &

# Inject SessionStart + PostToolUse hooks from template into runtime settings.json
# The template at /opt/claude-config/settings.json has the canonical hook definitions.
# This ensures runtime hooks stay in sync without fragile Python string escaping.
SETTINGS="${HOME}/.claude/settings.json"
TEMPLATE="/opt/claude-config/settings.json"
if [ -f "$SETTINGS" ] && [ -f "$TEMPLATE" ] && command -v jq >/dev/null 2>&1; then
  TEMPLATE_HOOKS=$(jq '.hooks' "$TEMPLATE" 2>/dev/null)
  if [ -n "$TEMPLATE_HOOKS" ] && [ "$TEMPLATE_HOOKS" != "null" ]; then
    CURRENT_HOOKS=$(jq '.hooks' "$SETTINGS" 2>/dev/null)
    if [ "$CURRENT_HOOKS" != "$TEMPLATE_HOOKS" ]; then
      jq --argjson hooks "$TEMPLATE_HOOKS" '.hooks = $hooks' "$SETTINGS" >"${SETTINGS}.tmp" &&
        mv "${SETTINGS}.tmp" "$SETTINGS"
    fi
  fi
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
