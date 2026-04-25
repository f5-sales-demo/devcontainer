#!/bin/sh
# retry — run a command with exponential backoff.
#
# Usage: retry [MAX_ATTEMPTS] COMMAND [ARGS...]
#   MAX_ATTEMPTS  optional integer (default 5). Backoff: 5 s, 10 s, 20 s, 40 s, 80 s.
#
# Examples:
#   retry git clone --depth=1 https://github.com/org/repo.git /opt/repo
#   retry 8 npm install -g some-package
set -eu

max=5
if [ "${1:-}" -gt 0 ] 2>/dev/null; then max="$1"; shift; fi

n=0
delay=5
until "$@"; do
  n=$((n + 1))
  if [ "$n" -ge "$max" ]; then
    echo "retry: '$*' failed after $max attempts" >&2
    exit 1
  fi
  echo "retry: attempt $n/$max failed, retrying in ${delay}s..." >&2
  sleep "$delay"
  delay=$((delay * 2))
done
