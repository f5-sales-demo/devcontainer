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

# ============================================================
# Configure user environment
# ============================================================

# Git config from env vars
if [ -n "$GIT_AUTHOR_NAME" ]; then
    git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
    git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

# SSH key from env var (base64 encoded)
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

# Seed Claude Code config if missing
if [ ! -f "$HOME/.claude.json" ] || [ ! -s "$HOME/.claude.json" ]; then
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
fi

# Install OpenClaw (npm, no devcontainer feature available yet)
if ! command -v openclaw &> /dev/null; then
    npm install -g openclaw 2>/dev/null &
fi

exec "$@"
