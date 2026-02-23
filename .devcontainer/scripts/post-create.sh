#!/bin/bash
set -e

echo "🔧 Running post-create setup..."

# Python tools (installed after Python feature)
echo "  📦 Installing Python tools..."
pip install --user \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint \
    2>/dev/null

# npm tools (installed after Node feature)
echo "  📦 Installing npm tools..."
npm install -g markdownlint-cli2 2>/dev/null

# OpenClaw (no devcontainer feature available)
echo "  📦 Installing OpenClaw..."
npm install -g openclaw 2>/dev/null

echo "✅ Post-create setup complete"
