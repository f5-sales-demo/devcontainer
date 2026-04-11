#!/usr/bin/env bash
# npx Resolution Test Suite (TDD)
#
# Verifies that 'npx <tool>' resolves the same version as the
# direct '<tool>' command for all system-installed npm packages.
# Without the user-prefix symlinks, npx downloads wrong packages
# (e.g. 'npx biome' → env-var manager instead of the linter).
#
# Run:  bash tests/test-npx-resolution.sh
set -euo pipefail

PASS=0
FAIL=0

compare_versions() {
  local name="$1" cmd="$2"
  local direct_ver npx_ver

  direct_ver=$("$cmd" --version 2>&1 | head -1) || direct_ver="(error)"
  npx_ver=$(timeout 15 npx "$cmd" --version 2>&1 | head -1) || npx_ver="(error)"

  if [ "$direct_ver" = "$npx_ver" ]; then
    echo "  PASS: $name — $direct_ver"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name — direct='$direct_ver' npx='$npx_ver'"
    FAIL=$((FAIL + 1))
  fi
}

# Test that npx does NOT download the deprecated 'tsc' stub
test_npx_tsc() {
  local ver
  ver=$(timeout 15 npx tsc --version 2>&1 | head -1) || ver="(error)"
  if echo "$ver" | grep -q "^Version"; then
    echo "  PASS: npx tsc — $ver"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: npx tsc — got '$ver' (expected TypeScript version)"
    FAIL=$((FAIL + 1))
  fi
}

# Test that npx biome is the linter (v2+), not the env-var manager (v0.3)
test_npx_biome() {
  local ver
  ver=$(timeout 15 npx biome --version 2>&1 | head -1) || ver="(error)"
  if echo "$ver" | grep -qE "^(Version: )?[1-9]"; then
    echo "  PASS: npx biome — $ver"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: npx biome — got '$ver' (expected v2+, got wrong package)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Critical conflict tests (wrong package downloaded) ==="
test_npx_tsc
test_npx_biome

echo ""
echo "=== Version match tests (npx should use pre-installed version) ==="
compare_versions "eslint" "eslint"
compare_versions "prettier" "prettier"
compare_versions "pnpm" "pnpm"
compare_versions "pyright" "pyright"
compare_versions "stylelint" "stylelint"
compare_versions "htmlhint" "htmlhint"
compare_versions "jscpd" "jscpd"
compare_versions "textlint" "textlint"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$FAIL"
