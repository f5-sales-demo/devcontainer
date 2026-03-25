# Claude Code Tool Awareness (Container Default)

This file is the Managed policy CLAUDE.md, installed at
`/etc/claude-code/CLAUDE.md` during image build. It is loaded in every
Claude Code session at the highest priority tier, regardless of the
working directory or project-level instructions.

## Tool Naming Convention

All Claude Code tools use PascalCase. NEVER use snake_case.

| Correct | WRONG (never use) | Purpose |
| --- | --- | --- |
| `Read` | `read_file`, `read`, `cat` | Read file contents |
| `Write` | `write_file`, `write`, `create_file` | Create/overwrite files |
| `Edit` | `edit_file`, `edit`, `sed` | Edit existing files |
| `Bash` | `bash`, `run_command`, `shell`, `execute` | Run shell commands |
| `Glob` | `glob`, `find_files`, `list_files` | Find files by pattern |
| `Grep` | `grep`, `search`, `search_files` | Search file contents |
| `Agent` | `agent`, `task`, `run_task` | Launch subagent tasks |

## Agent Tool Requirements

- Always include `description` (string) — it is REQUIRED
- Both `description` and `prompt` are required
- Use `subagent_type` to select specialized agents (e.g., `Explore`, `Plan`)

## Parameter Types

- Numbers must be numbers, not strings
- Booleans must be booleans, not strings
- `Edit.replace_all` is boolean, `Read.offset` and `Read.limit` are numbers

## Error Recovery

If a tool call returns "No such tool available":

1. Check casing — PascalCase not snake_case
2. Check required parameters
3. Check parameter types
4. NEVER conclude tools are unavailable — they are always present
5. NEVER build workarounds for "missing" tools — fix the tool call

## Agent Subagent Capabilities

- **general-purpose**: Full tool access — `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`
- **Explore**: Read-only — `Glob`, `Grep`, `Read`, `Bash` (output only)
- **Plan**: Read-only — same as Explore

## Bash Tool Escaping

The Bash tool escapes `!` to `\!` on all platforms. Avoid `!` in all
generated Bash commands.

- jq: use `| not` instead of `!=`
- Bash: use `cmd || { handle; }` instead of `if ! cmd; then`

## Self-Test

Run `claude-self-test` to verify container configuration is correct.
