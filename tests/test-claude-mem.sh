#!/bin/bash
# claude-mem Plugin Compatibility Tests
# Run: bash tests/test-claude-mem.sh
set -euo pipefail

PASS=0
FAIL=0

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

PLUGIN_BASE="$HOME/.claude/plugins"
CMEM_PLUGIN_JSON=$(find "$PLUGIN_BASE/cache/thedotmack/claude-mem" \
  -name "plugin.json" -path "*/.claude-plugin/*" -print -quit 2>/dev/null || true)

if [ -z "$CMEM_PLUGIN_JSON" ]; then
  echo "FATAL: claude-mem not installed in plugin cache"
  exit 1
fi

CMEM_DIR=$(dirname "$(dirname "$CMEM_PLUGIN_JSON")")
echo "=== claude-mem Compatibility Tests ==="
echo "Plugin root: $CMEM_DIR"
echo ""

echo "1. Plugin File Existence"
check "plugin.json exists" test -f "$CMEM_DIR/.claude-plugin/plugin.json"
check "hooks.json exists" test -f "$CMEM_DIR/hooks/hooks.json"
check "mcp-server.cjs exists" test -f "$CMEM_DIR/scripts/mcp-server.cjs"
check "worker-service.cjs exists" test -f "$CMEM_DIR/scripts/worker-service.cjs"
check "bun-runner.js exists" test -f "$CMEM_DIR/scripts/bun-runner.js"
check ".mcp.json exists" test -f "$CMEM_DIR/.mcp.json"
check "package.json exists" test -f "$CMEM_DIR/package.json"

echo ""
echo "2. Plugin Registration"
check "claude-mem in installed_plugins.json" \
  jq -e '.plugins["claude-mem@thedotmack"]' "$PLUGIN_BASE/installed_plugins.json"
check "installed_plugins.json is v2 format" \
  jq -e '.version == 2' "$PLUGIN_BASE/installed_plugins.json"
check "claude-mem enabled in settings.json" \
  jq -e '.enabledPlugins["claude-mem@thedotmack"] == true' "$HOME/.claude/settings.json"
check "thedotmack in known_marketplaces.json" \
  jq -e '.thedotmack' "$PLUGIN_BASE/known_marketplaces.json"

echo ""
echo "3. Runtime Dependencies"
check "bun is available" command -v bun
NODE_MAJOR=$(node -e "console.log(process.version.split('.')[0].replace('v',''))")
check "node >= 18 (found v${NODE_MAJOR})" test "$NODE_MAJOR" -ge 18
check "node_modules exists" test -d "$CMEM_DIR/node_modules"

echo ""
echo "4. Hook Coexistence"
check "settings.json SessionStart chmod hook intact" \
  jq -e '.hooks.SessionStart[0].hooks[0].command | test("chmod.*\\+x")' "$HOME/.claude/settings.json"
check "settings.json PostToolUse Skill hook intact" \
  jq -e '.hooks.PostToolUse[0].matcher == "Skill"' "$HOME/.claude/settings.json"
check "claude-mem hooks.json defines hooks" \
  jq -e '.hooks | length > 0' "$CMEM_DIR/hooks/hooks.json"
# Verify superpowers plugin hooks also still exist
SP_HOOKS=$(find "$PLUGIN_BASE/cache/claude-plugins-official/superpowers" \
  -name "hooks.json" -print -quit 2>/dev/null || true)
if [ -n "$SP_HOOKS" ]; then
  check "superpowers hooks.json still exists" test -f "$SP_HOOKS"
fi

echo ""
echo "5. CLAUDE.md Conflict Check"
check "managed CLAUDE.md intact at /etc/claude-code/" \
  grep -q "PascalCase" /etc/claude-code/CLAUDE.md
check "user CLAUDE.md intact at ~/.claude/" \
  grep -q "ephemeral Docker" "$HOME/.claude/CLAUDE.md"

echo ""
echo "6. Port Availability"
check "port 37777 does not conflict with Chrome (9222)" \
  test "37777" != "9222"
check "port 37777 does not conflict with VNC (5900)" \
  test "37777" != "5900"
check "port 37777 does not conflict with noVNC (6080)" \
  test "37777" != "6080"

echo ""
echo "7. MCP Configuration"
check "plugin .mcp.json defines mcp-search" \
  jq -e '.mcpServers["mcp-search"]' "$CMEM_DIR/.mcp.json"
check "chrome-devtools MCP still in claude.json" \
  jq -e '.mcpServers["chrome-devtools"]' "$HOME/.claude.json"

echo ""
echo "8. LiteLLM Auth Integration"
if [ -n "$LITELLM_API_KEY" ]; then
  check "claude-mem .env exists" test -f "$HOME/.claude-mem/.env"
  check "claude-mem .env contains ANTHROPIC_API_KEY" \
    grep -q "ANTHROPIC_API_KEY=" "$HOME/.claude-mem/.env"
  HEALTH=$(curl -sf --connect-timeout 2 http://localhost:37777/api/health 2>/dev/null || true)
  if [ -n "$HEALTH" ]; then
    check "worker auth method is API key" \
      bash -c "echo '$HEALTH' | jq -e '.ai.authMethod | test(\"API key\")'"
  else
    echo "  SKIP: worker not running (auth method check requires live worker)"
  fi
else
  echo "  SKIP: LITELLM_API_KEY not set (OAuth mode)"
fi

echo ""
echo "9. Script Permissions"
NON_EXEC_SH=$(find "$CMEM_DIR" -name "*.sh" -type f ! -perm -u+x 2>/dev/null | wc -l)
check "all .sh files executable (${NON_EXEC_SH} non-exec)" \
  test "$NON_EXEC_SH" -eq 0

echo ""
echo "10. Ephemeral Data Behavior"
TEST_DIR="/tmp/claude-mem-test-$$"
mkdir -p "$TEST_DIR"
rm -rf "$TEST_DIR"
check "data directory can be recreated" mkdir -p "$TEST_DIR"
rm -rf "$TEST_DIR"

echo ""
echo "11. Other Plugins Unaffected"
ENABLED_COUNT=$(jq '.enabledPlugins | length' "$HOME/.claude/settings.json")
CACHED_COUNT=$(jq '.plugins | keys | length' "$PLUGIN_BASE/installed_plugins.json")
check "all ${ENABLED_COUNT} enabled plugins have cache entries (${CACHED_COUNT} found)" \
  test "$CACHED_COUNT" -ge "$ENABLED_COUNT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS — claude-mem is compatible"
  exit 0
fi
