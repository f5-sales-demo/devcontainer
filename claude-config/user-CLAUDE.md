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
