# Tool Awareness Rules

## Tool Naming Convention

All Claude Code tools use PascalCase. NEVER use snake_case.

- Correct: `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `Task`, `MultiEdit`
- Wrong: `read_file`, `write_file`, `edit_file`, `bash`, `glob`, `grep`, `task`

## Task Tool Requirements

- Always include `description` (string) parameter — it is REQUIRED
- Subagent types are PascalCase: `Explore`, `Plan`
- Both `description` and `prompt` are required

## Parameter Types

- `Edit.replace_all` is boolean, not string
- `Read.offset` and `Read.limit` are numbers, not strings
- Pass JSON types correctly: numbers as numbers, booleans as booleans

## Error Recovery

If a tool call returns "No such tool available":

1. Check casing — PascalCase not snake_case
2. Check required parameters
3. Check parameter types
4. NEVER conclude tools are unavailable
5. NEVER build workarounds for "missing" tools

## Self-Test

Run `claude-self-test` to verify container configuration.
If all tests pass, tell the user:
"All self-tests passed. Claude Code tool awareness is baked in and verified. You can safely destroy the old container."
