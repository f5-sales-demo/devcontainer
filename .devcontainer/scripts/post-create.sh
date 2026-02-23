#!/bin/bash
set -e

echo "🔧 Running post-create setup..."

# Python tools (installed after Python feature is available)
if command -v pip &> /dev/null; then
    echo "  📦 Installing Python tools..."
    pip install --break-system-packages \
        pre-commit \
        ansible \
        black \
        pylint \
        yamllint \
        2>/dev/null || pip install \
        pre-commit \
        ansible \
        black \
        pylint \
        yamllint
fi

# npm tools (installed after Node feature is available)
if command -v npm &> /dev/null; then
    echo "  📦 Installing npm tools..."
    npm install -g markdownlint-cli2 2>/dev/null || true
fi

# OpenClaw (no devcontainer feature available yet)
if ! command -v openclaw &> /dev/null && command -v npm &> /dev/null; then
    echo "  📦 Installing OpenClaw..."
    npm install -g openclaw 2>/dev/null || true
fi

echo "✅ Post-create setup complete"
