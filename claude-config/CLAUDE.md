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
| `Bash` | `bash`, `run_command`, `shell`, `execute` | Run shell commands |
| `Glob` | `glob`, `find_files`, `list_files` | Find files by pattern |
| `Grep` | `grep`, `search`, `search_files` | Search file contents |
| `Task` | `task`, `run_task`, `agent` | Launch subagent tasks |
| `WebFetch` | `web_fetch`, `fetch`, `curl` | Fetch a URL and return its contents |
| `WebSearch` | `web_search`, `search_web` | Search the web and return results |

**Note:** `WebSearch` requires a direct Anthropic API connection — it is
a server-side tool executed by the Anthropic backend. Through a proxy, the
tool is silently dropped and returns 0 results. Use the SearXNG fallback
below or `WebFetch` for direct URL retrieval.
`MultiEdit` is not available through all proxy configurations — use
sequential `Edit` calls instead.

## Web Search

The built-in `WebSearch` tool only works with a direct Anthropic API
connection. When running through a proxy, use these alternatives:

### SearXNG (self-hosted, no API key needed)

If the search profile is enabled (`COMPOSE_PROFILES=proxy,search`),
a SearXNG metasearch engine is available inside the Docker network:

```bash
curl -s "http://searxng:8080/search?q=your+query&format=json" | jq '.results[:5]'
```

Use `Bash` with `curl` to query SearXNG and parse the JSON results.

### WebFetch (built-in, works through proxy)

Use `WebFetch` to retrieve content from a specific URL when you already
know where to look.

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
