#!/bin/bash
# Setup lazy.nvim plugin manager and install all neovim plugins.
# Designed to run during container image build (no token needed).
set -euo pipefail

LAZY_DIR="${HOME}/.local/share/nvim/lazy/lazy.nvim"

# Install lazy.nvim if not present
if [ ! -d "${LAZY_DIR}" ]; then
  git clone --filter=blob:none \
    https://github.com/folke/lazy.nvim.git \
    --branch=stable \
    "${LAZY_DIR}" 2>&1 | grep -v "is not a commit"
fi

# Remove legacy native-pack plugins (if any)
rm -rf "${HOME}/.local/share/nvim/site/pack/plugins/start"

# Remove legacy init.vim (superseded by init.lua)
rm -f "${HOME}/.config/nvim/init.vim"

# Install all plugins headlessly
nvim --headless "+Lazy! sync" +qa
