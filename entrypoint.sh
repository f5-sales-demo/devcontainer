#!/bin/bash
# Fix volume permissions
for dir in "$HOME/.cache" "$HOME/.local" "$HOME/.claude" "$HOME/.ssh"; do
    if [ -d "$dir" ] && [ ! -O "$dir" ]; then
        sudo chown -R "$(id -u):$(id -g)" "$dir" 2>/dev/null || true
    fi
done

if [ ! -O "$HOME" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME" 2>/dev/null || true
fi

# Configure npm to use home directory for global installs
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$NPM_CONFIG_PREFIX/bin"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$NPM_CONFIG_PREFIX/bin:$PATH"

# ============================================================
# Install AI coding tools on first boot
# ============================================================

# Claude Code — native installer
if ! command -v claude &> /dev/null; then
    echo "  📦 Installing Claude Code (native)..."
    curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && bash /tmp/claude-install.sh && rm -f /tmp/claude-install.sh
fi

# OpenCode — native installer
if ! command -v opencode &> /dev/null; then
    echo "  📦 Installing OpenCode (native)..."
    curl -fsSL https://opencode.ai/install -o /tmp/opencode-install.sh && bash /tmp/opencode-install.sh && rm -f /tmp/opencode-install.sh
fi

# Codex — npm (bundles native Rust binary)
if ! command -v codex &> /dev/null; then
    echo "  📦 Installing Codex (npm)..."
    npm install -g @openai/codex 2>/dev/null
fi

# OpenClaw — npm
if ! command -v openclaw &> /dev/null; then
    echo "  📦 Installing OpenClaw (npm)..."
    npm install -g openclaw 2>/dev/null
fi

# ============================================================
# Configure user environment
# ============================================================

if [ -n "$GIT_AUTHOR_NAME" ]; then
    git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
    git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

if [ -n "$SSH_PRIVATE_KEY" ]; then
    mkdir -p "$HOME/.ssh"
    echo "$SSH_PRIVATE_KEY" | base64 -d > "$HOME/.ssh/id_ed25519"
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh/id_ed25519"
    ssh-keygen -y -f "$HOME/.ssh/id_ed25519" > "$HOME/.ssh/id_ed25519.pub" 2>/dev/null
    if [ ! -f "$HOME/.ssh/config" ]; then
        cat > "$HOME/.ssh/config" << 'SSHCONF'
Host github.com
    StrictHostKeyChecking accept-new
    IdentityFile ~/.ssh/id_ed25519
Host *
    StrictHostKeyChecking accept-new
SSHCONF
        chmod 600 "$HOME/.ssh/config"
    fi
fi

if [ ! -f "$HOME/.claude.json" ] || [ ! -s "$HOME/.claude.json" ]; then
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
fi

# Write PATH config for interactive shells
cat > "$HOME/.path.sh" << PATHEOF
export NPM_CONFIG_PREFIX="\$HOME/.npm-global"
export PATH="\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.npm-global/bin:\$PATH"
PATHEOF

# Source it from zshrc/bashrc if not already there
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && ! grep -q ".path.sh" "$rc" 2>/dev/null; then
        echo 'source "$HOME/.path.sh"' >> "$rc"
    fi
done

exec "$@"
