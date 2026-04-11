#!/usr/bin/env bash
# Pre-install Claude Code plugins into the cache directory.
# Called from Dockerfile section 12l after marketplace clones.
# Supports multiple marketplaces — reads the @marketplace suffix
# from each enabledPlugins key in settings.json.
#
# Generates installed_plugins.json in v2 format:
#   {"version":2,"plugins":{"name@mkt":[{scope,installPath,...}],...}}
set -euo pipefail

PLUGIN_BASE="$1" # e.g. /home/vscode/.claude/plugins
SETTINGS="$2"    # e.g. /opt/claude-config/settings.json
INSTALLED_JSON="${PLUGIN_BASE}/installed_plugins.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Build installed_plugins.json using jq for correct JSON
# Collect entries as a JSON array, then reshape to v2 format
ENTRIES="[]"

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

  # Read version from plugin.json (default to git SHA or 0.0.0)
  VERSION="${GIT_SHA:-0.0.0}"
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
    # External URL plugin — use existing cache or clone fresh
    EXISTING=$(find "${CACHE_DIR}/${NAME}" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | head -1)
    if [ -n "$EXISTING" ]; then
      DEST=$(dirname "$(dirname "$EXISTING")")
      VERSION=$(basename "$DEST")
    else
      git clone --depth=1 --single-branch --branch main \
        https://github.com/obra/superpowers.git "$DEST"
      if [ -f "${DEST}/.claude-plugin/plugin.json" ]; then
        V=$(jq -r '.version // empty' "${DEST}/.claude-plugin/plugin.json")
        if [ -n "$V" ] && [ "$V" != "$VERSION" ]; then
          VERSION="$V"
          NEW_DEST="${CACHE_DIR}/${NAME}/${VERSION}"
          if [ "$DEST" != "$NEW_DEST" ]; then
            mkdir -p "$NEW_DEST"
            cp -a "${DEST}/." "$NEW_DEST/"
            rm -rf "$DEST"
            DEST="$NEW_DEST"
          fi
        fi
      fi
    fi
  elif [ "$NAME" = "claude-mem" ]; then
    # External plugin — clone repo, copy only the plugin/ subdirectory
    EXISTING=$(find "${CACHE_DIR}/${NAME}" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | head -1)
    if [ -n "$EXISTING" ]; then
      DEST=$(dirname "$(dirname "$EXISTING")")
      VERSION=$(basename "$DEST")
    else
      git clone --depth=1 --single-branch --branch main \
        https://github.com/thedotmack/claude-mem.git /tmp/claude-mem-clone
      cp -a /tmp/claude-mem-clone/plugin/. "$DEST/"
      rm -rf /tmp/claude-mem-clone
      if [ -f "${DEST}/.claude-plugin/plugin.json" ]; then
        V=$(jq -r '.version // empty' "${DEST}/.claude-plugin/plugin.json")
        if [ -n "$V" ] && [ "$V" != "$VERSION" ]; then
          VERSION="$V"
          NEW_DEST="${CACHE_DIR}/${NAME}/${VERSION}"
          if [ "$DEST" != "$NEW_DEST" ]; then
            mkdir -p "$NEW_DEST"
            cp -a "${DEST}/." "$NEW_DEST/"
            rm -rf "$DEST"
            DEST="$NEW_DEST"
          fi
        fi
      fi
    fi
  else
    echo "WARNING: no source found for plugin '${NAME}' in marketplace '${MKT}', skipping"
    rm -rf "$DEST"
    continue
  fi

  # Fix script permissions — cp -a preserves source perms which
  # may lack execute bits on .sh files from marketplace repos
  find "$DEST" -name "*.sh" -type f -exec chmod +x {} +

  # Add entry to collection
  ENTRIES=$(echo "$ENTRIES" | jq \
    --arg key "$KEY" \
    --arg scope "user" \
    --arg path "$DEST" \
    --arg ver "$VERSION" \
    --arg ts "$TIMESTAMP" \
    --arg sha "$GIT_SHA" \
    '. + [{"key": $key, "scope": $scope, "installPath": $path, "version": $ver, "installedAt": $ts, "lastUpdated": $ts, "gitCommitSha": $sha}]')
done

# Write v2 format: {"version":2,"plugins":{"key":[{entry}],...}}
echo "$ENTRIES" | jq '{
  version: 2,
  plugins: (reduce .[] as $e ({}; .[$e.key] = [($e | del(.key))]))
}' >"$INSTALLED_JSON"

# Final sweep: ensure all .sh files across marketplaces and cache
# are executable — catches any scripts missed by per-plugin fixups
find "${PLUGIN_BASE}/marketplaces" "${PLUGIN_BASE}/cache" \
  -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null || true

# Ensure every enabled cached plugin has a marketplace directory entry.
# Claude Code resolves plugin paths from marketplaces/<mkt>/plugins/<name>/
# Plugins installed from external sources (GitHub clones like superpowers,
# claude-mem) only exist in cache — create marketplace symlinks so Claude
# Code can find them and run their hooks without "Plugin directory does not
# exist" errors.
for KEY in $KEYS; do
  NAME=$(echo "$KEY" | cut -d@ -f1)
  MKT=$(echo "$KEY" | cut -d@ -f2)
  MKT_PLUGIN_DIR="${PLUGIN_BASE}/marketplaces/${MKT}/plugins/${NAME}"

  # Skip if marketplace dir already exists
  [ -d "$MKT_PLUGIN_DIR" ] && continue

  # Find the cache entry for this plugin (use first version found)
  CACHE_ENTRY=$(find "${PLUGIN_BASE}/cache/${MKT}/${NAME}" \
    -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
  [ -n "$CACHE_ENTRY" ] || continue

  # Create parent dir and symlink
  mkdir -p "$(dirname "$MKT_PLUGIN_DIR")"
  ln -sf "$CACHE_ENTRY" "$MKT_PLUGIN_DIR"
done

# Neutralize hooks from non-enabled marketplace plugins (cc#40013)
# Claude Code fires hooks from ALL installed plugins, not just enabled ones.
# Replace hooks.json with {} for plugins not in enabledPlugins.
for MKT_DIR in "${PLUGIN_BASE}/marketplaces"/*/; do
  [ -d "$MKT_DIR" ] || continue
  MKT_NAME=$(basename "$MKT_DIR")
  for PLUGIN in "${MKT_DIR}plugins"/*/; do
    [ -d "$PLUGIN" ] || continue
    PLUGIN_NAME=$(basename "$PLUGIN")
    KEY="${PLUGIN_NAME}@${MKT_NAME}"
    HOOKS_FILE="${PLUGIN}hooks/hooks.json"
    [ -f "$HOOKS_FILE" ] || continue
    if jq -e --arg k "$KEY" '.enabledPlugins[$k]' "$SETTINGS" >/dev/null 2>&1; then
      continue
    fi
    # Skip if already neutralized (idempotent)
    CURRENT=$(cat "$HOOKS_FILE" 2>/dev/null || true)
    if [ "$CURRENT" = "{}" ]; then
      chmod 755 "$(dirname "$HOOKS_FILE")" 2>/dev/null || true
      chmod 444 "$HOOKS_FILE" 2>/dev/null || true
      continue
    fi
    chmod 755 "$(dirname "$HOOKS_FILE")" 2>/dev/null || true
    chmod 644 "$HOOKS_FILE" 2>/dev/null || true
    echo '{}' >"$HOOKS_FILE"
    chmod 444 "$HOOKS_FILE"
  done
done

# Second pass: neutralize hooks.json at non-standard paths (monorepo marketplaces)
# e.g. thedotmack/cursor-hooks/hooks.json (not under plugins/)
while IFS= read -r HF; do
  [ -f "$HF" ] || continue
  # Skip files already handled by the standard loop above
  echo "$HF" | grep -q '/marketplaces/[^/]*/plugins/[^/]*/hooks/hooks.json$' && continue
  HD=$(dirname "$HF")
  HF_PARENT=$(dirname "$HD")
  HF_PARENT_REAL=$(readlink -f "$HF_PARENT" 2>/dev/null || echo "$HF_PARENT")
  SKIP=false
  for LINK in "${PLUGIN_BASE}/marketplaces"/*/plugins/*/; do
    [ -L "${LINK%/}" ] || continue
    LINK_TARGET=$(readlink -f "${LINK%/}" 2>/dev/null || true)
    [ -n "$LINK_TARGET" ] || continue
    if [ "$HF_PARENT_REAL" = "$LINK_TARGET" ]; then
      LINK_NAME=$(basename "${LINK%/}")
      LINK_MKT=$(basename "$(dirname "$(dirname "${LINK%/}")")")
      if jq -e --arg k "${LINK_NAME}@${LINK_MKT}" '.enabledPlugins[$k]' "$SETTINGS" >/dev/null 2>&1; then
        SKIP=true
        break
      fi
    fi
  done
  if [ "$SKIP" = true ]; then
    continue
  fi
  CURRENT=$(cat "$HF" 2>/dev/null || true)
  if [ "$CURRENT" = "{}" ]; then
    chmod 755 "$HD" 2>/dev/null || true
    chmod 444 "$HF" 2>/dev/null || true
    continue
  fi
  chmod 755 "$HD" 2>/dev/null || true
  chmod 644 "$HF" 2>/dev/null || true
  echo '{}' >"$HF" 2>/dev/null || true
  chmod 444 "$HF" 2>/dev/null || true
done < <(find "${PLUGIN_BASE}/marketplaces" -name "hooks.json" 2>/dev/null)

# Third pass: neutralize cache-level hooks.json for non-enabled plugins.
# Claude Code reads hooks from installed_plugins.json -> installPath which
# always points to cache/<mkt>/<name>/<version>/hooks/hooks.json.
for CHF in "${PLUGIN_BASE}/cache"/*/*/*/hooks/hooks.json; do
  [ -f "$CHF" ] || continue
  RELATIVE="${CHF#"${PLUGIN_BASE}"/cache/}"
  C_MKT="${RELATIVE%%/*}"
  C_NAME="${RELATIVE#*/}"
  C_NAME="${C_NAME%%/*}"
  C_KEY="${C_NAME}@${C_MKT}"
  CHD=$(dirname "$CHF")

  if jq -e --arg k "$C_KEY" '.enabledPlugins[$k]' "$SETTINGS" >/dev/null 2>&1; then
    continue
  fi

  C_CURRENT=$(cat "$CHF" 2>/dev/null || true)
  if [ "$C_CURRENT" = "{}" ]; then
    chmod 755 "$CHD" 2>/dev/null || true
    chmod 444 "$CHF" 2>/dev/null || true
    continue
  fi

  chmod 755 "$CHD" 2>/dev/null || true
  chmod 644 "$CHF" 2>/dev/null || true
  echo '{}' >"$CHF" 2>/dev/null || true
  chmod 444 "$CHF" 2>/dev/null || true
done
