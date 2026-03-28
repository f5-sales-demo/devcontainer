#!/bin/bash
# Plugin hook neutralization and marketplace directory repair.
# Called from settings.json SessionStart and PostToolUse hooks.
#
# Three responsibilities:
#   1. Ensure marketplace directories exist for all enabled cached plugins
#   2. Fix .sh execute permissions across all plugin directories
#   3. Neutralize hooks.json for non-enabled marketplace plugins
#
# CRITICAL: This script MUST always exit 0. Claude Code interprets non-zero
# exit from hook commands as "hook error" and displays it to the user.
# The background daemon in entrypoint.sh provides backup coverage, so a
# silent partial failure here is strictly better than a noisy error.

SETTINGS="${HOME}/.claude/settings.json"
PLUGIN_BASE="${HOME}/.claude/plugins"

# ── 1. Ensure marketplace directories for enabled cached plugins ─────────
# Claude Code resolves plugin paths from marketplaces/<mkt>/plugins/<name>/
# Plugins from external sources (GitHub) only exist in cache — symlink them.
if [ -f "$SETTINGS" ]; then
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    name="${key%%@*}"
    mkt="${key#*@}"
    mkt_dir="${PLUGIN_BASE}/marketplaces/${mkt}/plugins/${name}"

    [ -d "$mkt_dir" ] && continue

    cache_entry=$(find "${PLUGIN_BASE}/cache/${mkt}/${name}" \
      -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
    [ -n "$cache_entry" ] || continue

    mkdir -p "$(dirname "$mkt_dir")" 2>/dev/null || true
    ln -sf "$cache_entry" "$mkt_dir" 2>/dev/null || true
  done < <(jq -r '.enabledPlugins | keys[]' "$SETTINGS" 2>/dev/null)
fi

# ── 2. Fix .sh execute permissions ───────────────────────────────────────
find "$PLUGIN_BASE" -name '*.sh' -type f \
  ! -perm -u+x -exec chmod +x {} + 2>/dev/null || true

# ── 3. Neutralize non-enabled marketplace plugin hooks ───────────────────
for hf in "$PLUGIN_BASE"/marketplaces/*/plugins/*/hooks/hooks.json; do
  [ -f "$hf" ] || continue
  hd=$(dirname "$hf")
  p=$(basename "$(dirname "$(dirname "$hf")")")
  m=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$hf")")")")")

  if jq -e --arg k "${p}@${m}" '.enabledPlugins[$k]' "$SETTINGS" >/dev/null 2>&1; then
    # Enabled plugin: restore normal permissions (handles disable->enable)
    chmod 755 "$hd" 2>/dev/null || true
    chmod 644 "$hf" 2>/dev/null || true
    continue
  fi

  # Skip if already neutralized (idempotent)
  current=$(cat "$hf" 2>/dev/null || true)
  if [ "$current" = "{}" ]; then
    chmod 444 "$hf" 2>/dev/null || true
    chmod 555 "$hd" 2>/dev/null || true
    continue
  fi

  # Neutralize and lock
  chmod 755 "$hd" 2>/dev/null || true
  chmod 644 "$hf" 2>/dev/null || true
  echo '{}' >"$hf" 2>/dev/null || true
  chmod 444 "$hf" 2>/dev/null || true
  chmod 555 "$hd" 2>/dev/null || true
done

# ALWAYS exit 0 — never cause "hook error" display
exit 0
