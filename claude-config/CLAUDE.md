# Claude Code Tool Awareness (Container Default)

This file is the User-level CLAUDE.md, loaded in every Claude Code
session regardless of the project directory. It is seeded by the
devcontainer entrypoint at first startup.

## Tool Naming Convention

All Claude Code tools use PascalCase. NEVER use snake_case.

| Correct | WRONG (never use) | Purpose |
| --- | --- | --- |
| `Read` | `read_file`, `read`, `cat` | Read file contents |
| `Write` | `write_file`, `write`, `create_file` | Create/overwrite files |
| `Edit` | `edit_file`, `edit`, `sed` | Edit existing files |
| `MultiEdit` | `multi_edit`, `multiedit` | Multiple edits in one call |
| `Bash` | `bash`, `run_command`, `shell`, `execute` | Run shell commands |
| `Glob` | `glob`, `find_files`, `list_files` | Find files by pattern |
| `Grep` | `grep`, `search`, `search_files` | Search file contents |
| `Task` | `task`, `run_task`, `agent` | Launch subagent tasks |
| `WebFetch` | `web_fetch`, `fetch`, `curl` | Fetch a URL and return its contents |
| `WebSearch` | `web_search`, `search_web` | Search the web and return results |

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

## Self-Test

Run `claude-self-test` to verify container configuration is correct.
