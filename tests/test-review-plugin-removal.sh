#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
SETTINGS="${REPO_ROOT}/claude-config/settings.json"
DOCKERFILE="${REPO_ROOT}/Dockerfile"

jq -e '
  .enabledPlugins["code-review@claude-plugins-official"] == null and
  .enabledPlugins["pr-review-toolkit@claude-plugins-official"] == null and
  .enabledPlugins["codex@openai-codex"] == null and
  .extraKnownMarketplaces["openai-codex"] == null and
  ((.hooks.Stop // []) | length == 0)
' "${SETTINGS}" >/dev/null

if grep -Eq 'f5-sales-demo/codex-plugin-cc|marketplaces/openai-codex|"openai-codex"' "${DOCKERFILE}"; then
  echo "Deprecated Codex marketplace remains in Dockerfile" >&2
  exit 1
fi

for source in "${DOCKERFILE}" "${REPO_ROOT}/claude-config/self-test.sh"; do
  if grep -Eqi 'attack-navigator|ATT&CK Navigator' "${source}"; then
    echo "Optional ATT&CK Navigator integration remains in ${source}" >&2
    exit 1
  fi
done

echo "Deprecated optional review and Navigator integrations are absent"
