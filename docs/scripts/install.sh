#!/bin/bash
set -euo pipefail
# Bootstrap the devcontainer environment.
# Usage: curl -fsSL https://f5-sales-demo.github.io/devcontainer/scripts/install.sh | bash
exec bash <(curl -fsSL https://raw.githubusercontent.com/f5-sales-demo/devcontainer/main/devcontainer.sh)
