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
echo "3. Project Memory (Tool Awareness)"
MEMORY_FOUND=false
for SUFFIX in "-workspace-devcontainer" "-workspace"; do
  MP="$HOME/.claude/projects/${SUFFIX}/memory/MEMORY.md"
  if [ -f "$MP" ]; then
    MEMORY_FOUND=true
    check "MEMORY.md at $SUFFIX" test -f "$MP"
    check "contains PascalCase reference" grep -q "PascalCase" "$MP"
    check "contains Read tool entry" grep -q '`Read`' "$MP"
    check "contains Task subagent types" grep -q "Explore" "$MP"
    check "warns against snake_case" grep -q "snake_case" "$MP"
    break
  fi
done
if [ "$MEMORY_FOUND" = false ]; then
  echo "  FAIL: No MEMORY.md found in any project path"
  ((FAIL++))
fi

echo ""
echo "4. Project Rules"
RULES_DIR=""
for DIR in /workspace/devcontainer /workspace; do
  if [ -d "$DIR/.claude/rules" ]; then
    RULES_DIR="$DIR/.claude/rules"
    break
  fi
done
if [ -n "$RULES_DIR" ]; then
  check "rules directory exists" test -d "$RULES_DIR"
  check "tool-awareness rule present" test -f "$RULES_DIR/tool-awareness.md"
  check "session-startup rule present" test -f "$RULES_DIR/session-startup.md"
else
  echo "  WARN: No .claude/rules/ directory found (optional)"
  ((WARN++))
fi

echo ""
echo "5. Container Environment"
check "workspace directory exists" test -d /workspace
check "home directory writable" test -w "$HOME"
check "TERM is set" test -n "${TERM:-}"

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
