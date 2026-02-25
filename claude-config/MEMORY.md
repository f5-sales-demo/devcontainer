## Tool Name Reference

Claude Code tools use PascalCase. NEVER use snake_case variants.

### Core Tools

| Correct | WRONG (never use) | Purpose |
|---|---|---|
| `Read` | `read_file`, `read`, `cat` | Read file contents |
| `Write` | `write_file`, `write`, `create_file` | Create/overwrite files |
| `Edit` | `edit_file`, `edit`, `sed` | Edit existing files |
| `MultiEdit` | `multi_edit`, `multiedit` | Multiple edits in one call |
| `Bash` | `bash`, `run_command`, `shell`, `execute` | Run shell commands |
| `Glob` | `glob`, `find_files`, `list_files` | Find files by pattern |
| `Grep` | `grep`, `search`, `search_files` | Search file contents |
| `Task` | `task`, `run_task`, `agent` | Launch subagent tasks |

### Task Tool

- `description` (string) — REQUIRED
- `prompt` (string) — REQUIRED
- `subagent_type` — PascalCase: `Explore`, `Plan` (not `explore`, `plan`)

### Parameter Types

- `Read`: `file_path` (string), `offset` (number), `limit` (number)
- `Write`: `file_path` (string), `content` (string)
- `Edit`: `file_path` (string), `old_string` (string), `new_string` (string), `replace_all` (boolean)
- Numbers must be numbers, not strings. Booleans must be booleans, not strings.

### Knowledge Base Tools (different system — do NOT confuse with above)

These are Open WebUI tools, NOT filesystem tools:
`view_knowledge_file`, `search_knowledge_bases`, `query_knowledge_files`,
`search_chats`, `generate_image`

### Error Recovery

If a tool call returns "No such tool available":
1. CHECK CASING FIRST — PascalCase, not snake_case
2. Check required parameters (especially `description` for Task)
3. Check parameter types (numbers not strings, booleans not strings)
4. NEVER conclude tools are unavailable — they are always present
5. NEVER build workarounds for "missing" tools — fix the tool call
