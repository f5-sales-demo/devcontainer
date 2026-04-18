#!/bin/bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main"
RETRY_COUNT=3
RETRY_DELAY=2

# ============================================================
# Helpers
# ============================================================
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
fatal() { fail "$@"; exit 1; }

# Download a URL to a local path with retries.
# Uses a temp file + atomic rename so a failed download never
# leaves a partial target file on disk.
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

# Require a command to be installed, print install hint on failure.
require() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "$cmd is not installed."
    [ -n "$hint" ] && info "$hint"
    return 1
  fi
  return 0
}

# ============================================================
# Install mode: download files to CWD when docker-compose.yml
# is missing (covers both "curl | bash" and first-run cases).
# ============================================================
if [ ! -f docker-compose.yml ]; then
  echo "Installing devcontainer into $(pwd) ..."
  echo ""

  require curl "Install with: brew install curl" || exit 1

  download "${REPO_BASE}/docker-compose.yml" docker-compose.yml || \
    fatal "Cannot continue without docker-compose.yml"
  ok "docker-compose.yml"

  download "${REPO_BASE}/devcontainer.sh" devcontainer.sh || \
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

  echo ""
  echo "Next steps:"
  echo "  1. Edit .env with your credentials:  vi .env"
  echo "  2. Start the container:              ./devcontainer.sh"
  exit 0
fi

# ============================================================
# Run mode: detect host environment and start the container.
# ============================================================
cd "$(dirname "$0")"

echo "Starting devcontainer ..."
echo ""

# --- preflight checks ---
_preflight_ok=true

if ! require podman "Install with: brew install podman"; then
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

# .env check
if [ ! -f .env ]; then
  warn "No .env file found. Container will start with defaults only."
fi

echo ""
exec podman compose up -d "$@"
