#!/bin/bash
# post-start.sh — Runs every time the container starts
set -e

echo "🚀 Running post-start checks..."

# Verify proxy connectivity
echo -n "  Checking AI proxy (proxy:8082)... "
if curl -sf --connect-timeout 5 http://proxy:8082/ > /dev/null 2>&1; then
    echo "✅ reachable"
else
    echo "⚠️  Not reachable"
    echo "  Check proxy container: docker compose logs proxy"
fi

# Quick API test
echo -n "  Testing API... "
RESPONSE=$(curl -sf --connect-timeout 5 http://proxy:8082/v1/messages -X POST \
  -H "x-api-key: changeme" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"gpt-4o","max_tokens":5,"messages":[{"role":"user","content":"say ok"}]}' 2>/dev/null) && \
  echo "✅ responding" || echo "⚠️  not responding (check API endpoint and network)"

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh docker kubectl helm terraform claude opencode codex pre-commit uv; do
    if command -v $cmd &> /dev/null; then
        printf "    ✅ %-12s %s\n" "$cmd" "$($cmd --version 2>&1 | head -1)"
    fi
done

echo ""
echo "✅ Ready! Start coding in /workspace"
echo ""
