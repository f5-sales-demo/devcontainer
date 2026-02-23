#!/bin/bash
set -e

echo "🚀 Running post-start checks..."

export PATH="$HOME/.local/bin:$(npm prefix -g 2>/dev/null)/bin:$PATH"

# Verify proxy
echo -n "  Checking AI proxy (proxy:8082)... "
if curl -sf --connect-timeout 5 http://proxy:8082/ > /dev/null 2>&1; then
    echo "✅ reachable"
else
    echo "⚠️  Not reachable"
fi

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh docker kubectl helm terraform pre-commit uv claude opencode codex openclaw; do
    if command -v $cmd &> /dev/null; then
        printf "    ✅ %-12s %s\n" "$cmd" "$($cmd --version 2>&1 | head -1)"
    fi
done

echo ""
echo "✅ Ready! Start coding in /workspace"
echo ""
