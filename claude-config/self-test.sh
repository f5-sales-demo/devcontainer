#!/bin/bash
# Claude Code Container Self-Test
set -euo pipefail

PASS=0
FAIL=0
WARN=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    ((FAIL++))
  fi
}

echo "=== Claude Code Container Self-Test ==="
echo ""

echo "1. Core Tools"
check "claude CLI installed" command -v claude
check "node installed" command -v node
check "python installed" command -v python3
check "git installed" command -v git
check "gh CLI installed" command -v gh

echo ""
echo "2. Claude Code Configuration"
check ".claude.json exists" test -f "$HOME/.claude.json"
check ".claude directory exists" test -d "$HOME/.claude"
check "settings.json exists" test -f "$HOME/.claude/settings.json"

echo ""
echo "3. Tool Awareness (Managed policy)"
MANAGED_CLAUDE="/etc/claude-code/CLAUDE.md"
check "$MANAGED_CLAUDE exists" test -f "$MANAGED_CLAUDE"
check "Managed policy contains PascalCase reference" grep -q "PascalCase" "$MANAGED_CLAUDE"
check "Managed policy contains tool table" grep -q "Read file contents" "$MANAGED_CLAUDE"
check "Managed policy contains subagent docs" grep -q "Subagent" "$MANAGED_CLAUDE"

echo ""
echo "4. Container Environment"
check "workspace directory exists" test -d /workspace
check "home directory writable" test -w "$HOME"
check "TERM is set" test -n "${TERM:-}"

echo ""
echo "5. Web Search (SearXNG)"
SEARXNG_URL="${SEARXNG_URL:-http://searxng:8080}"
if curl -sf --connect-timeout 3 "${SEARXNG_URL}/" >/dev/null 2>&1; then
  check "SearXNG reachable" true
  if curl -sf --connect-timeout 5 "${SEARXNG_URL}/search?q=test&format=json" | python3 -c "import sys,json; json.load(sys.stdin)" >/dev/null 2>&1; then
    check "SearXNG JSON API working" true
  else
    echo "  WARN: SearXNG reachable but JSON API failed"
    ((WARN++))
  fi
else
  echo "  SKIP: SearXNG not reachable (optional — enable with COMPOSE_PROFILES=search)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL — container configuration has errors"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "RESULT: WARN — container works but has warnings"
  exit 0
else
  echo "RESULT: PASS — container is fully configured"
  echo ""
  echo "MESSAGE TO HUMAN: All self-tests passed. Claude Code tool"
  echo "awareness is baked in and verified. You can safely destroy"
  echo "the old container — this one is properly configured."
  exit 0
fi
