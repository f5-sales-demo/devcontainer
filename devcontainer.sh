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

# Timezone: macOS symlink -> IANA name, Linux -> /etc/timezone, fallback UTC
if [ -L /etc/localtime ]; then
  export TZ
  TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
elif [ -f /etc/timezone ]; then
  export TZ
  TZ=$(cat /etc/timezone)
fi
ok "Timezone: ${TZ:-UTC}"

# GitHub token: fresh from gh CLI
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    export GH_TOKEN
    GH_TOKEN=$(gh auth token 2>/dev/null)
    ok "GitHub: authenticated"
  else
    warn "GitHub: gh is installed but not authenticated (run: gh auth login)"
  fi
else
  warn "GitHub: gh CLI not found — GH_TOKEN will not be set"
fi

if [ ! -f .env ]; then
  warn "No .env file found. Container will start with defaults only."
fi

echo ""
exec podman compose up -d "$@"
