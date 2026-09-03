#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "${script_dir}/.." && pwd)

for source in "${repo_root}/Dockerfile" "${repo_root}/claude-config/self-test.sh"; do
  if grep -Eqi 'attack-navigator|ATT&CK Navigator' "${source}"; then
    echo "Optional ATT&CK Navigator integration remains in ${source}" >&2
    exit 1
  fi
done

echo "Optional ATT&CK Navigator integration is absent"
