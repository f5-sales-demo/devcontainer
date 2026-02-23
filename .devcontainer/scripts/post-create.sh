#!/bin/bash
# post-create.sh — Runs once after the container is first created
set -e

echo "🔧 Running post-create setup..."

# Ensure cache directories exist with correct ownership
mkdir -p "$HOME/.cache/opencode" "$HOME/.cache/pre-commit"

# Seed AI tool configs
if [ ! -f "$HOME/.claude.json" ] || [ ! -s "$HOME/.claude.json" ]; then
    echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
    echo "  ✅ Seeded AI tool config"
fi

# Ensure hasCompletedOnboarding is set (even if file exists from host)
python3 -c "
import json, os
path = os.path.expanduser('~/.claude.json')
try:
    with open(path) as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
if not d.get('hasCompletedOnboarding'):
    d['hasCompletedOnboarding'] = True
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
    print('  ✅ Set hasCompletedOnboarding=true')
else:
    print('  ✅ hasCompletedOnboarding already set')
"

# Install any additional global tools from tools.txt
if [ -f "/workspace/.devcontainer/tools.txt" ]; then
    echo "  📦 Installing additional tools from tools.txt..."
    while IFS= read -r tool || [ -n "$tool" ]; do
        [[ "$tool" =~ ^#.*$ || -z "$tool" ]] && continue
        echo "    Installing: $tool"
        eval "$tool" || echo "    ⚠️  Failed: $tool"
    done < "/workspace/.devcontainer/tools.txt"
fi

echo "✅ Post-create setup complete!"
