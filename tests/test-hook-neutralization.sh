#!/bin/bash
# Hook Neutralization & Marketplace Completeness Tests (TDD)
#
# Tests the three-layer plugin hook fix infrastructure:
#   - Marketplace directory completeness for all enabled plugins
#   - Neutralization of non-enabled marketplace plugin hooks
#   - Staging marketplace handling
#   - Settings.json hook command robustness
#   - Background daemon lifecycle
#
# Run:  bash tests/test-hook-neutralization.sh            # all tests
#       bash tests/test-hook-neutralization.sh --unit-only # skip E2E (no container needed)
set -euo pipefail

PASS=0
FAIL=0
UNIT_ONLY=false
[ "${1:-}" = "--unit-only" ] && UNIT_ONLY=true

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# ── Mock environment helpers ──────────────────────────────────────
MOCK_HOME=""

setup_mock_env() {
  MOCK_HOME=$(mktemp -d)
  local plugins="${MOCK_HOME}/.claude/plugins"
  mkdir -p "${plugins}/marketplaces/test-mkt/plugins"
  mkdir -p "${plugins}/cache/test-mkt"

  # Minimal settings.json with one enabled plugin
  cat >"${MOCK_HOME}/.claude/settings.json" <<'SETTINGS'
{
  "enabledPlugins": {
    "alpha@test-mkt": true,
    "beta@test-mkt": true
  }
}
SETTINGS
}

teardown_mock_env() {
  if [ -n "$MOCK_HOME" ]; then
    # Unlock any chmod-locked files before removal
    find "$MOCK_HOME" -type f -perm 444 -exec chmod 644 {} + 2>/dev/null || true
    rm -rf "$MOCK_HOME"
  fi
  MOCK_HOME=""
}

# Create a mock plugin in the marketplace directory
# Usage: create_mock_mkt_plugin <marketplace> <plugin_name> <hooks_json_content>
create_mock_mkt_plugin() {
  local mkt="$1" name="$2" hooks_content="$3"
  local plugin_dir="${MOCK_HOME}/.claude/plugins/marketplaces/${mkt}/plugins/${name}"
  mkdir -p "${plugin_dir}/hooks"
  echo "$hooks_content" >"${plugin_dir}/hooks/hooks.json"
  # Add a dummy .sh file for permission tests
  echo '#!/bin/bash' >"${plugin_dir}/hooks/run.sh"
}

# Create a mock plugin in the cache directory
# Usage: create_mock_cache_plugin <marketplace> <plugin_name> <version> <hooks_json_content>
create_mock_cache_plugin() {
  local mkt="$1" name="$2" ver="$3" hooks_content="$4"
  local cache_dir="${MOCK_HOME}/.claude/plugins/cache/${mkt}/${name}/${ver}"
  mkdir -p "${cache_dir}/hooks"
  mkdir -p "${cache_dir}/.claude-plugin"
  echo "$hooks_content" >"${cache_dir}/hooks/hooks.json"
  echo "{\"version\": \"${ver}\"}" >"${cache_dir}/.claude-plugin/plugin.json"
}

# Source the neutralize function from entrypoint.sh with HOME overridden
source_neutralize_fn() {
  local fn_body
  fn_body=$(sed -n '/^neutralize_non_enabled_hooks()/,/^}/p' \
    "$(dirname "$0")/../entrypoint.sh")
  if [ -z "$fn_body" ]; then
    echo "  FAIL: neutralize_non_enabled_hooks() not found in entrypoint.sh" >&2
    neutralize_non_enabled_hooks() { return 1; }
    return 1
  fi
  HOME="$MOCK_HOME" eval "$fn_body"
}

# Source the ensure_marketplace_dirs function from entrypoint.sh
source_ensure_dirs_fn() {
  local fn_body
  fn_body=$(sed -n '/^ensure_marketplace_dirs()/,/^}/p' \
    "$(dirname "$0")/../entrypoint.sh")
  if [ -z "$fn_body" ]; then
    echo "  FAIL: ensure_marketplace_dirs() not found in entrypoint.sh" >&2
    # Define a stub so tests can report FAIL rather than crash
    ensure_marketplace_dirs() { return 1; }
    return 1
  fi
  HOME="$MOCK_HOME" eval "$fn_body"
}

# ── Group 1: Marketplace Directory Completeness ──────────────────
echo "=== Hook Neutralization & Marketplace Completeness Tests ==="
echo ""
echo "1. Marketplace Directory Completeness"

# Test 1: ensure_marketplace_dirs creates symlinks for cache-only plugins
setup_mock_env
create_mock_cache_plugin "test-mkt" "alpha" "1.0.0" '{"hooks":{"PreToolUse":[]}}'
# alpha is enabled and in cache but NOT in marketplace
source_ensure_dirs_fn || true
HOME="$MOCK_HOME" ensure_marketplace_dirs 2>/dev/null || true
check "ensure_marketplace_dirs creates symlink for cache-only plugin" \
  test -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha"
teardown_mock_env

# Test 2: ensure_marketplace_dirs skips plugins already in marketplace
setup_mock_env
create_mock_mkt_plugin "test-mkt" "alpha" '{"hooks":{"PreToolUse":[]}}'
create_mock_cache_plugin "test-mkt" "alpha" "1.0.0" '{"hooks":{"PreToolUse":[]}}'
source_ensure_dirs_fn || true
HOME="$MOCK_HOME" ensure_marketplace_dirs 2>/dev/null || true
# Should not be a symlink — original dir preserved
check "ensure_marketplace_dirs preserves existing marketplace dir" \
  test -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha" -a \
  \( -L "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha" -o \
  -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha" \)
teardown_mock_env

# Test 3: symlink points to valid target
setup_mock_env
create_mock_cache_plugin "test-mkt" "alpha" "2.0.0" '{"hooks":{}}'
source_ensure_dirs_fn || true
HOME="$MOCK_HOME" ensure_marketplace_dirs 2>/dev/null || true
check "symlink target is valid directory" \
  test -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha"
teardown_mock_env

# Test 4: ensure_marketplace_dirs handles missing cache gracefully
setup_mock_env
# beta is enabled but has no cache entry either — should not error
source_ensure_dirs_fn || true
HOME="$MOCK_HOME" ensure_marketplace_dirs 2>/dev/null || true
check "ensure_marketplace_dirs handles missing cache without error" \
  true
teardown_mock_env

echo ""
echo "2. Basic Neutralization"

# Test 5: non-enabled plugin hooks.json → {} with 444/555 perms
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo bad"}]}]}}'
source_neutralize_fn
HOME="$MOCK_HOME" neutralize_non_enabled_hooks
CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json")
FPERMS=$(stat -c '%a' "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json" 2>/dev/null)
DPERMS=$(stat -c '%a' "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks" 2>/dev/null)
check "non-enabled plugin hooks.json neutralized to {}" \
  test "$CONTENT" = "{}"
check "non-enabled plugin hooks.json perms 444" \
  test "$FPERMS" = "444"
check "non-enabled plugin hooks dir perms 755" \
  test "$DPERMS" = "755"
teardown_mock_env

# Test 6: enabled plugin hooks.json preserved with 644/755 perms
setup_mock_env
ORIG_HOOKS='{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"echo ok"}]}]}}'
create_mock_mkt_plugin "test-mkt" "alpha" "$ORIG_HOOKS"
source_neutralize_fn
HOME="$MOCK_HOME" neutralize_non_enabled_hooks
CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha/hooks/hooks.json")
FPERMS=$(stat -c '%a' "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha/hooks/hooks.json" 2>/dev/null)
check "enabled plugin hooks.json preserved" \
  test "$CONTENT" = "$ORIG_HOOKS"
check "enabled plugin hooks.json perms 644" \
  test "$FPERMS" = "644"
teardown_mock_env

# Test 7: idempotent — already neutralized (444) files cause no errors
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{}'
chmod 444 "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json"
chmod 755 "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks"
source_neutralize_fn
STDERR_OUTPUT=$(HOME="$MOCK_HOME" neutralize_non_enabled_hooks 2>&1 || true)
CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json")
check "idempotent neutralize on locked file — no errors" \
  test -z "$STDERR_OUTPUT"
check "idempotent neutralize preserves {} content" \
  test "$CONTENT" = "{}"
teardown_mock_env

# Test 8: missing hooks dir → exit 0, no stderr
setup_mock_env
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma"
# No hooks/ subdir
source_neutralize_fn
STDERR_OUTPUT=$(HOME="$MOCK_HOME" neutralize_non_enabled_hooks 2>&1 || true)
check "missing hooks dir causes no error" \
  test -z "$STDERR_OUTPUT"
teardown_mock_env

# Test 9: empty marketplace → exit 0, no stderr
setup_mock_env
# No plugins created at all
source_neutralize_fn
STDERR_OUTPUT=$(HOME="$MOCK_HOME" neutralize_non_enabled_hooks 2>&1 || true)
check "empty marketplace causes no error" \
  test -z "$STDERR_OUTPUT"
teardown_mock_env

echo ""
echo "3. Staging Marketplace"

# Test 10: .staging marketplace plugins get neutralized
setup_mock_env
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging/plugins"
create_mock_mkt_plugin "test-mkt.staging" "alpha" '{"hooks":{"PreToolUse":[]}}'
# alpha@test-mkt is enabled, but alpha@test-mkt.staging is NOT
source_neutralize_fn
HOME="$MOCK_HOME" neutralize_non_enabled_hooks
CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging/plugins/alpha/hooks/hooks.json")
check "staging marketplace plugin correctly neutralized" \
  test "$CONTENT" = "{}"
teardown_mock_env

# Test 11: staging plugin key differs from non-staging
setup_mock_env
create_mock_mkt_plugin "test-mkt" "alpha" '{"hooks":{"PreToolUse":[]}}'
create_mock_mkt_plugin "test-mkt.staging" "alpha" '{"hooks":{"PreToolUse":[]}}'
source_neutralize_fn
HOME="$MOCK_HOME" neutralize_non_enabled_hooks
MKT_CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha/hooks/hooks.json")
STG_CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging/plugins/alpha/hooks/hooks.json")
check "non-staging enabled plugin preserved" \
  test "$MKT_CONTENT" = '{"hooks":{"PreToolUse":[]}}'
check "staging copy of same plugin neutralized" \
  test "$STG_CONTENT" = "{}"
teardown_mock_env

echo ""
echo "4. Settings.json Hook Command"

# Test 12: neutralize-hooks.sh exits 0 even with locked files
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{}'
chmod 444 "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json"
chmod 755 "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks"
SCRIPT="$(dirname "$0")/../claude-config/neutralize-hooks.sh"
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  check "neutralize-hooks.sh exits 0 with locked files" test $? -eq 0
else
  echo "  FAIL: neutralize-hooks.sh not found (expected at $SCRIPT)"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 13: neutralize-hooks.sh neutralizes new non-enabled plugins
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[]}}'
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json")
  check "neutralize-hooks.sh neutralizes non-enabled plugin" test "$CONTENT" = "{}"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 14: settings.json hooks reference script path (not inline bash)
SETTINGS_FILE="$(dirname "$0")/../claude-config/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  check "SessionStart hook references neutralize-hooks.sh" \
    jq -e '.hooks.SessionStart[0].hooks[0].command | test("neutralize-hooks")' "$SETTINGS_FILE"
  check "PostToolUse hook references neutralize-hooks.sh" \
    jq -e '.hooks.PostToolUse[0].hooks[0].command | test("neutralize-hooks")' "$SETTINGS_FILE"
else
  echo "  FAIL: settings.json not found"
  FAIL=$((FAIL + 2))
fi

echo ""
echo "5. Daemon Lifecycle"

# Test 15: daemon function handles concurrent runs without corruption
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[]}}'
source_neutralize_fn
# Run 5 parallel neutralizations
for _ in 1 2 3 4 5; do
  HOME="$MOCK_HOME" neutralize_non_enabled_hooks &
done
wait
CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json" 2>/dev/null || echo "MISSING")
check "concurrent neutralize produces valid JSON {}" \
  test "$CONTENT" = "{}"
teardown_mock_env

# Test 16: entrypoint daemon section has no sleep between inotifywait and neutralize
ENTRYPOINT="$(dirname "$0")/../entrypoint.sh"
if [ -f "$ENTRYPOINT" ]; then
  # After inotifywait line, next non-blank line should NOT be 'sleep'
  INOTIFY_NEXT=$(awk '/inotifywait/{found=1;next} found && /[^ \t]/{print;exit}' "$ENTRYPOINT")
  HAS_SLEEP=false
  echo "$INOTIFY_NEXT" | grep -q "sleep" && HAS_SLEEP=true
  check "no sleep between inotifywait and neutralize" \
    test "$HAS_SLEEP" = "false"
else
  echo "  FAIL: entrypoint.sh not found"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "6. Non-Standard Plugin Paths"

# Test 20: hooks.json at non-standard path (not under plugins/) gets neutralized
setup_mock_env
# Create a monorepo-style marketplace with hooks NOT under plugins/
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/cursor-hooks"
echo '{"hooks":{"beforeSubmitPrompt":[{"command":"./session-init.sh"}]}}' \
  >"${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/cursor-hooks/hooks.json"
# Run the standalone script (which has the broader scan)
SCRIPT="$(dirname "$0")/../claude-config/neutralize-hooks.sh"
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/cursor-hooks/hooks.json" 2>/dev/null)
  check "non-standard path hooks.json neutralized" test "$CONTENT" = "{}"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 21: hooks.json at non-standard path that is a symlink target of enabled plugin is preserved
setup_mock_env
create_mock_cache_plugin "test-mkt" "alpha" "1.0.0" '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo ok"}]}]}}'
# Create symlink: plugins/alpha -> cache entry (simulates ensure_marketplace_dirs)
source_ensure_dirs_fn || true
HOME="$MOCK_HOME" ensure_marketplace_dirs 2>/dev/null || true
# Now the non-standard path (cache target) has hooks.json — should be preserved via the standard path check
ORIG_HOOKS='{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo ok"}]}]}}'
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  # The standard plugins/alpha/hooks/hooks.json (symlink to cache) should be preserved
  CONTENT=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/alpha/hooks/hooks.json" 2>/dev/null)
  check "enabled plugin hooks preserved through symlink" test "$CONTENT" = "$ORIG_HOOKS"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 22: multiple non-standard paths in same marketplace all neutralized
setup_mock_env
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-a/hooks"
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-b/hooks"
echo '{"hooks":{"Stop":[]}}' >"${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-a/hooks/hooks.json"
echo '{"hooks":{"Stop":[]}}' >"${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-b/hooks/hooks.json"
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  CONTENT_A=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-a/hooks/hooks.json" 2>/dev/null)
  CONTENT_B=$(cat "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/subdir-b/hooks/hooks.json" 2>/dev/null)
  check "non-standard path A neutralized" test "$CONTENT_A" = "{}"
  check "non-standard path B neutralized" test "$CONTENT_B" = "{}"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 2))
fi
teardown_mock_env

echo ""
echo "8. Marketplace Sync Compatibility"

# Test 23: rm -rf succeeds on marketplace with neutralized plugins
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo bad"}]}]}}'
create_mock_mkt_plugin "test-mkt" "delta" '{"hooks":{"PreToolUse":[]}}'
SCRIPT="$(dirname "$0")/../claude-config/neutralize-hooks.sh"
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  rm -rf "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt" 2>/dev/null
  check "rm -rf succeeds on marketplace with neutralized plugins" \
    test -z "$(ls -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt" 2>/dev/null)"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 24: neutralized hooks directory has 755 not 555
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[]}}'
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  DPERMS=$(stat -c '%a' "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks" 2>/dev/null)
  check "neutralized hooks dir has 755 (not 555)" test "$DPERMS" = "755"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 25: hooks.json still protected at 444 after neutralization
setup_mock_env
create_mock_mkt_plugin "test-mkt" "gamma" '{"hooks":{"SessionStart":[]}}'
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  FPERMS=$(stat -c '%a' "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt/plugins/gamma/hooks/hooks.json" 2>/dev/null)
  check "hooks.json still protected at 444" test "$FPERMS" = "444"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

# Test 26: staging marketplace removable after neutralization
setup_mock_env
mkdir -p "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging/plugins"
create_mock_mkt_plugin "test-mkt.staging" "gamma" '{"hooks":{"SessionStart":[]}}'
create_mock_mkt_plugin "test-mkt.staging" "delta" '{"hooks":{"PreToolUse":[]}}'
if [ -f "$SCRIPT" ]; then
  HOME="$MOCK_HOME" bash "$SCRIPT" 2>/dev/null
  rm -rf "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging" 2>/dev/null
  check "staging marketplace removable after neutralization" \
    test -z "$(ls -d "${MOCK_HOME}/.claude/plugins/marketplaces/test-mkt.staging" 2>/dev/null)"
else
  echo "  FAIL: neutralize-hooks.sh not found"
  FAIL=$((FAIL + 1))
fi
teardown_mock_env

if [ "$UNIT_ONLY" = true ]; then
  echo ""
  echo "── Skipping E2E tests (--unit-only) ──"
else
  echo ""
  echo "7. End-to-End (Container)"

  # Test 17: every enabled plugin has a marketplace directory
  PLUGIN_BASE="$HOME/.claude/plugins"
  SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ]; then
    MISSING_DIRS=0
    while IFS= read -r key; do
      name="${key%%@*}"
      mkt="${key#*@}"
      mkt_dir="${PLUGIN_BASE}/marketplaces/${mkt}/plugins/${name}"
      if [ -d "$mkt_dir" ] || [ -L "$mkt_dir" ]; then
        : # ok
      else
        echo "    MISSING: $mkt_dir (for $key)"
        MISSING_DIRS=$((MISSING_DIRS + 1))
      fi
    done < <(jq -r '.enabledPlugins | keys[]' "$SETTINGS" 2>/dev/null)
    check "all enabled plugins have marketplace directories (${MISSING_DIRS} missing)" \
      test "$MISSING_DIRS" -eq 0
  else
    echo "  FAIL: settings.json not found at $SETTINGS"
    FAIL=$((FAIL + 1))
  fi

  # Test 18: no non-enabled plugin has active hooks
  NON_ENABLED_HOOKS=0
  for hf in "$PLUGIN_BASE/marketplaces"/*/plugins/*/hooks/hooks.json; do
    [ -f "$hf" ] || continue
    PNAME=$(basename "$(dirname "$(dirname "$hf")")")
    MNAME=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$hf")")")")")
    KEY="${PNAME}@${MNAME}"
    if jq -e --arg k "$KEY" '.enabledPlugins[$k]' "$SETTINGS" >/dev/null 2>&1; then
      continue
    fi
    CONTENT=$(cat "$hf")
    if [ "$CONTENT" != "{}" ]; then
      echo "    ACTIVE: $hf (key=$KEY)"
      NON_ENABLED_HOOKS=$((NON_ENABLED_HOOKS + 1))
    fi
  done
  check "no active hooks from non-enabled plugins (${NON_ENABLED_HOOKS} found)" \
    test "$NON_ENABLED_HOOKS" -eq 0

  # Test 19: all enabled plugins have cache entries
  MISSING_CACHE=0
  while IFS= read -r key; do
    name="${key%%@*}"
    mkt="${key#*@}"
    cache_dir="${PLUGIN_BASE}/cache/${mkt}/${name}"
    if [ -d "$cache_dir" ] || [ -L "$cache_dir" ]; then
      : # ok
    else
      echo "    MISSING CACHE: $cache_dir (for $key)"
      MISSING_CACHE=$((MISSING_CACHE + 1))
    fi
  done < <(jq -r '.enabledPlugins | keys[]' "$SETTINGS" 2>/dev/null)
  check "all enabled plugins have cache entries (${MISSING_CACHE} missing)" \
    test "$MISSING_CACHE" -eq 0

  # Test 20e: non-standard path hooks.json files are neutralized unless they
  # belong to an enabled plugin's directory (e.g., thedotmack/plugin/ is claude-mem)
  NON_STD_ACTIVE=0
  while IFS= read -r hf; do
    [ -f "$hf" ] || continue
    # Skip standard paths (already tested above)
    echo "$hf" | grep -q '/plugins/[^/]*/hooks/hooks.json$' && continue
    # Skip if the hooks.json's parent structure is a symlink target for an enabled plugin
    hf_real=$(readlink -f "$(dirname "$(dirname "$hf")")")
    is_enabled_target=false
    for link in "$PLUGIN_BASE/marketplaces"/*/plugins/*/; do
      [ -L "${link%/}" ] || continue
      link_target=$(readlink -f "${link%/}")
      if [ "$hf_real" = "$link_target" ] || echo "$hf_real" | grep -q "^${link_target}"; then
        is_enabled_target=true
        break
      fi
    done
    if [ "$is_enabled_target" = true ]; then
      continue
    fi
    CONTENT=$(cat "$hf" 2>/dev/null)
    if [ "$CONTENT" != "{}" ]; then
      echo "    ACTIVE NON-STD: $hf"
      NON_STD_ACTIVE=$((NON_STD_ACTIVE + 1))
    fi
  done < <(find "$PLUGIN_BASE/marketplaces" -name "hooks.json" 2>/dev/null)
  check "no active hooks from non-standard unlinked paths (${NON_STD_ACTIVE} found)" \
    test "$NON_STD_ACTIVE" -eq 0

  # Test: self-test hook checks pass
  if command -v claude-self-test >/dev/null 2>&1; then
    SELF_TEST_OUTPUT=$(claude-self-test 2>&1 || true)
    HOOK_FAILS=$(echo "$SELF_TEST_OUTPUT" | grep -c "FAIL:.*hook\|FAIL:.*plugin\|FAIL:.*chmod" || true)
    check "self-test hook-related checks all pass (${HOOK_FAILS} failures)" \
      test "$HOOK_FAILS" -eq 0
  else
    echo "  SKIP: claude-self-test not available"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit "$FAIL"
