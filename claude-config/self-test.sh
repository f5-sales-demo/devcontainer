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
echo "3. Tool Awareness (User-level CLAUDE.md)"
USER_CLAUDE="$HOME/.claude/CLAUDE.md"
if [ -f "$USER_CLAUDE" ]; then
  check "~/.claude/CLAUDE.md exists" test -f "$USER_CLAUDE"
  check "contains PascalCase reference" grep -q "PascalCase" "$USER_CLAUDE"
  check "contains Read tool entry" grep -q '`Read`' "$USER_CLAUDE"
  check "contains Task tool requirements" grep -q "description" "$USER_CLAUDE"
  check "warns against snake_case" grep -q "snake_case" "$USER_CLAUDE"
  check "mentions self-test" grep -q "claude-self-test" "$USER_CLAUDE"
else
  echo "  FAIL: ~/.claude/CLAUDE.md not found"
  ((FAIL++))
fi

echo ""
echo "4. Container Environment"
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
