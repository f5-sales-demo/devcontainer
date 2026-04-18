#!/bin/bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main"

# ============================================================
# Install mode: download files to CWD when docker-compose.yml
# is missing (covers both "curl | bash" and first-run cases).
# ============================================================
if [ ! -f docker-compose.yml ]; then
  echo "Installing devcontainer into $(pwd) ..."

  # Download to temp files first — atomic rename prevents partial writes
  # from leaving a corrupt docker-compose.yml that tricks run mode.
  _tmp_compose=$(mktemp docker-compose.yml.XXXXXX)
  _tmp_script=$(mktemp devcontainer.sh.XXXXXX)
  trap 'rm -f "$_tmp_compose" "$_tmp_script"' EXIT

  curl -fsSL "${REPO_BASE}/docker-compose.yml" -o "$_tmp_compose"
  curl -fsSL "${REPO_BASE}/devcontainer.sh"    -o "$_tmp_script"

  mv -f "$_tmp_compose" docker-compose.yml
  mv -f "$_tmp_script"  devcontainer.sh
  chmod +x devcontainer.sh
  trap - EXIT

  if [ ! -f .env ]; then
    curl -fsSL "${REPO_BASE}/.env.example" -o .env
    echo ""
    echo "Created .env from template. Edit it with your credentials:"
    echo "  vi .env"
    echo ""
    echo "Then start the container:"
    echo "  ./devcontainer.sh"
  else
    echo ""
    echo ".env already exists, left unchanged."
    echo ""
    echo "Start the container:"
    echo "  ./devcontainer.sh"
  fi

  exit 0
fi

# ============================================================
# Run mode: detect host environment and start the container.
# ============================================================
cd "$(dirname "$0")"

if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is not installed." >&2
  exit 1
fi

# Timezone: macOS symlink -> IANA name, Linux -> /etc/timezone, fallback UTC
if [ -L /etc/localtime ]; then
  export TZ
  TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
elif [ -f /etc/timezone ]; then
  export TZ
  TZ=$(cat /etc/timezone)
fi

# GitHub token: fresh from gh CLI
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  export GH_TOKEN
  GH_TOKEN=$(gh auth token 2>/dev/null)
fi

exec podman compose up -d "$@"
