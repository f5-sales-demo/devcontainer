# Dev Container

A batteries-included [devcontainer](https://containers.dev) for software development with built-in AI coding tools and an API proxy.

## Setup

```bash
# 1. Configure
cp .env.example .env
echo "USER_UID=$(id -u)" >> .env
echo "USER_GID=$(id -g)" >> .env
echo "USERNAME=$(whoami)" >> .env
echo "GIT_AUTHOR_NAME=$(git config user.name)" >> .env
echo "GIT_AUTHOR_EMAIL=$(git config user.email)" >> .env

# 2. (Optional) Add SSH key for git clone over SSH
echo "SSH_PRIVATE_KEY=$(base64 < ~/.ssh/id_ed25519)" >> .env

# 3. Edit .env — set your API endpoint (the two REQUIRED lines at the top)
nano .env

# 4. Run
docker compose up -d --build && docker compose exec dev zsh
```

Clone your repos into `/workspace` and start coding. First boot takes ~1 minute to install AI tools.

## What Goes in `.env`

```
OPENAI_API_KEY=sk-your-api-key-here
OPENAI_BASE_URL=https://your-api-endpoint.example.com/v1
```

Everything else has sensible defaults. See `.env.example` for all options.

## What's Included

| Category | Tools |
|----------|-------|
| **Languages** | Node.js 24, Python 3.13, Go, Rust, Java |
| **AI Coding** | Claude Code, OpenCode, Codex, OpenClaw |
| **DevOps** | Docker, kubectl, Helm, Terraform, pre-commit |
| **Utilities** | git, gh, vim, neovim, tmux, ripgrep, fzf, jq, yq, curl, nmap |

AI tools are installed on first boot using native installers where available. They persist in the home volume, self-update, and are owned by your user.

## Data Persistence

All data lives in Docker named volumes (no host mounts):

| Volume | Path | Contents |
|--------|------|----------|
| `workspace` | `/workspace` | Your code and repos |
| `home` | `/home/<username>` | Shell config, SSH, git, tools, caches |

Data persists across restarts and rebuilds. To start fresh: `docker compose down -v`

## Adding Tools

Edit `.devcontainer/tools.txt` (one install command per line), then rebuild:

```bash
docker compose up -d --build
```

Or add system packages directly to the `Dockerfile`.

## Troubleshooting

```bash
docker compose logs proxy                              # Check proxy
docker compose down && docker compose up -d --build    # Rebuild (keeps data)
docker compose down -v && docker compose up -d --build # Full reset
```
