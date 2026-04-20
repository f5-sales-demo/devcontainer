# Container Context

You are running inside an ephemeral Docker container built from
[f5xc-salesdemos/devcontainer](https://github.com/f5xc-salesdemos/devcontainer).
All filesystem changes are lost on container restart.

Your build fingerprint is in `/etc/devcontainer-version`.
Run `claude-self-test` to verify container health.

The `f5xc-devcontainer` plugin handles all container awareness:

- Identity questions ("who are you", "what version") → `self-awareness` skill
- Tool lookups ("which tool should I use to...") → `tool-catalog` skill
- Self-diagnosis and health checks → `container-introspector` agent
- Tool installation and maintenance → `container-maintainer` agent
- Catalog drift detection → `tool-auditor` agent

## Skill Routing — Prefer Skills Over Built-in Tools

When a skill exists for a task, ALWAYS invoke the skill instead of using
a built-in tool directly. Skills provide better results because they use
locally hosted, purpose-built infrastructure.

### Web Content (URLs)

- **Any URL fetch, scrape, or content extraction** → invoke `f5xc-firecrawl:scrape` skill
- **Crawling multiple pages** → invoke `f5xc-firecrawl:crawl` skill
- **Site URL discovery** → invoke `f5xc-firecrawl:map` skill
- **Web search** → invoke `f5xc-firecrawl:search` skill
- **Structured data extraction** → invoke `f5xc-firecrawl:extract` skill
- Prefer firecrawl over built-in `WebFetch` — firecrawl runs locally on port 3002,
  produces cleaner Markdown, and handles JS-rendered pages

### Tool Selection

- **"Which tool should I use?"** → invoke `f5xc-devcontainer:tool-catalog` skill

### Container Identity

- **"Who are you?" / version / health** → invoke `f5xc-devcontainer:self-awareness` skill
