#!/bin/bash
set -euo pipefail
# Bootstrap the devcontainer environment.
# Usage: curl -fsSL https://f5xc-salesdemos.github.io/devcontainer/scripts/install.sh | bash
exec bash <(curl -fsSL https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/devcontainer.sh)
