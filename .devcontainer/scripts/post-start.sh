#!/bin/bash
set -e

echo "🚀 Running post-start checks..."

# Verify proxy
echo -n "  Checking AI proxy (proxy:8082)... "
if curl -sf --connect-timeout 5 http://proxy:8082/ > /dev/null 2>&1; then
    echo "✅ reachable"
else
    echo "⚠️  Not reachable (start proxy with: docker compose up -d proxy)"
fi

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh docker kubectl helm terraform \
           pre-commit uv claude opencode codex openclaw prettier markdownlint-cli2 \
           actionlint act terraform-docs ansible black pylint yamllint yt-dlp \
           aws az pwsh devcontainer; do
    if command -v $cmd &> /dev/null; then
        ver=$($cmd --version 2>&1 | head -1 | sed 's/^[[:space:]]*//')
        printf "    ✅ %-20s %s\n" "$cmd" "$ver"
    fi
done

echo ""
echo "✅ Ready! Start coding in /workspace"
