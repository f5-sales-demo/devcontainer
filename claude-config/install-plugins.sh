#!/usr/bin/env bash
# Pre-install Claude Code plugins into the cache directory.
# Called from Dockerfile section 12l after marketplace clones.
# Supports multiple marketplaces — reads the @marketplace suffix
# from each enabledPlugins key in settings.json.
set -euo pipefail

PLUGIN_BASE="$1" # e.g. /home/vscode/.claude/plugins
SETTINGS="$2"    # e.g. /opt/claude-config/settings.json
INSTALLED_JSON="${PLUGIN_BASE}/installed_plugins.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Start building installed_plugins.json
echo '[' >"$INSTALLED_JSON"
FIRST=true

# Read enabled plugin keys from settings.json
# Format: "name@marketplace-name"
KEYS=$(jq -r '.enabledPlugins | keys[]' "$SETTINGS")

for KEY in $KEYS; do
  NAME=$(echo "$KEY" | cut -d@ -f1)
  MKT=$(echo "$KEY" | cut -d@ -f2)
  MKT_DIR="${PLUGIN_BASE}/marketplaces/${MKT}"
  CACHE_DIR="${PLUGIN_BASE}/cache/${MKT}"

  mkdir -p "$CACHE_DIR"

  # Get git SHA for this marketplace (if it exists)
  GIT_SHA=""
  if [ -d "$MKT_DIR/.git" ]; then
    GIT_SHA=$(cd "$MKT_DIR" && git rev-parse HEAD)
  fi

  # Determine source path in marketplace
  SRC=""
  if [ -d "${MKT_DIR}/plugins/${NAME}" ]; then
    SRC="${MKT_DIR}/plugins/${NAME}"
  elif [ -d "${MKT_DIR}/external_plugins/${NAME}" ]; then
    SRC="${MKT_DIR}/external_plugins/${NAME}"
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

  DEST="${CACHE_DIR}/${NAME}/${VERSION}"
  mkdir -p "$DEST"

  if [ -n "$SRC" ]; then
    # Local marketplace plugin -- copy
    cp -a "${SRC}/." "$DEST/"
  elif [ "$NAME" = "superpowers" ]; then
    # External URL plugin -- clone at build time
    git clone --depth=1 --single-branch --branch main \
      https://github.com/obra/superpowers.git "$DEST"
  else
    echo "WARNING: no source found for plugin '${NAME}' in marketplace '${MKT}', skipping"
    rm -rf "$DEST"
    continue
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
    "marketplace": "${MKT}",
    "scope": "user",
    "version": "${VERSION}",
    "installPath": "${DEST}",
    "lastUpdated": "${TIMESTAMP}",
    "gitCommitSha": "${GIT_SHA}"
  }
ENTRY
done

echo ']' >>"$INSTALLED_JSON"
