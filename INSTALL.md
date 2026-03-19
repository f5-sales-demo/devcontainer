# OpenCode + Oh-My-OpenCode — Workstation Setup Guide

> **Audience**: This document is written as plain-language instructions for OpenCode itself.
> Launch `opencode`, paste the URL to this file, and OpenCode will execute each step.
>
> **Platform**: macOS on Apple Silicon (arm64). Homebrew is already installed.
> OpenCode is already installed via `brew install opencode`.

---

## Security Principles

Every instruction in this guide follows these rules:

- **Never use `sudo`** for any software install. All tools install to user-owned directories (`/opt/homebrew`, `~/.bun`, `~/.config`, `~/.cache`).
- **Homebrew owns `/opt/homebrew`** with permissions `0755`, owned by the current user. No root access required.
- **npm global packages** install under `/opt/homebrew/lib` (Homebrew-managed Node.js). No `sudo` needed.
- **Bun** installs to `~/.bun` — a single binary, user-owned, no system modification.
- **API keys** are exported as environment variables in `~/.zshrc`, never committed to Git repositories.
- **All config files** live under `~/.config/opencode/` following the XDG Base Directory convention.
- **Claude Code plugins** are installed to `~/.claude/plugins/` — entirely within `$HOME`, no system paths touched.
- **Podman** is the corporate-standard container runtime. Docker Desktop is **not permitted**. A lightweight shim at `~/.local/bin/docker` transparently routes any `docker` command to `podman`.

---

## Step 1 — Install Homebrew Dependencies

These are the brew packages required by OpenCode and its LSP/tooling ecosystem. Run each `brew install` command. Skip any package that is already installed.

```bash
# Core runtime (required by opencode)
brew install node
brew install ripgrep

# GitHub CLI (used by opencode for PR/issue operations)
brew install gh

# Terminal multiplexer (used by opencode for interactive sessions)
brew install tmux

# LSP servers installed via brew (opencode auto-detects these on PATH)
brew install marksman          # Markdown language server
brew install shellcheck        # Shell script static analysis (used by bash-language-server)
brew install shfmt             # Shell script formatter
brew install terraform-ls      # Terraform language server (HashiCorp)

# Git hooks and project governance
brew install pre-commit        # Git hook framework (enforces linting and branch policies)

# Container runtime — corporate standard is Podman (Docker is not permitted)
brew install podman            # OCI container runtime — runs in a user-space VM, no sudo
brew install podman-compose    # docker-compose compatible CLI for podman
```

### Verify Brew Installations

```bash
node --version        # Expected: v25.x or later
npm --version         # Expected: 11.x or later
npx --version         # Expected: 11.x or later
rg --version          # Expected: 15.x or later
gh --version          # Expected: 2.x or later
tmux -V               # Expected: 3.x or later
marksman --version    # Should print a date
shellcheck --version  # Expected: 0.10+
shfmt --version       # Expected: 3.x
terraform-ls --version # Expected: 0.x
pre-commit --version  # Expected: pre-commit 4.x
podman --version      # Expected: podman 5.x
```

---

## Step 2 — Install npm Global Packages (LSP Servers)

These are language servers that OpenCode discovers on `PATH` via `which()`. When found, OpenCode uses the brew/npm-installed version instead of auto-downloading its own copy.

**Important**: Because Node.js is installed via Homebrew, `npm install -g` writes to `/opt/homebrew/lib` which is user-owned. No `sudo` required.

```bash
npm install -g vscode-langservers-extracted   # HTML, CSS, JSON, ESLint LSP servers
npm install -g bash-language-server           # Bash/Zsh/Shell LSP
npm install -g yaml-language-server           # YAML LSP
npm install -g @mdx-js/language-server        # MDX LSP
npm install -g @taplo/cli                     # TOML LSP (taplo)
```

### Verify npm Global Packages

```bash
npm list -g --depth=0
```

Expected output should include:

```
├── @mdx-js/language-server@0.6.3
├── @taplo/cli@0.7.0
├── bash-language-server@5.6.0
├── vscode-langservers-extracted@4.10.0
└── yaml-language-server@1.21.0
```

---

## Step 3 — Install Bun

Bun is used by OpenCode internally for plugin management. Install it to `~/.bun` (user-space, no sudo):

```bash
curl -fsSL https://bun.com/install | bash
```

### Verify Bun

```bash
source ~/.zshrc
which bun       # Expected: /Users/<you>/.bun/bin/bun
bun --version   # Expected: 1.3.x or later
```

---

## Step 4 — Install Google Chrome

Chrome is required by the `chrome-devtools-mcp` MCP server for browser automation. Install it via Homebrew Cask — this places it at `/Applications/Google Chrome.app` which is the path referenced in the `opencode.json` MCP configuration.

```bash
brew install --cask google-chrome
```

Chrome auto-updates itself after installation. No `sudo` is required — Homebrew Cask installs applications to `/Applications` using the current user's permissions.

### Verify Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

Expected: `Google Chrome 144.x` or later.

---

## Step 5 — Install Terminal Environment (iTerm2, Oh My Zsh, Theme, Plugins)

A modern terminal environment is required for inline image display (`imgcat`), syntax-highlighted command output, autosuggestions, and a context-rich shell prompt. This step installs the complete terminal stack.

### 5.1 — Install iTerm2

```bash
brew install --cask iterm2
```

iTerm2 bundles command-line utilities — including `imgcat`, `imgls`, `it2api` — inside the app at `/Applications/iTerm.app/Contents/Resources/utilities/`. When running inside iTerm2, this directory is added to `PATH` automatically. To ensure these utilities are always available (including when a shell is launched by opencode or another process), the `PATH` addition is made explicit in `~/.zshrc` (see Step 13).

### 5.2 — Install Oh My Zsh

Oh My Zsh is a framework for managing Zsh configuration, plugins, and themes. The installer creates `~/.zshrc` from a template — any prior `.zshrc` is backed up automatically.

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

The `--unattended` flag prevents the installer from switching the default shell or launching a new session. Oh My Zsh is installed to `~/.oh-my-zsh/` — entirely within `$HOME`.

### 5.3 — Install Powerlevel10k Theme and Fonts

Powerlevel10k is a fast, highly-configurable Zsh prompt theme that uses special glyphs (icons, branch symbols, lock icons, etc.) which require a patched Nerd Font. Install the theme, its recommended font, and the full Nerd Font collection:

```bash
# Powerlevel10k theme
brew install powerlevel10k
ln -sf /opt/homebrew/share/powerlevel10k ~/.oh-my-zsh/custom/themes/powerlevel10k

# Fonts — MesloLGS NF is Powerlevel10k's recommended font with optimized glyphs
brew install --cask font-meslo-for-powerlevel10k
brew install --cask font-meslo-lg-nerd-font
```

Homebrew Cask installs fonts to `~/Library/Fonts/` — user-owned, no `sudo` required. After installation, configure iTerm2 to use the font:

1. Open **iTerm2** → **Settings** (⌘,) → **Profiles** → **Text**
2. Set **Font** to `MesloLGS NF` at size 13
3. Ensure **Use ligatures** is checked

Without this font, Powerlevel10k's prompt will display placeholder rectangles instead of icons and branch symbols.

### 5.4 — Install Zsh Plugins

These plugins provide fish-shell-like autosuggestions and real-time syntax highlighting. Clone them into Oh My Zsh's custom plugins directory:

```bash
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

### 5.5 — Configure `~/.zshrc` for Oh My Zsh

The Oh My Zsh installer creates a `~/.zshrc` with defaults. The following settings must be present in the file. If they already exist, update them to match; if not, add them.

**Theme** — set near the top of `~/.zshrc`:

```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```

**Plugins** — find the `plugins=(...)` line and set:

```bash
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)
```

| Plugin | What It Does |
| ------ | ------------ |
| `git` | Git aliases and prompt integration (`gst`, `gco`, `gp`, branch status in prompt) |
| `z` | Frecency-based directory jumping (`z project` jumps to most-used matching path) |
| `zsh-autosuggestions` | Fish-like inline suggestions from command history (accept with →) |
| `zsh-syntax-highlighting` | Real-time color coding of commands as you type (green = valid, red = error) |

### 5.6 — Configure Powerlevel10k Prompt

On first launch in iTerm2 after setting the theme, Powerlevel10k's configuration wizard runs automatically. Follow the prompts to choose your preferred style. The wizard writes `~/.p10k.zsh`.

To re-run the wizard at any time:
```bash
p10k configure
```

### Verify Terminal Environment

```bash
ls "/Applications/iTerm.app/Contents/Resources/utilities/imgcat"       # Expected: file exists
ls ~/.oh-my-zsh/oh-my-zsh.sh                                          # Expected: file exists
ls ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme    # Expected: symlink to /opt/homebrew/share
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions                     # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting                 # Expected: directory exists
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                          # Expected: file exists (p10k font)
ls ~/Library/Fonts/MesloLGSNerdFont-Regular.ttf 2>/dev/null \
  || ls ~/Library/Fonts/MesloLGLNerdFont-Regular.ttf                   # Expected: Nerd Font installed
```

---

## Step 6 — Install Claude Code Plugins (Skills for Oh-My-OpenCode)

Oh-My-OpenCode scans `~/.claude/plugins/` for Claude Code plugins and loads their SKILL.md files as available skills. Claude Code itself does **not** need to be installed — only the plugin directory structure is required.

This step clones the official plugin marketplace, copies each enabled plugin into the cache directory, clones the superpowers framework separately, and generates the JSON registry files that oh-my-opencode reads at startup.

### 6.1 — Clone the Official Plugin Marketplace

```bash
mkdir -p ~/.claude/plugins/marketplaces
git clone --depth=1 --single-branch --branch main \
  https://github.com/anthropics/claude-plugins-official.git \
  ~/.claude/plugins/marketplaces/claude-plugins-official
```

### 6.2 — Install Each Plugin into the Cache

Run the following script. It copies each enabled plugin from the marketplace clone into the versioned cache directory, clones the external superpowers plugin from GitHub, and builds the `installed_plugins.json` registry.

```bash
PLUGIN_BASE="$HOME/.claude/plugins"
MARKETPLACE="${PLUGIN_BASE}/marketplaces/claude-plugins-official"
CACHE="${PLUGIN_BASE}/cache/claude-plugins-official"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
GIT_SHA="$(cd "$MARKETPLACE" && git rev-parse HEAD)"

mkdir -p "$CACHE"

printf '[' > "${PLUGIN_BASE}/installed_plugins.json"
FIRST=true

for NAME in frontend-design superpowers code-review code-simplifier feature-dev ralph-loop typescript-lsp commit-commands security-guidance claude-md-management pr-review-toolkit skill-creator claude-code-setup hookify; do
  SRC=""
  if [ -d "${MARKETPLACE}/plugins/${NAME}" ]; then
    SRC="${MARKETPLACE}/plugins/${NAME}"
  elif [ -d "${MARKETPLACE}/external_plugins/${NAME}" ]; then
    SRC="${MARKETPLACE}/external_plugins/${NAME}"
  fi

  VERSION="0.0.0"
  if [ -n "$SRC" ] && [ -f "${SRC}/.claude-plugin/plugin.json" ]; then
    V="$(jq -r '.version // empty' "${SRC}/.claude-plugin/plugin.json")"
    [ -n "$V" ] && VERSION="$V"
  fi

  DEST="${CACHE}/${NAME}/${VERSION}"
  mkdir -p "$DEST"

  if [ -n "$SRC" ]; then
    cp -a "${SRC}/." "$DEST/"
  elif [ "$NAME" = "superpowers" ]; then
    git clone --depth=1 --single-branch --branch main \
      https://github.com/obra/superpowers.git "$DEST"
    if [ -f "${DEST}/.claude-plugin/plugin.json" ]; then
      V="$(jq -r '.version // empty' "${DEST}/.claude-plugin/plugin.json")"
      if [ -n "$V" ]; then
        VERSION="$V"
        NEW_DEST="${CACHE}/${NAME}/${VERSION}"
        if [ "$DEST" != "$NEW_DEST" ]; then
          mkdir -p "$NEW_DEST"
          cp -a "${DEST}/." "$NEW_DEST/"
          rm -rf "$DEST"
          DEST="$NEW_DEST"
        fi
      fi
    fi
  else
    echo "WARNING: no source found for plugin '$NAME', skipping"
    rm -rf "${CACHE}/${NAME}"
    continue
  fi

  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    printf ',\n' >> "${PLUGIN_BASE}/installed_plugins.json"
  fi

  printf '  {\n    "name": "%s",\n    "marketplace": "claude-plugins-official",\n    "scope": "user",\n    "version": "%s",\n    "installPath": "%s",\n    "lastUpdated": "%s",\n    "gitCommitSha": "%s"\n  }' \
    "$NAME" "$VERSION" "$DEST" "$TIMESTAMP" "$GIT_SHA" \
    >> "${PLUGIN_BASE}/installed_plugins.json"
done

printf '\n]\n' >> "${PLUGIN_BASE}/installed_plugins.json"
```

### 6.3 — Create Supporting Registry Files

```bash
PLUGIN_BASE="$HOME/.claude/plugins"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

# Marketplace registry
printf '{"claude-plugins-official":{"source":{"source":"github","repo":"anthropics/claude-plugins-official"},"installLocation":"%s","lastUpdated":"%s"}}' \
  "${PLUGIN_BASE}/marketplaces/claude-plugins-official" \
  "$TIMESTAMP" \
  > "${PLUGIN_BASE}/known_marketplaces.json"

# Empty blocklist
printf '{"fetchedAt":"%s","plugins":[]}' "$TIMESTAMP" > "${PLUGIN_BASE}/blocklist.json"
```

### 6.4 — Write `~/.claude/settings.json`

This tells oh-my-opencode which plugins are enabled. Write the file `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "feature-dev@claude-plugins-official": true,
    "ralph-loop@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "pr-review-toolkit@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true,
    "hookify@claude-plugins-official": true
  }
}
```

### Verify Plugin Installation

```bash
# Check installed_plugins.json has all 14 plugins
jq 'length' ~/.claude/plugins/installed_plugins.json
# Expected: 14

# Check SKILL.md files were loaded
find ~/.claude/plugins/cache -name "SKILL.md" -type f | wc -l
# Expected: 19 (5 from official plugins + 14 from superpowers)

# Check all files are user-owned
ls -la ~/.claude/settings.json
ls -la ~/.claude/plugins/installed_plugins.json
```

---

## Step 7 — Install OpenCode Plugin SDK Dependencies

OpenCode uses a `package.json` in its config directory for local plugin SDK dependencies. Create and install:

```bash
mkdir -p ~/.config/opencode
```

Write the file `~/.config/opencode/package.json` with the following content:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.2.20"
  }
}
```

Then install the dependencies:

```bash
cd ~/.config/opencode && bun install && cd -
```

This creates `~/.config/opencode/node_modules/` with the OpenCode plugin SDK.

---

## Step 8 — Write `opencode.json`

This is the main OpenCode configuration file. Write the file `~/.config/opencode/opencode.json` with the following content.

**Before writing**: Replace `YOUR_API_KEY_HERE` with your actual API key, and `YOUR_OPENAI_PROXY_BASE_URL` / `YOUR_ANTHROPIC_PROXY_BASE_URL` with the correct proxy endpoint URLs for your organization.

**Chrome flags explained**: The `--chromeArg` entries disable Chrome 115+'s automatic HTTP→HTTPS upgrading. Without these flags, Chrome silently redirects `http://` URLs to `https://`, which breaks demo environments that serve plain HTTP only. The three disabled features are:

| Feature Disabled | What It Would Do If Enabled |
| ---------------- | --------------------------- |
| `HttpsFirstBalancedModeAutoEnable` | Automatically enables HTTPS-First Mode on sites Chrome thinks support HTTPS |
| `HttpsUpgrades` | Silently rewrites `http://` navigations to `https://` before the request is sent |
| `HttpsFirstModeV2` | Shows a full-page interstitial warning when falling back to HTTP |

The remaining flags (`--no-first-run`, `--no-default-browser-check`, `--disable-extensions`, `--disable-background-timer-throttling`, `--disable-backgrounding-occluded-windows`) ensure a clean, automation-friendly Chrome session. No sandbox or GPU flags are needed on macOS — those are Linux container workarounds.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "command": [
        "npx",
        "-y",
        "chrome-devtools-mcp@latest",
        "--executablePath",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "--chromeArg=--disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades,HttpsFirstModeV2",
        "--chromeArg=--no-first-run",
        "--chromeArg=--no-default-browser-check",
        "--chromeArg=--disable-extensions",
        "--chromeArg=--disable-background-timer-throttling",
        "--chromeArg=--disable-backgrounding-occluded-windows"
      ]
    }
  },
  "provider": {
    "openai-proxy": {
      "name": "OpenAI Proxy",
      "options": {
        "baseURL": "YOUR_OPENAI_PROXY_BASE_URL",
        "apiKey": "YOUR_API_KEY_HERE"
      },
      "models": {
        "gpt-5.4": {
          "name": "GPT 5.4",
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          },
          "limit": {
            "context": 1000000,
            "output": 128000
          },
          "options": {
            "reasoningSummary": null
          }
        },
        "grok-code-fast-1": {
          "name": "Explore",
          "modalities": {
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 256000,
            "output": 256000
          }
        }
      }
    },
    "anthropic-proxy": {
      "name": "Anthropic Proxy",
      "options": {
        "baseURL": "YOUR_ANTHROPIC_PROXY_BASE_URL",
        "apiKey": "YOUR_API_KEY_HERE"
      },
      "models": {
        "claude-opus-4-6": {
          "name": "Claude Opus 4.6",
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          },
          "limit": {
            "context": 1000000,
            "output": 128000
          }
        },
        "claude-sonnet-4-6": {
          "name": "Claude Sonnet 4.6",
          "modalities": {
            "input": ["text", "image"],
            "output": ["text"]
          },
          "limit": {
            "context": 1000000,
            "output": 64000
          }
        }
      }
    }
  },
  "model": "anthropic-proxy/claude-opus-4-6",
  "small_model": "anthropic-proxy/claude-sonnet-4-6",
  "permission": {
    "read": {
      "*": "allow",
      "*.env": "allow",
      "*.env.*": "allow"
    }
  },
  "plugin": [
    "@robinmordasiewicz/oh-my-opencode@3.11.0-fork.1"
  ]
}
```

---

## Step 9 — Write `oh-my-opencode.json`

This configures the Oh-My-OpenCode plugin — agent model assignments, task category routing, and background concurrency. Write the file `~/.config/opencode/oh-my-opencode.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",
  "agents": {
    "sisyphus": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "oracle": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "librarian": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "explore": {
      "model": "openai-proxy/grok-code-fast-1"
    },
    "multimodal-looker": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "prometheus": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "metis": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "hephaestus": {
      "model": "openai-proxy/gpt-5.4"
    },
    "momus": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "atlas": {
      "model": "anthropic-proxy/claude-sonnet-4-6"
    },
    "frontend-ui-ux-engineer": {
      "model": "openai-proxy/gpt-5.4"
    },
    "document-writer": {
      "model": "anthropic-proxy/claude-opus-4-6"
    }
  },
  "categories": {
    "visual-engineering": {
      "model": "openai-proxy/gpt-5.4"
    },
    "business-logic": {
      "model": "openai-proxy/gpt-5.4"
    },
    "ultrabrain": {
      "model": "openai-proxy/gpt-5.4"
    },
    "deep": {
      "model": "openai-proxy/gpt-5.4"
    },
    "artistry": {
      "model": "openai-proxy/gpt-5.4"
    },
    "quick": {
      "model": "anthropic-proxy/claude-sonnet-4-6"
    },
    "unspecified-low": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "unspecified-high": {
      "model": "anthropic-proxy/claude-opus-4-6"
    },
    "writing": {
      "model": "anthropic-proxy/claude-opus-4-6"
    }
  },
  "background_task": {
    "defaultConcurrency": 5,
    "providerConcurrency": {
      "openai-proxy": 5,
      "anthropic-proxy": 5
    }
  }
}
```

---

## Step 10 — Write `AGENTS.md`

This file contains global rules injected into every OpenCode LLM session. Write the file `~/.config/opencode/AGENTS.md`:

```markdown
# Global Rules

## Tool Usage

- ALWAYS use the Read tool on a file before using Edit or Write on it, even if you saw its contents earlier in the conversation. The Edit tool will reject changes to unread files.

## Surgical Changes

- If your changes make imports/variables/functions unused, remove those orphans. Do not remove pre-existing dead code unless asked.

## Error Handling

- Use specific error types over catch-all handlers.

## Code Style

- Prefer pure functions. Only modify return values, not input parameters or global state.
- All imports at the top of the file.
- Check if logic already exists in the codebase before writing new code.

## Communication

- Do not explain code unless asked. Do not summarize what you did unless asked.
```

---

## Step 11 — Write `tui.json`

This configures the OpenCode terminal UI. Write the file `~/.config/opencode/tui.json`:

```json
{
  "$schema": "https://opencode.ai/tui.json",
  "scroll_acceleration": {
    "enabled": true
  }
}
```

---

## Step 12 — Write `.gitignore`

If you plan to version-control your OpenCode config directory, this `.gitignore` prevents tracking generated files. Write the file `~/.config/opencode/.gitignore`:

```
node_modules
package.json
bun.lock
.gitignore
```

---

## Step 13 — Configure `~/.zshrc` (Environment Variables and PATH)

Oh My Zsh (Step 5) created `~/.zshrc` with its own boilerplate. This file has a specific structure — the Powerlevel10k instant prompt **must** be at the very top, the Oh My Zsh `source` line stays in the middle, and user additions go at the end. If any of the lines below already exist, skip them. Do not duplicate entries.

### 13.1 — Top of File: Powerlevel10k Instant Prompt

This block **must be the first thing** in `~/.zshrc` (before any other code that produces output). It enables sub-millisecond prompt rendering by caching the prompt while the rest of `.zshrc` loads in the background. Without it, the terminal flickers briefly on each new shell.

```bash
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
```

### 13.2 — Middle: Oh My Zsh Settings (already present)

The following lines were set in Step 5.5 and should already be in `~/.zshrc`. Verify they are present:

```bash
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh
```

### 13.3 — After `source $ZSH/oh-my-zsh.sh`: User Configuration

Add the following lines **after** the `source $ZSH/oh-my-zsh.sh` line:

```bash
# Homebrew (Apple Silicon)
eval $(/opt/homebrew/bin/brew shellenv)

# Powerlevel10k config (written by `p10k configure` wizard)
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# User-local binaries (docker shim, etc.)
export PATH="$HOME/.local/bin:$PATH"

# iTerm2 utilities (imgcat, imgls, it2api, etc.)
export PATH="/Applications/iTerm.app/Contents/Resources/utilities:$PATH"

# API key for AI proxy (replace with your actual key)
export F5AI_API_KEY="YOUR_API_KEY_HERE"

# Enable 1M token context for Anthropic models
export ANTHROPIC_1M_CONTEXT=true
```

### Reload the Shell

```bash
source ~/.zshrc
```

---

## Step 14 — Install Project Tooling (Containers, Git Hooks, Docker Shim)

These tools support the standard development workflow across all repositories: container-based linting via pre-commit hooks, OCI container builds, and compatibility with tools that expect a `docker` CLI.

### 14.1 — Ensure Podman is Running

The corporate standard container runtime is **Podman**. Docker Desktop is not permitted. Podman runs containers in a lightweight user-space VM with no root privileges required.

Verify Podman is installed and the machine is running:

```bash
podman --version       # Expected: podman 5.x or later
podman machine list    # Expected: one machine with "Currently running" status
```

If the machine is not running:
```bash
podman machine start
```

If no machine exists:
```bash
podman machine init --cpus 4 --memory 8192 --disk-size 80
podman machine start
```

### 14.2 — Create a Podman-to-Docker Compatibility Shim

Many third-party tools (super-linter, CI scripts, Makefiles) hardcode the `docker` CLI command. Since Docker is not permitted on corporate workstations, create a one-line shim that transparently forwards all `docker` invocations to `podman`:

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/docker << 'EOF'
#!/bin/sh
# Podman compatibility shim — corporate standard forbids Docker Desktop
exec /opt/homebrew/bin/podman "$@"
EOF
chmod +x ~/.local/bin/docker
```

Verify the shim works:
```bash
~/.local/bin/docker --version   # Expected: podman version 5.x (proxied)
docker --version                 # Expected: podman 5.x (routed via shim, once PATH is updated in Step 14)
```

### 14.3 — Verify pre-commit

pre-commit was installed in Step 1 via Homebrew. Verify it is available:

```bash
pre-commit --version   # Expected: pre-commit 4.x or later
```

To activate pre-commit hooks in any repository that uses `.pre-commit-config.yaml`:

```bash
cd <repository-root>
pre-commit install
```

---

## Step 15 — Verify the Complete Installation

Run each of these commands to confirm everything is in place.

### 15.1 — Core Tools

```bash
opencode --version          # Expected: 1.2.20 or later
node --version              # Expected: v25.x or later
bun --version               # Expected: 1.3.x or later
npm --version               # Expected: 11.x or later
rg --version                # Expected: 15.x or later
gh --version                # Expected: 2.x or later
tmux -V                     # Expected: tmux 3.x
```

### 15.2 — LSP Servers on PATH

```bash
which bash-language-server   # Expected: /opt/homebrew/bin/bash-language-server
which yaml-language-server   # Expected: /opt/homebrew/bin/yaml-language-server
which marksman               # Expected: /opt/homebrew/bin/marksman
which terraform-ls           # Expected: /opt/homebrew/bin/terraform-ls
which shellcheck             # Expected: /opt/homebrew/bin/shellcheck
which shfmt                  # Expected: /opt/homebrew/bin/shfmt
```

### 15.3 — npm Global LSP Packages

```bash
npm list -g --depth=0 2>/dev/null | grep -E "(vscode-langservers|bash-language|yaml-language|mdx-js|taplo)"
```

Expected: all five packages listed.

### 15.4 — Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

Expected: Google Chrome 144.x or later.

### 15.5 — chrome-devtools-mcp

```bash
npx -y chrome-devtools-mcp@latest --help
```

Expected: prints the CLI help with options like `--executablePath`, `--headless`, etc.

### 15.6 — OpenCode Config Files

```bash
ls -la ~/.config/opencode/opencode.json
ls -la ~/.config/opencode/oh-my-opencode.json
ls -la ~/.config/opencode/AGENTS.md
ls -la ~/.config/opencode/tui.json
ls -la ~/.config/opencode/package.json
ls -la ~/.config/opencode/node_modules/@opencode-ai/plugin/
```

All files should exist and be owned by the current user.

### 15.7 — Environment Variables

```bash
echo $BUN_INSTALL            # Expected: /Users/<you>/.bun
echo $F5AI_API_KEY           # Expected: your API key (not empty)
echo $ANTHROPIC_1M_CONTEXT   # Expected: true
```

### 15.8 — Claude Code Plugins

```bash
# Verify plugin count
jq 'length' ~/.claude/plugins/installed_plugins.json
# Expected: 14

# Verify SKILL.md files
find ~/.claude/plugins/cache -name "SKILL.md" -type f | wc -l
# Expected: 19

# Verify settings.json
jq '.enabledPlugins | keys | length' ~/.claude/settings.json
# Expected: 14
```

### 15.9 — Project Tooling (Podman, Docker Shim, pre-commit)

```bash
podman --version                # Expected: podman 5.x
podman machine list             # Expected: machine "Currently running"
~/.local/bin/docker --version   # Expected: podman 5.x (via shim)
which docker                    # Expected: ~/.local/bin/docker (once PATH includes ~/.local/bin)
pre-commit --version            # Expected: pre-commit 4.x
```

### 15.10 — Terminal Environment (iTerm2, Oh My Zsh, Theme, Plugins)

```bash
ls "/Applications/iTerm.app"                                                    # Expected: iTerm2 installed
which imgcat                                                                     # Expected: /Applications/iTerm.app/.../utilities/imgcat
ls ~/.oh-my-zsh/oh-my-zsh.sh                                                    # Expected: file exists
ls ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme             # Expected: symlink exists
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh # Expected: file exists
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting                           # Expected: directory exists
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                                    # Expected: p10k font installed
grep "^ZSH_THEME" ~/.zshrc                                                      # Expected: powerlevel10k/powerlevel10k
grep "^plugins=" ~/.zshrc                                                        # Expected: (git z zsh-autosuggestions zsh-syntax-highlighting)
```

### 15.11 — Launch OpenCode

```bash
opencode
```

OpenCode should start without errors. The Oh-My-OpenCode plugin should load automatically (you will see the Sisyphus agent and multi-agent orchestration capabilities).

---

## Troubleshooting

### Plugin fails to load

If the oh-my-opencode plugin fails to load at startup:

```bash
# Clear the plugin cache and restart
rm -rf ~/.cache/opencode/node_modules
opencode
```

OpenCode will re-download and install the plugin from npm on next launch.

### chrome-devtools-mcp fails

If Chrome browser automation does not work:

```bash
# Clear the npx cache
rm -rf ~/.npm/_npx
npm cache clean --force

# Clear the chrome-devtools-mcp browser profile
rm -rf ~/.cache/chrome-devtools-mcp/chrome-profile

# Verify Chrome path
ls "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

### LSP servers not detected

OpenCode discovers LSP servers via `which()`. Ensure your PATH includes `/opt/homebrew/bin`:

```bash
echo $PATH | tr ':' '\n' | grep homebrew
```

If `/opt/homebrew/bin` is not in the output, ensure `eval $(/opt/homebrew/bin/brew shellenv)` is in your `~/.zshrc`.

### Bun not found

```bash
# Verify bun is installed
ls ~/.bun/bin/bun

# Verify PATH includes bun
echo $PATH | tr ':' '\n' | grep bun
```

If missing, re-run: `curl -fsSL https://bun.com/install | bash` and then `source ~/.zshrc`.

---

### Claude Code plugins not loading

If oh-my-opencode does not discover the Claude Code plugins at startup:

```bash
# Verify installed_plugins.json exists and is valid JSON
jq . ~/.claude/plugins/installed_plugins.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Verify settings.json exists
cat ~/.claude/settings.json | jq .enabledPlugins

# Verify plugin install paths exist
jq -r '.[].installPath' ~/.claude/plugins/installed_plugins.json | while read p; do
  [ -d "$p" ] && echo "OK: $p" || echo "MISSING: $p"
done

# Re-run the install script from Step 6 if paths are missing
```

### Chrome cannot resolve a domain (`ERR_NAME_NOT_RESOLVED`)

macOS caches DNS failures (`NXDOMAIN`) in the `mDNSResponder` system daemon. If Chrome (or any application using the system resolver) queries a domain **before** its DNS record exists, the negative result is cached for up to 30 minutes (determined by the SOA minimum TTL). Subsequent lookups — including from a freshly launched Chrome — return the cached failure even after the real DNS record is created.

**Diagnosis**: `dig +short <domain>` resolves correctly, but Chrome shows `ERR_NAME_NOT_RESOLVED`.

**Workaround** — temporarily add a Chrome `--host-resolver-rules` flag to the `opencode.json` MCP config that maps the domain to its IP, bypassing the system resolver:

```bash
# 1. Get the domain's IP via dig (which uses its own resolver, not mDNSResponder)
dig +short <domain> @8.8.8.8

# 2. Add this flag to the chrome-devtools command array in opencode.json:
#    "--chromeArg=--host-resolver-rules=MAP <domain> <ip>"
#    Example: "--chromeArg=--host-resolver-rules=MAP app.example.com 72.19.3.185"

# 3. Restart opencode to relaunch Chrome with the new flag

# 4. After the negative cache expires (~30 minutes), remove the flag and restart opencode
```

**Prevention**: Ensure DNS records are created and propagated **before** Chrome first attempts to load the domain. If your workflow creates DNS records programmatically (e.g., via API), restart opencode after DNS creation to launch Chrome with a clean resolver cache.

**Note**: `dscacheutil -flushcache` does not reliably clear the `mDNSResponder` negative cache on macOS. The `killall -HUP mDNSResponder` command that would clear it requires elevated privileges, which are not available on corporate workstations.

---

## File Manifest

After completing all steps, your `~/.config/opencode/` directory should contain:

```
~/.config/opencode/
├── .gitignore                 # Excludes generated files from git
├── AGENTS.md                  # Global LLM instructions
├── node_modules/              # Plugin SDK dependencies (bun-managed)
│   └── @opencode-ai/
│       ├── plugin/
│       └── sdk/
├── oh-my-opencode.json        # Agent model routing and concurrency config
├── opencode.json              # Main config: providers, models, MCP, plugins
├── package.json               # Local plugin dependencies
├── bun.lock                   # Bun lockfile (auto-generated)
└── tui.json                   # Terminal UI settings
```

Your `~/.claude/` directory should contain:

```
~/.claude/
├── settings.json                          # Plugin enable/disable flags
└── plugins/
    ├── blocklist.json                     # Empty blocklist
    ├── installed_plugins.json             # Plugin registry (v3 format)
    ├── known_marketplaces.json            # Marketplace metadata
    ├── cache/
    │   └── claude-plugins-official/       # Installed plugin files
    │       ├── frontend-design/0.0.0/
    │       ├── superpowers/5.0.5/         # 14 skills, 3 commands
    │       ├── code-review/0.0.0/
    │       ├── code-simplifier/1.0.0/
    │       ├── feature-dev/0.0.0/
    │       ├── ralph-loop/0.0.0/
    │       ├── typescript-lsp/0.0.0/
    │       ├── commit-commands/0.0.0/
    │       ├── security-guidance/0.0.0/
    │       ├── claude-md-management/1.0.0/
    │       ├── pr-review-toolkit/0.0.0/
    │       ├── skill-creator/0.0.0/
    │       ├── claude-code-setup/1.0.0/
    │       └── hookify/0.0.0/
    └── marketplaces/
        └── claude-plugins-official/       # Git clone of official marketplace
```

Additionally, the following user-local binaries and runtime directories are created:

```
~/.local/bin/
└── docker                         # Podman shim — corporate standard forbids Docker Desktop

~/.cache/opencode/             # Plugin downloads, auto-installed LSP servers
~/.cache/chrome-devtools-mcp/  # Chrome browser profile for MCP
~/.npm/_npx/                   # npx cache for chrome-devtools-mcp
~/.local/share/containers/     # Podman machine storage
```
