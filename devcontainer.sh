#!/bin/bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main"
RETRY_COUNT=3
RETRY_DELAY=2

# ============================================================
# Helpers
# ============================================================
info() { printf '  %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
fatal() {
  fail "$@"
  exit 1
}

download() {
  local url="$1" dest="$2" attempt=0 tmp
  tmp=$(mktemp "${dest}.XXXXXX")
  trap 'rm -f "$tmp"' RETURN
  while [ $attempt -lt $RETRY_COUNT ]; do
    attempt=$((attempt + 1))
    if curl -fsSL --connect-timeout 10 --retry 0 "$url" -o "$tmp" 2>/dev/null; then
      mv -f "$tmp" "$dest"
      trap - RETURN
      return 0
    fi
    if [ $attempt -lt $RETRY_COUNT ]; then
      warn "Download failed (attempt $attempt/$RETRY_COUNT), retrying in ${RETRY_DELAY}s ..."
      sleep "$RETRY_DELAY"
    fi
  done
  fail "Failed to download $url after $RETRY_COUNT attempts"
  return 1
}

brew_ensure() {
  local pkg="$1"
  if brew list --formula "$pkg" >/dev/null 2>&1 || brew list --cask "$pkg" >/dev/null 2>&1; then
    ok "$pkg (already installed)"
    return 0
  fi
  info "Installing $pkg ..."
  if brew install "$pkg" >/dev/null 2>&1; then
    ok "$pkg"
    return 0
  fi
  fail "Failed to install $pkg"
  return 1
}

# ============================================================
# Install mode: first-run bootstrap when docker-compose.yml
# is absent. Installs dependencies, configures the host, and
# downloads compose files.
# ============================================================
if [ ! -f docker-compose.yml ]; then

  echo ""
  echo "Devcontainer setup"
  echo "=================="
  echo ""

  # -- Homebrew -------------------------------------------------
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is not installed."
    info "Your IT department may provide Homebrew as managed software."
    info "Otherwise, see https://brew.sh for installation instructions."
    exit 1
  fi
  ok "Homebrew"

  # -- Packages -------------------------------------------------
  echo ""
  echo "Packages"
  echo "--------"
  brew_ensure podman
  brew_ensure podman-compose
  brew_ensure gh
  brew_ensure iterm2
  brew_ensure font-meslo-for-powerlevel10k
  brew_ensure font-meslo-lg-nerd-font

  # -- iTerm2 configuration -------------------------------------
  echo ""
  echo "iTerm2"
  echo "------"

  PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

  # Quit iTerm2 so plist changes aren't overwritten
  if pgrep -xq iTerm2; then
    info "Quitting iTerm2 to apply settings ..."
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null || true
    for _ in $(seq 1 20); do
      pgrep -xq iTerm2 || break
      sleep 0.5
    done
  fi

  # Generate default plist if iTerm2 has never been launched
  if [ ! -f "$PLIST" ]; then
    info "Launching iTerm2 once to generate defaults ..."
    open -a iTerm2
    for _ in $(seq 1 16); do
      [ -f "$PLIST" ] && break
      sleep 0.5
    done
    sleep 1
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null || true
    for _ in $(seq 1 20); do
      pgrep -xq iTerm2 || break
      sleep 0.5
    done
  fi

  if [ -f "$PLIST" ]; then
    if /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Normal Font\" \"MesloLGS-NF-Regular 13\"" "$PLIST" 2>/dev/null; then
      ok "Font: MesloLGS Nerd Font 13pt"
    else
      warn "Could not set font"
    fi
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Silence Bell\" true" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Visual Bell\" false" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Unlimited Scrollback\" true" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Option Key Sends\" 2" "$PLIST" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Right Option Key Sends\" 2" "$PLIST" 2>/dev/null
    ok "Terminal settings (bell, scrollback, option keys)"

    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 1 2>/dev/null
    ok "Dark theme"

    # Shift+Enter -> ESC[13;2u (Claude Code multi-line prompts)
    if /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Action" "$PLIST" >/dev/null 2>&1; then
      ok "Shift+Enter (already configured)"
    else
      if /usr/libexec/PlistBuddy \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24' dict" \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Version integer 2" \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':'Apply Mode' integer 0" \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Action integer 10" \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Text string [13;2u" \
        -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Escaping integer 2" \
        "$PLIST" 2>/dev/null; then
        ok "Shift+Enter mapped"
      else
        warn "Could not map Shift+Enter"
      fi
    fi
  else
    warn "iTerm2 plist not found, skipping configuration"
  fi

  # -- Podman machine -------------------------------------------
  echo ""
  echo "Podman machine"
  echo "--------------"

  if podman machine inspect >/dev/null 2>&1; then
    ok "Machine already initialized"
  else
    info "Initializing podman machine (16 GB RAM, 4 CPUs, 220 GB disk) ..."
    if podman machine init --memory 16384 --cpus 4 --disk-size 220; then
      ok "Machine initialized"
    else
      fatal "podman machine init failed"
    fi
  fi

  if podman machine info >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    ok "Machine running"
  else
    info "Starting podman machine ..."
    if podman machine start; then
      ok "Machine started"
    else
      fatal "podman machine start failed"
    fi
  fi

  # VM tuning: zram + swappiness
  _zram_size=$(podman machine ssh -- 'cat /etc/systemd/zram-generator.conf.d/override.conf 2>/dev/null' || true)
  if echo "$_zram_size" | grep -q 'zram-size = 4096'; then
    ok "VM zram tuning (already applied)"
  else
    info "Tuning VM: zram 4 GB zstd, swappiness 150 ..."
    podman machine ssh -- 'sudo mkdir -p /etc/systemd/zram-generator.conf.d && \
sudo tee /etc/systemd/zram-generator.conf.d/override.conf > /dev/null << EOF
[zram0]
zram-size = 4096
compression-algorithm = zstd
EOF'
    podman machine ssh -- 'echo "vm.swappiness=150" | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null'
    info "Restarting machine to apply VM tuning ..."
    podman machine stop
    podman machine start
    ok "VM tuning applied"
  fi

  # -- Download compose files -----------------------------------
  echo ""
  echo "Compose files"
  echo "-------------"

  download "${REPO_BASE}/docker-compose.yml" docker-compose.yml ||
    fatal "Cannot continue without docker-compose.yml"
  ok "docker-compose.yml"

  download "${REPO_BASE}/devcontainer.sh" devcontainer.sh ||
    fatal "Cannot continue without devcontainer.sh"
  chmod +x devcontainer.sh
  ok "devcontainer.sh"

  if [ ! -f .env ]; then
    if download "${REPO_BASE}/.env.example" .env; then
      ok ".env (created from template)"
    else
      warn "Could not download .env template. Create .env manually before starting."
    fi
  else
    ok ".env (already exists, left unchanged)"
  fi

  # -- Done -----------------------------------------------------
  echo ""
  echo "Setup complete."
  echo ""
  echo "Next steps:"
  echo "  1. Edit .env with your credentials:  vi .env"
  echo "  2. Start the container:              ./devcontainer.sh"
  exit 0
fi

# ============================================================
# Build mode: local arm64 image build with layer caching.
# Usage: ./devcontainer.sh build
# ============================================================
if [ "${1:-}" = "build" ]; then
  cd "$(dirname "$0")"

  if ! command -v podman >/dev/null 2>&1; then
    fatal "podman is not installed."
  fi

  if [ ! -f docker-compose.build.yml ]; then
    fatal "docker-compose.build.yml not found. Run from the repo root."
  fi

  echo "Building devcontainer (arm64, local layer cache) ..."
  echo ""
  shift
  exec podman compose -f docker-compose.yml -f docker-compose.build.yml build "$@"
fi

# ============================================================
# Run mode: detect host environment and start the container.
# ============================================================
cd "$(dirname "$0")"

# --- container name (stable per directory, unique across workspaces) ---
NAME_FILE=".devcontainer-name"
if [ -f "$NAME_FILE" ]; then
  DEVCONTAINER_NAME=$(cat "$NAME_FILE")
else
  DEVCONTAINER_NAME="devcontainer-$(date +%Y%m%d%H%M%S)"
  echo "$DEVCONTAINER_NAME" >"$NAME_FILE"
fi
export DEVCONTAINER_NAME

echo "Starting $DEVCONTAINER_NAME ..."
echo ""

# --- preflight checks ---
_preflight_ok=true

if ! command -v podman >/dev/null 2>&1; then
  fail "podman is not installed. Run this script without docker-compose.yml to trigger setup."
  _preflight_ok=false
fi

if command -v podman >/dev/null 2>&1; then
  if ! podman machine info >/dev/null 2>&1 && ! podman info >/dev/null 2>&1; then
    fail "Podman machine is not running."
    info "Start with: podman machine start"
    _preflight_ok=false
  fi
fi

if [ "$_preflight_ok" = false ]; then
  echo ""
  fatal "Fix the above errors and try again."
fi

# --- detect environment ---

# Source .env so auto-detect respects manual overrides.
# Variables already set in .env will not be overwritten.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env 2>/dev/null || true
  set +a
  ok ".env loaded"
else
  warn "No .env file found. Container will start with auto-detected values only."
fi

# Timezone: macOS symlink -> IANA name, Linux -> /etc/timezone, fallback UTC
if [ -z "${TZ:-}" ]; then
  if [ -L /etc/localtime ]; then
    export TZ
    TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
  elif [ -f /etc/timezone ]; then
    export TZ
    TZ=$(cat /etc/timezone)
  fi
  ok "Timezone: ${TZ:-UTC} (auto-detected)"
else
  ok "Timezone: $TZ (.env)"
fi

# Git config: author name and email
if [ -z "${GIT_AUTHOR_EMAIL:-}" ]; then
  if command -v git >/dev/null 2>&1; then
    _git_email=$(git config user.email 2>/dev/null || true)
    if [ -n "$_git_email" ]; then
      export GIT_AUTHOR_EMAIL="$_git_email"
      ok "Git: email=$_git_email (auto-detected)"
    else
      warn "Git: user.email not configured (run: git config --global user.email you@example.com)"
    fi
    unset _git_email
  fi
else
  ok "Git: email=$GIT_AUTHOR_EMAIL (.env)"
fi
if [ -z "${GIT_AUTHOR_NAME:-}" ]; then
  if command -v git >/dev/null 2>&1; then
    _git_name=$(git config user.name 2>/dev/null || true)
    if [ -n "$_git_name" ]; then
      export GIT_AUTHOR_NAME="$_git_name"
      ok "Git: name=$_git_name (auto-detected)"
    else
      warn "Git: user.name not configured (run: git config --global user.name 'Your Name')"
    fi
    unset _git_name
  fi
else
  ok "Git: name=$GIT_AUTHOR_NAME (.env)"
fi

# SSH key: ed25519 private key (base64-encoded)
if [ -z "${SSH_PRIVATE_KEY:-}" ]; then
  if [ -f "$HOME/.ssh/id_ed25519" ]; then
    export SSH_PRIVATE_KEY
    SSH_PRIVATE_KEY=$(base64 <"$HOME/.ssh/id_ed25519")
    ok "SSH: id_ed25519 (auto-detected)"
  fi
else
  ok "SSH: private key (.env)"
fi

# GitHub token: fresh from gh CLI
if [ -z "${GH_TOKEN:-}" ]; then
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      export GH_TOKEN
      GH_TOKEN=$(gh auth token 2>/dev/null)
      ok "GitHub: authenticated (auto-detected)"
    else
      warn "GitHub: gh is installed but not authenticated (run: gh auth login)"
    fi
  else
    warn "GitHub: gh CLI not found — GH_TOKEN will not be set"
  fi
else
  ok "GitHub: authenticated (.env)"
fi

# GitLab token: from glab CLI
if [ -z "${GITLAB_TOKEN:-}" ]; then
  if command -v glab >/dev/null 2>&1; then
    if glab auth status >/dev/null 2>&1; then
      export GITLAB_TOKEN
      GITLAB_TOKEN=$(glab config get token --host gitlab.com 2>/dev/null || true)
      if [ -n "$GITLAB_TOKEN" ]; then
        _glab_user=$(glab api /user --jq '.username' 2>/dev/null || true)
        ok "GitLab: authenticated${_glab_user:+ ($_glab_user)} (auto-detected)"
        unset _glab_user
      fi
    else
      warn "GitLab: glab is installed but not authenticated (run: glab auth login)"
    fi
  fi
else
  ok "GitLab: authenticated (.env)"
fi

# Azure CLI: forward host login session
if [ -z "${AZURE_CONFIG_BASE64:-}" ]; then
  if command -v az >/dev/null 2>&1; then
    if az account show >/dev/null 2>&1; then
      _az_user=$(az account show --query user.name -o tsv 2>/dev/null || true)
      export AZURE_CONFIG_BASE64
      AZURE_CONFIG_BASE64=$( (cd "$HOME/.azure" && tar czf - \
        azureProfile.json msal_token_cache.json msal_token_cache.bin \
        clouds.config service_principal_entries.json az.json 2>/dev/null) | base64)
      ok "Azure CLI: authenticated${_az_user:+ ($_az_user)} (auto-detected)"
      unset _az_user
    else
      warn "Azure CLI: az is installed but not authenticated (run: az login)"
    fi
  fi
else
  ok "Azure CLI: authenticated (.env)"
fi

# Salesforce CLI: sfdx auth URL for org login
if [ -z "${SFDX_AUTH_URL:-}" ]; then
  if command -v sf >/dev/null 2>&1; then
    if sf org list auth 2>/dev/null | grep -q Username; then
      _sfdx_url=$(sf org display --verbose --json 2>/dev/null | jq -r '.result.sfdxAuthUrl // empty' 2>/dev/null || true)
      if [ -n "$_sfdx_url" ]; then
        export SFDX_AUTH_URL="$_sfdx_url"
        ok "Salesforce: authenticated (auto-detected)"
      else
        warn "Salesforce: sf authenticated but could not extract auth URL"
      fi
      unset _sfdx_url
    else
      warn "Salesforce: sf is installed but not authenticated (run: sf org login web)"
    fi
  fi
else
  ok "Salesforce: authenticated (.env)"
fi

# Claude Code OAuth: extract from macOS keychain
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  if [ "$(uname)" = "Darwin" ]; then
    _claude_token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
      python3 -c "import sys,json; print(json.load(sys.stdin).get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null || true)
    if [ -n "$_claude_token" ]; then
      export CLAUDE_CODE_OAUTH_TOKEN="$_claude_token"
      ok "Claude Code: OAuth token (auto-detected from keychain)"
    fi
    unset _claude_token
  fi
else
  ok "Claude Code: OAuth token (.env)"
fi

# Google gog CLI: OAuth credentials and tokens
if command -v gog >/dev/null 2>&1; then
  if gog auth list --plain 2>/dev/null | head -1 | grep -q .; then
    if [ -z "${GOG_ACCOUNT:-}" ]; then
      export GOG_ACCOUNT
      GOG_ACCOUNT=$(gog auth list --plain 2>/dev/null | head -1 | cut -f1)
      ok "gog: account=$GOG_ACCOUNT (auto-detected)"
    else
      ok "gog: account=$GOG_ACCOUNT (.env)"
    fi
    if [ -z "${GOG_CREDENTIALS_JSON:-}" ]; then
      _cred_path=$(gog auth status --plain 2>/dev/null | grep credentials_path | cut -f2)
      if [ -n "$_cred_path" ] && [ -f "$_cred_path" ]; then
        export GOG_CREDENTIALS_JSON
        GOG_CREDENTIALS_JSON=$(base64 <"$_cred_path")
        ok "gog: credentials (auto-detected)"
      fi
      unset _cred_path
    else
      ok "gog: credentials (.env)"
    fi
    if [ -z "${GOG_TOKEN_JSON:-}" ] && [ -n "${GOG_ACCOUNT:-}" ]; then
      _gog_tmp=$(mktemp)
      if gog auth tokens export "$GOG_ACCOUNT" --out "$_gog_tmp" --overwrite 2>/dev/null; then
        export GOG_TOKEN_JSON
        GOG_TOKEN_JSON=$(base64 <"$_gog_tmp")
        ok "gog: tokens (auto-detected)"
      fi
      rm -f "$_gog_tmp"
      unset _gog_tmp
    elif [ -n "${GOG_TOKEN_JSON:-}" ]; then
      ok "gog: tokens (.env)"
    fi
  fi
fi

# Google Workspace CLI (gws): OAuth credentials
if [ -f "$HOME/.config/gws/client_secret.json" ] || [ -n "${GWS_CLIENT_SECRET_JSON:-}" ]; then
  if [ -z "${GWS_CLIENT_SECRET_JSON:-}" ]; then
    export GWS_CLIENT_SECRET_JSON
    GWS_CLIENT_SECRET_JSON=$(base64 <"$HOME/.config/gws/client_secret.json")
    ok "gws: client_secret (auto-detected)"
  else
    ok "gws: client_secret (.env)"
  fi
  if [ -z "${GWS_ENCRYPTION_KEY:-}" ]; then
    _gws_key=$(security find-generic-password -s "gws-cli" -w 2>/dev/null ||
      cat "$HOME/.config/gws/.encryption_key" 2>/dev/null || true)
    if [ -n "$_gws_key" ]; then
      export GWS_ENCRYPTION_KEY="$_gws_key"
      ok "gws: encryption key (auto-detected)"
    fi
    unset _gws_key
  else
    ok "gws: encryption key (.env)"
  fi
  if [ -z "${GWS_CREDENTIALS_ENC:-}" ] && [ -f "$HOME/.config/gws/credentials.enc" ]; then
    export GWS_CREDENTIALS_ENC
    GWS_CREDENTIALS_ENC=$(base64 <"$HOME/.config/gws/credentials.enc")
    ok "gws: credentials (auto-detected)"
  elif [ -n "${GWS_CREDENTIALS_ENC:-}" ]; then
    ok "gws: credentials (.env)"
  fi
  if [ -z "${GWS_TOKEN_CACHE:-}" ] && [ -f "$HOME/.config/gws/token_cache.json" ]; then
    export GWS_TOKEN_CACHE
    GWS_TOKEN_CACHE=$(base64 <"$HOME/.config/gws/token_cache.json")
    ok "gws: token_cache (auto-detected)"
  elif [ -n "${GWS_TOKEN_CACHE:-}" ]; then
    ok "gws: token_cache (.env)"
  fi
fi

# Podman host socket for Docker-outside-of-Docker.
# On macOS the container runs inside the podman-machine VM, so we use the
# VM-internal rootless socket path (the Mac-side proxy socket lives on
# virtiofs, where podman's statfs validation fails). On Linux we use the
# local rootless socket directly. Override by setting DOCKER_SOCK in .env.
if [ -z "${DOCKER_SOCK:-}" ]; then
  if [ "$(uname)" = "Darwin" ]; then
    _detected_sock=$(podman machine ssh -- 'echo /run/user/$(id -u)/podman/podman.sock' 2>/dev/null | tr -d '\r' || true)
    if [ -n "$_detected_sock" ] &&
      podman machine ssh -- "test -S $_detected_sock" >/dev/null 2>&1; then
      export DOCKER_SOCK="$_detected_sock"
      ok "Podman socket: $DOCKER_SOCK (in machine VM)"
    else
      fail "Podman socket not available in machine VM."
      info "Start the podman machine: podman machine start"
      info "Or set DOCKER_SOCK in .env to override detection."
      fatal "Cannot start container without a host runtime socket."
    fi
    unset _detected_sock
  else
    _detected_sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
    if [ -S "$_detected_sock" ]; then
      export DOCKER_SOCK="$_detected_sock"
      ok "Podman socket: $DOCKER_SOCK"
    else
      fail "Podman socket not found at: $_detected_sock"
      info "Start the user socket: systemctl --user start podman.socket"
      info "Or set DOCKER_SOCK in .env to override detection."
      fatal "Cannot start container without a host runtime socket."
    fi
    unset _detected_sock
  fi
fi

echo ""
exec podman compose up -d "$@"
