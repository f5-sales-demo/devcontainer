#!/bin/bash
# Nightly package update script for the devcontainer.
# Runs as the vscode user via cron. APT commands use sudo.
# Logs to /tmp/nightly-update.log (rotated on each run).
set -euo pipefail

LOG="/tmp/nightly-update.log"
LOCK="/tmp/nightly-update.lock"

exec >"$LOG" 2>&1

if [ -e "$LOCK" ]; then
  echo "$(date -u +%FT%TZ) SKIP: previous run still in progress"
  exit 0
fi
trap 'rm -f "$LOCK"' EXIT
touch "$LOCK"

echo "$(date -u +%FT%TZ) START nightly-update"

# ── APT (security patches only) ──
echo "--- APT ---"
sudo apt-get update -qq
sudo apt-get upgrade -y -qq --only-upgrade \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Options::="--force-confdef"
sudo apt-get autoremove -y -qq
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# ── Homebrew (Linuxbrew) ──
echo "--- Homebrew ---"
if command -v brew >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=0 brew update --quiet
  brew upgrade --quiet 2>&1 || true
  brew cleanup --prune=all -s 2>&1 || true
fi

# ── npm global packages ──
echo "--- npm ---"
if command -v npm >/dev/null 2>&1; then
  npm update -g --loglevel=warn 2>&1 || true
fi

# ── pip (system packages, security only) ──
echo "--- pip ---"
if command -v pip >/dev/null 2>&1; then
  pip install --no-cache-dir --break-system-packages --upgrade pip 2>&1 || true
  pip list --outdated --format=json 2>/dev/null |
    python3 -c "import sys,json; [print(p['name']) for p in json.load(sys.stdin)]" 2>/dev/null |
    xargs -r pip install --no-cache-dir --break-system-packages --upgrade 2>&1 || true
fi

# ── uv-managed tools ──
echo "--- uv ---"
if command -v uv >/dev/null 2>&1; then
  uv self update 2>&1 || true
  UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool upgrade --all 2>&1 || true
fi

# ── Ruby gems ──
echo "--- gem ---"
if command -v gem >/dev/null 2>&1; then
  sudo gem update --no-document 2>&1 || true
fi

# ── Go binaries (gopls, golangci-lint) ──
echo "--- go ---"
if command -v go >/dev/null 2>&1; then
  GOBIN=/usr/local/bin go install golang.org/x/tools/gopls@latest 2>&1 || true
fi

# ── Rust toolchain ──
echo "--- rust ---"
if command -v rustup >/dev/null 2>&1; then
  rustup update stable 2>&1 || true
fi

# ── Playwright browsers ──
echo "--- playwright ---"
if command -v npx >/dev/null 2>&1; then
  npx playwright install 2>&1 || true
fi

echo "$(date -u +%FT%TZ) DONE nightly-update"
