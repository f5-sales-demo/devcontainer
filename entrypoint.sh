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
  echo "$SSH_PRIVATE_KEY" | base64 -d >"$HOME/.ssh/id_ed25519"
  chmod 700 "$HOME/.ssh"
  chmod 600 "$HOME/.ssh/id_ed25519"
  ssh-keygen -y -f "$HOME/.ssh/id_ed25519" >"$HOME/.ssh/id_ed25519.pub" 2>/dev/null
  if [ ! -f "$HOME/.ssh/config" ]; then
    cat >"$HOME/.ssh/config" <<'SSHCONF'
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
  echo '{"hasCompletedOnboarding": true}' >"$HOME/.claude.json"
fi

# ============================================================
# Claude Code tool awareness (global User-level CLAUDE.md)
# ============================================================
# ~/.claude/CLAUDE.md is loaded in every Claude Code session regardless
# of the working directory. Seed it once; never overwrite user edits.
if [ ! -f "$HOME/.claude/CLAUDE.md" ]; then
  mkdir -p "$HOME/.claude"
  cp /opt/claude-config/CLAUDE.md "$HOME/.claude/CLAUDE.md"
fi

# ============================================================
# Docker-in-Docker (start dockerd if running in privileged mode)
# ============================================================
if [ "${ENABLE_DOCKER:-true}" = "true" ] && command -v dockerd >/dev/null 2>&1; then
  # Only start if we're in a privileged container (cgroup access required)
  if [ -d /sys/fs/cgroup ]; then
    sudo dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2375 >/var/log/dockerd.log 2>&1 &
    # Wait for Docker daemon to be ready
    retries=0
    while [ $retries -lt 30 ]; do
      docker info >/dev/null 2>&1 && break
      sleep 1
      retries=$((retries + 1))
    done
    if docker info >/dev/null 2>&1; then
      echo "Docker daemon started successfully"
    else
      echo "Warning: Docker daemon failed to start (not running in privileged mode?)" >&2
    fi
  fi
fi

# ============================================================
# VNC stack (Xvfb + fluxbox + x11vnc + noVNC)
# ============================================================
if [ "${ENABLE_VNC:-true}" = "true" ]; then
  VNC_RESOLUTION="${VNC_RESOLUTION:-1280x1024x24}"
  VNC_PORT="${VNC_PORT:-5900}"
  NOVNC_PORT="${NOVNC_PORT:-6080}"
  export DISPLAY="${DISPLAY:-:99}"

  Xvfb "${DISPLAY}" -screen 0 "${VNC_RESOLUTION}" -ac +extension GLX +render -noreset &

  retries=0
  while [ $retries -lt 50 ]; do
    xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1 && break
    sleep 0.1
    retries=$((retries + 1))
  done

  fluxbox &
  x11vnc -display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" \
    -nopw -xkb -noxrecord -noxfixes -noxdamage &

  NOVNC_LAUNCHER=""
  for candidate in \
    /usr/share/novnc/utils/novnc_proxy \
    /usr/share/novnc/utils/launch.sh \
    /usr/share/novnc/utils/websockify/run; do
    if [ -x "$candidate" ]; then
      NOVNC_LAUNCHER="$candidate"
      break
    fi
  done

  if [ -n "$NOVNC_LAUNCHER" ]; then
    "$NOVNC_LAUNCHER" --vnc localhost:"${VNC_PORT}" --listen "${NOVNC_PORT}" &
  else
    websockify --web /usr/share/novnc "${NOVNC_PORT}" localhost:"${VNC_PORT}" &
  fi

  echo "noVNC: http://localhost:${NOVNC_PORT}/vnc.html"
fi

exec "$@"
