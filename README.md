# Dev Container

A batteries-included [devcontainer](https://containers.dev) for software development with built-in AI coding tools and an API proxy.

## Quick Start

```bash
# 1. Configure
cp .env.example .env
cat >> .env << EOF
USER_UID=$(id -u)
USER_GID=$(id -g)
USERNAME=$(whoami)
GIT_AUTHOR_NAME=$(git config user.name)
GIT_AUTHOR_EMAIL=$(git config user.email)
EOF

# 2. Edit .env — set your API keys
nano .env

# 3. (Optional) Add SSH key
echo "SSH_PRIVATE_KEY=$(base64 < ~/.ssh/id_ed25519)" >> .env

# 4. Run
docker compose up -d --build && docker compose exec dev zsh
```

First boot takes ~1 minute. Clone your repos into `/workspace` and start coding.

## What's Included

### Via Devcontainer Features (auto-installed)
| Category | Tools |
|----------|-------|
| **Languages** | Node.js, Python, Go, Rust, Java |
| **AI Coding** | Claude Code, OpenCode, Codex |
| **Cloud CLIs** | AWS CLI, Azure CLI, PowerShell |
| **DevOps** | Docker, kubectl, Helm, Terraform, tflint |
| **Dev Tools** | GitHub CLI, act, terraform-docs, prettier, uv, devcontainers-cli |

### Via Dockerfile (always present)
| Category | Tools |
|----------|-------|
| **System** | git, vim, neovim, tmux, fzf, ripgrep, fd, bat, jq, yq, curl, wget |
| **Media** | ffmpeg, poppler-utils, qrencode, yt-dlp |
| **Network** | nmap, tcpdump, traceroute, dnsutils |
| **Linting** | actionlint |

### Via post-create script (after features install)
| Category | Tools |
|----------|-------|
| **Python** | pre-commit, ansible, black, pylint, yamllint |
| **npm** | markdownlint-cli2, openclaw |

## Data Persistence

All data lives in Docker named volumes (no host mounts):

| Volume | Path | Contents |
|--------|------|----------|
| `workspace` | `/workspace` | Your code and repos |
| `home` | `/home/<username>` | Shell config, SSH, git, tools, caches |

Data persists across restarts and rebuilds. To start fresh: `docker compose down -v`

## VS Code / Devcontainer CLI

For the full experience (features + extensions), open in VS Code:

```bash
# Option A: VS Code
code .

# Option B: CLI
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

## Troubleshooting

```bash
docker compose logs proxy                              # Check proxy
docker compose down && docker compose up -d --build    # Rebuild (keeps data)
docker compose down -v && docker compose up -d --build # Full reset
```
