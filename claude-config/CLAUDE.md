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
| `Task` | `task`, `run_task`, `agent` | Launch subagent tasks |

**Note:** `MultiEdit` is not available through all proxy configurations —
use sequential `Edit` calls instead.

## Task Tool Requirements

- Always include `description` (string) — it is REQUIRED
- Subagent types are PascalCase: `Explore`, `Plan`
- Both `description` and `prompt` are required

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

## Subagent (Task Tool) Limitations

When launched via the `Task` tool, subagents (Explore and Plan types)
have a **restricted tool set**. They can NOT use filesystem or shell tools.

### Tools available to subagents

Subagents can only use knowledge-base and utility tools:

- `list_knowledge_bases`, `search_knowledge_bases`, `query_knowledge_bases`
- `search_knowledge_files`, `query_knowledge_files`, `view_knowledge_file`
- `search_chats`, `view_chat`
- `generate_image`
- `get_current_timestamp`, `calculate_timestamp`

### Tools NOT available to subagents

- `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`
- `Task` (subagents cannot launch further subagents)

### Implication for the main session

Do NOT delegate filesystem exploration, shell commands, or file reading
to subagents. Perform those operations directly in the main session.
Use subagents only for knowledge-base search, chat history search,
and planning/reasoning tasks that don't require filesystem access.

## Bash Tool Escaping

The Bash tool escapes `!` to `\!` on all platforms. This
happens in the transport layer before the shell receives
the command. Avoid `!` in all generated Bash commands.

### jq — use `| not` instead of `!=`

| Avoid | Use Instead |
| ----- | ----------- |
| `select(.x != "y")` | `select((.x == "y") \| not)` |
| `if .x != "y"` | `if ((.x == "y") \| not)` |

### Bash — avoid `!` in conditionals

| Avoid | Use Instead |
| ----- | ----------- |
| `if ! cmd; then` | `cmd \|\| { handle; }` |
| `while ! test; do` | `until test; do` |

### Escape hatch — single-quoted heredoc

When `!` is unavoidable, use `<<'EOF'` (single-quoted
delimiter prevents transport-layer escaping):

    cat <<'SCRIPT' > /tmp/run.sh
    #!/bin/bash
    if ! command -v foo; then echo missing; fi
    SCRIPT
    bash /tmp/run.sh

## Self-Test

Run `claude-self-test` to verify container configuration is correct.
