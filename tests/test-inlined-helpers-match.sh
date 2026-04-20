#!/usr/bin/env bash
# Ensures the inlined fetch_governed/revision_is_fresh functions in
# consumer workflows stay byte-identical with the canonical source at
# tests/fixtures/fetch-governed.sh.
#
# Workflows that use reusable workflow_call instead of inlining the
# helpers are skipped gracefully — there is nothing to drift-check.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
SOURCE="${REPO_ROOT}/tests/fixtures/fetch-governed.sh"

# Extract just the two function definitions from the canonical source,
# stripping shebang, comments, and blank lines. This is what we expect
# to find verbatim (modulo leading whitespace) inside each consumer.
# sed handles all filtering so the pipeline never fails on empty input.
canonical=$(awk '
  /^fetch_governed\(\)/,/^}$/ { print; next }
  /^revision_is_fresh\(\)/,/^}$/ { print }
' "$SOURCE" | sed -e 's/^[[:space:]]*//' -e '/^$/d' -e '/^#/d')

FAIL=0
CHECKED=0
for wf in \
  "${REPO_ROOT}/.github/workflows/sync-managed-files.yml" \
  "${REPO_ROOT}/.github/workflows/enforce-repo-settings.yml"; do

  # Skip workflows that do not exist (repo may use reusable workflow_call)
  if [ ! -f "$wf" ]; then
    echo "[SKIP] $(basename "$wf") — file not found"
    continue
  fi

  # sed handles all filtering so the pipeline never fails on empty input
  # (awk + sed always exit 0, unlike grep which exits 1 on no match).
  inlined=$(awk '
    /fetch_governed\(\)/,/^[[:space:]]*}[[:space:]]*$/ { print; next }
    /revision_is_fresh\(\)/,/^[[:space:]]*}[[:space:]]*$/ { print }
  ' "$wf" | sed -e 's/^[[:space:]]*//' -e '/^$/d' -e '/^#/d')

  # Skip workflows that do not inline the helpers (reusable workflow_call)
  if [ -z "$inlined" ]; then
    echo "[SKIP] $(basename "$wf") — no inlined helpers found"
    continue
  fi

  CHECKED=$((CHECKED + 1))
  if [ "$inlined" = "$canonical" ]; then
    echo "[OK] $(basename "$wf") helper matches canonical"
  else
    echo "[FAIL] $(basename "$wf") helper drifted from canonical"
    diff <(printf '%s\n' "$canonical") <(printf '%s\n' "$inlined") || true
    FAIL=1
  fi
done

if [ "$CHECKED" -eq 0 ]; then
  echo "[INFO] No workflows with inlined helpers to check"
fi

exit "$FAIL"
