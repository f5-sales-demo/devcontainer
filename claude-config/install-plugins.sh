#!/usr/bin/env bash
# Pre-install Claude Code plugins into the cache directory.
# Called from Dockerfile section 12l after the marketplace clone.
set -euo pipefail

PLUGIN_BASE="$1" # e.g. /home/vscode/.claude/plugins
SETTINGS="$2"    # e.g. /opt/claude-config/settings.json
MARKETPLACE="${PLUGIN_BASE}/marketplaces/claude-plugins-official"
CACHE="${PLUGIN_BASE}/cache/claude-plugins-official"
INSTALLED_JSON="${PLUGIN_BASE}/installed_plugins.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
GIT_SHA=$(cd "$MARKETPLACE" && git rev-parse HEAD)

mkdir -p "$CACHE"

# Opencode skill directory — symlinks are created per-plugin below
# Uses opencode-only path to avoid duplicate discovery in Claude Code
HOME_DIR=$(dirname "$(dirname "$PLUGIN_BASE")")
OPENCODE_SKILLS="${HOME_DIR}/.config/opencode/skill"
mkdir -p "$OPENCODE_SKILLS"

# Start building installed_plugins.json
echo '[' >"$INSTALLED_JSON"
FIRST=true

# Read enabled plugin names from settings.json
# Format: "name@claude-plugins-official" -> extract "name"
PLUGINS=$(jq -r '.enabledPlugins | keys[] | split("@")[0]' "$SETTINGS")

for NAME in $PLUGINS; do
  # Determine source path in marketplace
  SRC=""
  if [ -d "${MARKETPLACE}/plugins/${NAME}" ]; then
    SRC="${MARKETPLACE}/plugins/${NAME}"
  elif [ -d "${MARKETPLACE}/external_plugins/${NAME}" ]; then
    SRC="${MARKETPLACE}/external_plugins/${NAME}"
  fi

  # Read version from plugin.json (default 0.0.0)
  VERSION="0.0.0"
  PJSON=""
  if [ -n "$SRC" ]; then
    PJSON="${SRC}/.claude-plugin/plugin.json"
  fi
  if [ -n "$PJSON" ] && [ -f "$PJSON" ]; then
    V=$(jq -r '.version // empty' "$PJSON")
    [ -n "$V" ] && VERSION="$V"
  fi

  DEST="${CACHE}/${NAME}/${VERSION}"
  mkdir -p "$DEST"

  if [ -n "$SRC" ]; then
    # Local marketplace plugin -- copy
    cp -a "${SRC}/." "$DEST/"
  elif [ "$NAME" = "superpowers" ]; then
    # External URL plugin -- clone at build time
    git clone --depth=1 --single-branch --branch main \
      https://github.com/obra/superpowers.git "$DEST"
  else
    echo "WARNING: no source found for plugin '$NAME', skipping"
    rm -rf "$DEST"
    continue
  fi

  # Symlink plugin skills into opencode's skill directory
  # (Claude Code already loads these via its plugin system)
  if [ -d "${DEST}/skills" ]; then
    for SKILL_PATH in "${DEST}"/skills/*/SKILL.md; do
      [ -f "$SKILL_PATH" ] || continue
      SKILL_NAME=$(basename "$(dirname "$SKILL_PATH")")
      if [ ! -e "${OPENCODE_SKILLS}/${SKILL_NAME}" ]; then
        ln -s "$(dirname "$SKILL_PATH")" "${OPENCODE_SKILLS}/${SKILL_NAME}"
      fi
    done
  fi

  # Append entry to installed_plugins.json
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo ',' >>"$INSTALLED_JSON"
  fi

  cat >>"$INSTALLED_JSON" <<ENTRY
  {
    "name": "${NAME}",
    "marketplace": "claude-plugins-official",
    "scope": "user",
    "version": "${VERSION}",
    "installPath": "${DEST}",
    "lastUpdated": "${TIMESTAMP}",
    "gitCommitSha": "${GIT_SHA}"
  }
ENTRY
done

echo ']' >>"$INSTALLED_JSON"
