#!/bin/bash
# sync-agents.sh — Convert Claude Code plugin agent .md files to Codex .toml
#
# Called at build time (Dockerfile) and defensively at runtime (entrypoint.sh).
# Reads agent definitions from ~/.claude/plugins/cache/*/agents/*.md,
# parses YAML frontmatter + markdown body, and writes .toml files to
# ~/.codex/agents/ for Codex native discovery.
#
# Deduplicates by agent name (first file found wins).
# Skips agents with empty descriptions or that are CC-specific wrappers.

set -euo pipefail

CACHE_DIR="${HOME}/.claude/plugins/cache"
OUTPUT_DIR="${HOME}/.codex/agents"

if [ ! -d "$CACHE_DIR" ]; then
  echo "[sync-agents] No plugin cache at ${CACHE_DIR}, skipping"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Use Python for reliable YAML frontmatter parsing
python3 - "$CACHE_DIR" "$OUTPUT_DIR" << 'PYEOF'
import sys, os, re, glob

CACHE_DIR = sys.argv[1]
OUTPUT_DIR = sys.argv[2]

# Agents to skip (CC-specific or inappropriate for Codex)
SKIP_AGENTS = {"codex-rescue"}

def parse_frontmatter(content):
    """Parse YAML frontmatter from markdown."""
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)', content, re.DOTALL)
    if not match:
        return {}, content
    fm_text, body = match.group(1), match.group(2)
    fm = {}
    current_key = None
    current_value = []
    for line in fm_text.split('\n'):
        key_match = re.match(r'^(\w[\w-]*):\s*(.*)', line)
        if key_match:
            if current_key:
                fm[current_key] = '\n'.join(current_value).strip()
            current_key = key_match.group(1)
            val = key_match.group(2)
            if val in ('>', '|', '>-', '|-'):
                current_value = []
            else:
                current_value = [val]
        elif current_key and (line.startswith('  ') or line.startswith('\t')):
            current_value.append(line.strip())
        elif current_key and line.strip() == '':
            current_value.append('')
    if current_key:
        fm[current_key] = '\n'.join(current_value).strip()
    return fm, body.strip()

def to_toml(fm, body):
    """Convert parsed agent to TOML string."""
    name = fm.get('name', 'unknown')
    desc = fm.get('description', '').replace('\n', ' ').strip()
    if len(desc) > 600:
        desc = desc[:597] + '...'
    disallowed = fm.get('disallowedTools', '')
    if 'Write' in disallowed and 'Edit' in disallowed:
        sandbox = 'read-only'
    else:
        sandbox = 'danger-full-access'
    escaped_desc = desc.replace('\\', '\\\\').replace('"""', '\\"\\"\\"')
    escaped_body = body.replace('\\', '\\\\').replace('"""', '\\"\\"\\"')
    return (
        f'name = "{name}"\n'
        f'description = """\\\n{escaped_desc}"""\n'
        f'sandbox_mode = "{sandbox}"\n\n'
        f'developer_instructions = """\\\n{escaped_body}\n"""\n'
    )

seen = set()
converted = 0
skipped = 0

for md_path in sorted(glob.glob(os.path.join(CACHE_DIR, '*', '*', '*', 'agents', '*.md'))):
    basename = os.path.splitext(os.path.basename(md_path))[0]
    if basename in seen or basename in SKIP_AGENTS:
        continue
    try:
        with open(md_path) as f:
            content = f.read()
        fm, body = parse_frontmatter(content)
        name = fm.get('name', basename)
        desc = fm.get('description', '').strip()
        if not desc:
            skipped += 1
            continue
        toml = to_toml(fm, body)
        out_path = os.path.join(OUTPUT_DIR, f'{basename}.toml')
        with open(out_path, 'w') as f:
            f.write(toml)
        seen.add(basename)
        converted += 1
    except Exception as e:
        print(f"[sync-agents] Warning: failed to convert {md_path}: {e}",
              file=sys.stderr)

print(f"[sync-agents] Converted {converted} agents, skipped {skipped}")
PYEOF
