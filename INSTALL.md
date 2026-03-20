# OpenCode + Oh-My-OpenCode — Workstation Setup Guide

> **Audience**: This document is written as plain-language instructions for OpenCode itself.
> Launch `opencode`, paste the URL to this file, and OpenCode will execute each step.
>
> **Platform**: macOS on Apple Silicon (arm64). Homebrew is already installed.
> OpenCode is already installed via `brew install opencode`.
>
> **First-time setup**: If this is a fresh OpenCode install, you **must** complete Step 0 manually
> before running `opencode run`. Step 0 grants the AI agent permission to access directories
> outside the project root (`~/.config`, `~/.claude`, `~/.cache`, `/opt/homebrew`, etc.) which
> is required by nearly every step in this guide. Without Step 0, `opencode run` will fail with
> permission errors because the default policy prompts for confirmation — which is impossible in
> non-interactive mode.
>
> **Execution notes**: This document is long (~1200 lines). Execute steps sequentially — do not
> skip ahead. Each step includes inline VERIFY comments that must pass before proceeding.
> Steps marked **MANUAL STEP** require human interaction and should be skipped during automated runs.

---

## Preflight Check — Verify Permissions Before Starting

**AI agent: run this check FIRST, before doing anything else.** If it fails, print the error message and stop immediately — do not attempt any other steps.

```bash
if ! jq -e '
  (.permission == "allow") or
  ((.permission.read == "allow" or .permission.read["*"] == "allow") and
   (.permission.edit == "allow" or .permission.edit["*"] == "allow") and
   (.permission.bash == "allow" or .permission.bash["*"] == "allow") and
   (.permission.external_directory == "allow" or .permission.external_directory["*"] == "allow"))
' ~/.config/opencode/opencode.json > /dev/null 2>&1; then
  echo ""
  echo "ERROR: OpenCode permissions are not configured for automated setup."
  echo ""
  echo "This guide needs to read and write files outside the project directory"
  echo "(~/.config, ~/.claude, ~/.cache, /opt/homebrew, etc.). Without the"
  echo "correct permissions, every step will fail."
  echo ""
  echo "Paste the following into your terminal, then rerun the command:"
  echo ""
  echo '  rm -rf ~/.config/opencode'
  echo '  mkdir -p ~/.config/opencode'
  echo '  cat > ~/.config/opencode/opencode.json << '"'"'EOF'"'"''
  echo '  {'
  echo '    "$schema": "https://opencode.ai/config.json",'
  echo '    "permission": "allow"'
  echo '  }'
  echo '  EOF'
  echo ""
  exit 1
fi
echo "Preflight check passed — permissions are configured correctly."
```

---

## Prerequisites

This guide uses a `.env` file (in the repository root) as the **single source of truth** for all environment variables. The `.env` file is gitignored and holds secrets used by Podman containers (`docker-compose.yml`) and by the OpenCode configuration files.

- **First run**: Step 8 creates `.env` from `.env.example` and auto-detects values from command-line tools (`gh`, `git config`, system timezone).
- **Re-runs**: Step 8 reads the existing `.env` and only updates variables that are missing or still have placeholder values.
- **Required variables** (`LITELLM_API_KEY`, `LITELLM_BASE_URL`) cannot be auto-detected from command-line tools. However, if an existing `opencode.json` is present from a prior setup, Step 8 will extract these values from its provider configuration. The AI agent only prompts the user if the values are still missing after this fallback.
- **Git identity** (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`) is auto-detected from `git config`. If not configured, the AI agent will prompt the user and set them via `git config --global`.

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

## Step 0 — Bootstrap OpenCode Permissions (Manual Prerequisite)

> **MANUAL STEP (required before `opencode run`):** This step must be performed by the user — not by an AI agent. It grants OpenCode's AI agent permission to access directories outside the project root, which is required by every subsequent step.

**Why this is necessary**: OpenCode's default permission policy is `"ask"` — the agent must request user confirmation before reading or writing files outside the project directory, running shell commands, or accessing external paths like `~/.config`, `~/.claude`, `/opt/homebrew`, etc. In interactive mode (the TUI), this works fine — the user clicks "allow". But `opencode run` is **non-interactive**: there is no UI to approve permission requests, so the agent fails immediately.

This step creates a minimal `opencode.json` that sets `"permission": "allow"` — a blanket grant that lets the agent use all tools and access all paths without confirmation prompts. Step 9 later overwrites this file with the full configuration (providers, models, MCP servers, etc.), so this bootstrap config is temporary.

**When to skip**: If you already have a `~/.config/opencode/opencode.json` with a `"permission"` key that is set to `"allow"` (or has explicit `"allow"` rules for `read`, `edit`, `bash`, and `external_directory`), you can skip this step.

Run the following in your terminal:

```bash
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow"
}
EOF
```

### Verify Step 0

```bash
cat ~/.config/opencode/opencode.json
```

VERIFY: output shows `"permission": "allow"`. The file must be valid JSON.

### Now Run the Automated Setup

After creating the bootstrap config, you can launch the automated setup. Run this from the repository root:

```bash
opencode run "read the @INSTALL.md file and follow the instructions and accept all prompts as yes"
```

OpenCode will read this document and execute Steps 1–16 sequentially. The `"permission": "allow"` config ensures the agent can access all required paths without prompting.

---

## Step 1 — Install Homebrew Dependencies

These are the brew packages required by OpenCode and its LSP/tooling ecosystem. Homebrew is idempotent — running `brew install` on an already-installed package prints a warning and exits with code 0. No pre-checks are needed.

**Known issue — stale Cellar directories**: Some packages (notably `trivy`) can leave behind a Cellar directory from a previous version after an upgrade or partial uninstall. When Homebrew tries to pour a newer bottle, it fails with `Error: /opt/homebrew/Cellar/<pkg>/<version> is not a directory` because a directory for a *different* version already exists. The workaround is to remove the stale Cellar entry and re-link. A helper function below handles this automatically for all packages.

```bash
# Helper function: install a brew package with stale-Cellar recovery.
# On re-runs, Homebrew may fail to pour a new bottle version if an old
# Cellar directory from a previous version still exists (commonly seen
# with trivy, but can affect any package). This function:
#   1. Attempts a normal `brew install`.
#   2. If that fails, removes the stale Cellar directory and retries.
#   3. If the retry also fails, forces a re-link of whatever version
#      is already in the Cellar (covers the case where the binary
#      exists but symlinks are missing).
brew_install() {
  local pkg="$1"
  if brew install "$pkg" 2>&1; then
    return 0
  fi
  echo "  ⚠ brew install $pkg failed — checking for stale Cellar entry..."
  local cellar="/opt/homebrew/Cellar/$pkg"
  if [ -d "$cellar" ]; then
    echo "  Removing stale Cellar directory: $cellar"
    rm -rf "$cellar"
    if brew install "$pkg" 2>&1; then
      return 0
    fi
  fi
  # Final fallback: if a Cellar entry exists (perhaps re-created by the
  # failed pour), attempt to link whatever version is present.
  if [ -d "$cellar" ]; then
    echo "  Attempting to link existing Cellar entry for $pkg..."
    brew link --overwrite "$pkg" 2>&1 || true
  fi
}

# Core runtime (required by opencode)
brew_install node
brew_install ripgrep
brew_install jq                # JSON processor (used by plugin install scripts in Step 6)

# GitHub CLI (used by opencode for PR/issue operations)
brew_install gh

# Terminal multiplexer (used by opencode for interactive sessions)
brew_install tmux

# LSP servers installed via brew (opencode auto-detects these on PATH)
brew_install marksman          # Markdown language server
brew_install shellcheck        # Shell script static analysis (used by bash-language-server)
brew_install shfmt             # Shell script formatter
brew install hashicorp/tap/terraform-ls 2>/dev/null \
  || brew_install terraform-ls  # Terraform language server (prefers HashiCorp tap, falls back to core)

# Git hooks and project governance
brew_install pre-commit        # Git hook framework (enforces linting and branch policies)

# Container runtime — corporate standard is Podman (Docker is not permitted)
brew_install podman            # OCI container runtime — runs in a user-space VM, no sudo
brew_install podman-compose    # docker-compose compatible CLI for podman

# Common CLI utilities (mirrors devcontainer toolset for consistent local experience)
brew_install wget              # HTTP/FTP download tool
brew_install curl              # Newer curl with HTTP/3 (macOS ships an older version)
brew_install watch             # Repeat commands periodically (not included in macOS)
brew_install coreutils         # GNU coreutils (gdate, gsort, gls, etc. — macOS ships BSD variants)
brew_install gnu-sed           # GNU sed (macOS ships BSD sed with incompatible flags)
brew_install tree              # Directory tree viewer
brew_install bat               # cat with syntax highlighting and git integration
brew_install eza               # Modern ls replacement with icons and git status
brew_install fzf               # Fuzzy finder for files, history, and command output
brew_install lsd               # ls replacement with color and icons (Nerd Font aware)
brew_install yq                # YAML/JSON/XML processor (like jq for YAML)

# Development runtimes and tools (mirrors devcontainer toolset)
brew_install python            # Python 3.13 runtime (macOS ships an older system Python)
brew_install go                # Go compiler (build terraform providers, CLI tools)
brew_install terraform         # Infrastructure as Code for cloud resources
brew_install neovim            # Terminal editor with LSP support
brew_install uv                # Fast Python package manager (10-100x faster than pip)
brew_install dos2unix          # Convert Windows CRLF line endings to Unix LF

# Cloud CLI
brew_install azure-cli         # Azure resource management

# Terraform ecosystem
brew_install tflint            # Terraform linter (catches errors before plan)
brew_install terraform-docs    # Auto-generate Terraform module documentation

# Linting and security scanning
brew_install hadolint          # Dockerfile linter (best practices enforcement)
brew_install gitleaks          # Secret scanner (catches leaked credentials pre-commit)
brew_install trivy             # Vulnerability scanner for containers and code
brew_install sslscan           # TLS/SSL configuration scanner
brew_install nuclei            # Web application vulnerability scanner
brew_install trufflehog        # Deep git history secret scanner

# Media tools
brew_install ffmpeg            # Video/audio processing (convert, extract, transcode)
brew_install yt-dlp            # Video downloader (YouTube and other sites)
```

### Verify Brew Installations

Run each command and confirm the output matches. If any command fails, re-run the corresponding `brew install` above.

```bash
node --version         # VERIFY: output starts with v25 (v25.x+)
npm --version          # VERIFY: output starts with 11 (11.x+)
npx --version          # VERIFY: output starts with 11 (11.x+)
rg --version           # VERIFY: output contains "ripgrep"
gh --version           # VERIFY: output contains "gh version 2"
tmux -V                # VERIFY: output contains "tmux 3" or higher
jq --version           # VERIFY: output starts with "jq-1"
marksman --version     # VERIFY: prints a version string (any output = success)
shellcheck --version   # VERIFY: output contains "version: 0.10" or higher
shfmt --version        # VERIFY: output starts with "v3"
terraform-ls --version # VERIFY: output contains a version number
pre-commit --version   # VERIFY: output contains "pre-commit 4" or higher
podman --version       # VERIFY: output contains "podman version 5" or higher
wget --version         # VERIFY: output contains "GNU Wget"
curl --version         # VERIFY: output starts with "curl" followed by a version number
watch --version        # VERIFY: output contains "watch from procps"
gdate --version        # VERIFY: output contains "GNU coreutils" (coreutils prefixes with 'g')
gsed --version         # VERIFY: output contains "GNU sed"
tree --version         # VERIFY: output contains "tree v"
bat --version          # VERIFY: output starts with "bat"
eza --version          # VERIFY: output starts with "v"
fzf --version          # VERIFY: output contains a version number
lsd --version          # VERIFY: output starts with "lsd"
yq --version           # VERIFY: output contains "yq" followed by a version number
python3 --version      # VERIFY: output starts with "Python 3.13"
go version             # VERIFY: output contains "go1."
terraform --version    # VERIFY: output contains "Terraform v1"
nvim --version         # VERIFY: output contains "NVIM v"
uv --version           # VERIFY: output starts with "uv"
dos2unix --version     # VERIFY: output contains "dos2unix"
az --version           # VERIFY: output contains "azure-cli" (first run may be slow)
tflint --version       # VERIFY: output starts with "TFLint version"
terraform-docs --version # VERIFY: output contains a version number
hadolint --version     # VERIFY: output contains "Haskell Dockerfile Linter"
gitleaks version       # VERIFY: output contains a version number
trivy --version        # VERIFY: output starts with "Version:"
sslscan --version      # VERIFY: output contains "sslscan version"
nuclei --version       # VERIFY: output contains "nuclei"
trufflehog --version   # VERIFY: output contains a version number
ffmpeg -version        # VERIFY: output starts with "ffmpeg version"
yt-dlp --version       # VERIFY: output contains a version string
```

---

## Step 2 — Install npm Global Packages (LSP Servers)

These are language servers that OpenCode discovers on `PATH` via `which()`. When found, OpenCode uses the brew/npm-installed version instead of auto-downloading its own copy.

**Important**: Because Node.js is installed via Homebrew, `npm install -g` writes to `/opt/homebrew/lib` which is user-owned. No `sudo` required.

**Note**: Unlike `brew install`, `npm install -g` always re-downloads even if the package is already installed. This is safe but adds ~30 seconds of network I/O on re-runs.

```bash
npm install -g vscode-langservers-extracted   # HTML, CSS, JSON, ESLint LSP servers
npm install -g bash-language-server           # Bash/Zsh/Shell LSP
npm install -g yaml-language-server           # YAML LSP
npm install -g @mdx-js/language-server        # MDX LSP
npm install -g @taplo/cli                     # TOML LSP (taplo)

# Code formatters (mirrors devcontainer toolset)
npm install -g prettier                       # Multi-language code formatter
npm install -g @biomejs/biome                 # Fast JS/TS/JSON linter and formatter
```

### Verify npm Global Packages

```bash
npm list -g --depth=0 2>/dev/null | grep -E "(vscode-langservers|bash-language|yaml-language|mdx-js|taplo|prettier|biome)"
```

VERIFY: All seven packages appear in the output (exact versions may differ):

- `@biomejs/biome`
- `@mdx-js/language-server`
- `@taplo/cli`
- `bash-language-server`
- `prettier`
- `vscode-langservers-extracted`
- `yaml-language-server`

---

## Step 3 — Install Bun

Bun is used by OpenCode internally for plugin management. Install it to `~/.bun` (user-space, no sudo).

**Idempotency**: The bun installer always re-downloads the binary even if already installed. The guard below skips the download when bun is already on PATH.

```bash
if ! command -v bun &>/dev/null; then
  curl -fsSL https://bun.sh/install | bash
fi
```

### Verify Bun

After installing bun, add it to the current shell's PATH so subsequent steps can use it. Do **not** run `source ~/.zshrc` — it will fail in a non-interactive shell context (Oh My Zsh and Powerlevel10k require a TTY).

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
which bun       # VERIFY: output is ~/.bun/bin/bun
bun --version   # VERIFY: output starts with "1." (1.3.x+)
```

---

## Step 4 — Install Google Chrome

Chrome is required by the `chrome-devtools-mcp` MCP server for browser automation. Install it via Homebrew Cask — this places it at `/Applications/Google Chrome.app` which is the path referenced in the `opencode.json` MCP configuration.

**Idempotency**: Unlike brew formulae, `brew install --cask` fails if the app already exists at `/Applications/` (Chrome auto-updates itself outside Homebrew's control, causing a version mismatch). Guard with an existence check:

```bash
[ -d "/Applications/Google Chrome.app" ] || brew install --cask google-chrome
```

Chrome auto-updates itself after installation. No `sudo` is required — Homebrew Cask installs applications to `/Applications` using the current user's permissions.

### Verify Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

VERIFY: output contains `Google Chrome` followed by a version number.

---

## Step 5 — Install Terminal Environment (iTerm2, Oh My Zsh, Theme, Plugins)

A modern terminal environment is required for inline image display (`imgcat`), syntax-highlighted command output, autosuggestions, and a context-rich shell prompt. This step installs the complete terminal stack.

### 5.1 — Install iTerm2

**Idempotency**: Like Chrome in Step 4, guard with an existence check — `brew install --cask` can fail or emit warnings if the app already exists:

```bash
[ -d "/Applications/iTerm.app" ] || brew install --cask iterm2
```

iTerm2 bundles command-line utilities — including `imgcat`, `imgls`, `it2api` — inside the
app at `/Applications/iTerm.app/Contents/Resources/utilities/`. When running inside iTerm2,
this directory is added to `PATH` automatically. To ensure these utilities are always available
(including when a shell is launched by opencode or another process), the `PATH` addition is
made explicit in `~/.zshrc` (see Step 14).

### 5.2 — Install Oh My Zsh

Oh My Zsh is a framework for managing Zsh configuration, plugins, and themes. The installer creates `~/.zshrc` from a template — any prior `.zshrc` is backed up automatically.

**IMPORTANT**: The Oh My Zsh installer exits with code 1 if `~/.oh-my-zsh` already exists. The `--unattended` flag does NOT bypass this check — it only disables shell switching and confirmation prompts. Always guard with an existence check:

```bash
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
```

Oh My Zsh is installed to `~/.oh-my-zsh/` — entirely within `$HOME`.

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

Homebrew Cask installs fonts to `~/Library/Fonts/` — user-owned, no `sudo` required.

Configure the default iTerm2 profile to use the installed font. iTerm2 stores its preferences in a binary plist at `~/Library/Preferences/com.googlecode.iterm2.plist`. Profile settings live in the `New Bookmarks` array — the default profile is at index 0. We use `/usr/libexec/PlistBuddy` to set the font directly.

**Why this cannot be a simple `defaults write`**: The font setting is nested inside an array of dictionaries (`New Bookmarks → [0] → Normal Font`). The `defaults` command cannot address nested keys — only `/usr/libexec/PlistBuddy` can.

**Race condition with a running iTerm2**: A running iTerm2 instance holds preferences in memory and writes them to the plist when it quits — overwriting any external changes. The script below handles this by gracefully quitting iTerm2 first (if running), waiting for it to fully exit, and then modifying the plist on disk. The user can relaunch iTerm2 afterward and the font will be active immediately.

The script handles three scenarios:

| Scenario | What happens |
| -------- | ------------ |
| iTerm2 not installed | Skipped — Step 5.1 installs it, but if this is a partial re-run without 5.1, there is nothing to configure. |
| iTerm2 installed but never launched | No plist exists yet. The script launches iTerm2 once in the background to generate default preferences, then quits it. |
| iTerm2 installed and running | The script quits iTerm2 gracefully (so it flushes in-memory prefs to disk), then overwrites the font setting. |

```bash
PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
FONT="MesloLGS-NF-Regular 13"

# Scenario 1: iTerm2 is not installed — nothing to configure.
if [ ! -d "/Applications/iTerm.app" ]; then
  echo "iTerm2 is not installed — skipping font configuration"
else
  # Scenario 3: iTerm2 is running — quit it gracefully so it flushes its
  # in-memory preferences to disk. Then we can safely overwrite the font.
  if pgrep -xq iTerm2; then
    echo "iTerm2 is running — quitting gracefully to flush preferences..."
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
    for i in $(seq 1 20); do
      pgrep -xq iTerm2 || break
      sleep 0.5
    done
    if pgrep -xq iTerm2; then
      echo "WARNING: iTerm2 did not exit within 10 seconds — force killing"
      killall iTerm2 2>/dev/null
      sleep 1
    fi
  fi

  # Scenario 2: iTerm2 was installed but never launched — no plist exists.
  # Launch it once in the background to generate default preferences, then
  # quit immediately. The brief window flash is expected.
  if [ ! -f "$PLIST" ]; then
    echo "No iTerm2 preferences found — launching once to generate defaults..."
    open -a iTerm2
    # Wait up to 8 seconds for the plist to appear (first launch is slow)
    for i in $(seq 1 16); do
      [ -f "$PLIST" ] && break
      sleep 0.5
    done
    sleep 1  # Let iTerm2 finish writing defaults
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
    for i in $(seq 1 20); do
      pgrep -xq iTerm2 || break
      sleep 0.5
    done
  fi

  # Apply the font setting
  if [ -f "$PLIST" ]; then
    CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Normal Font"' "$PLIST" 2>/dev/null)"
    if [ "$CURRENT" = "$FONT" ]; then
      echo "iTerm2 font already set to $FONT"
    else
      /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Normal Font\" \"$FONT\"" "$PLIST"
      echo "Set iTerm2 Normal Font to: $FONT"
    fi
  else
    echo "ERROR: iTerm2 plist not found at $PLIST after launch — font configuration skipped."
    echo "  Launch iTerm2 manually once, quit it, and re-run this step."
  fi
fi
```

Without this font, Powerlevel10k's prompt will display placeholder rectangles instead of icons and branch symbols.

### 5.4 — Install Zsh Plugins

These plugins provide fish-shell-like autosuggestions and real-time syntax highlighting. Clone them into Oh My Zsh's custom plugins directory.

**IMPORTANT**: `git clone` fails with exit code 128 if the target directory already exists. Always guard with an existence check:

```bash
[ -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
    ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

[ -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
    ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

### 5.5 — Configure `~/.zshrc` for Oh My Zsh

The Oh My Zsh installer creates a `~/.zshrc` with defaults. Two settings must be changed using `sed`. These commands are idempotent — they replace existing lines by pattern match, so running them twice produces the same result.

**Theme** — replace the default `ZSH_THEME="robbyrussell"` line:

```bash
sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
```

**Plugins** — replace the default `plugins=(git)` line:

```bash
sed -i '' 's/^plugins=(.*/plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
```

VERIFY both changes applied:

```bash
grep '^ZSH_THEME=' ~/.zshrc    # VERIFY: output is ZSH_THEME="powerlevel10k/powerlevel10k"
grep '^plugins=' ~/.zshrc       # VERIFY: output is plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)
```

| Plugin | What It Does |
| ------ | ------------ |
| `git` | Git aliases and prompt integration (`gst`, `gco`, `gp`, branch status in prompt) |
| `z` | Frecency-based directory jumping (`z project` jumps to most-used matching path) |
| `zsh-autosuggestions` | Fish-like inline suggestions from command history (accept with →) |
| `zsh-syntax-highlighting` | Real-time color coding of commands as you type (green = valid, red = error) |

### 5.6 — Configure Powerlevel10k Prompt

> **MANUAL STEP (skip in automated runs):** The Powerlevel10k configuration wizard is a fully interactive TUI that requires keystroke input in a real terminal. An AI agent cannot run this. The user must perform this manually:
>
> 1. Open **iTerm2** (not a regular Terminal.app session)
> 2. The wizard runs automatically on first launch after setting the theme
> 3. Follow the prompts to choose your preferred style — the wizard writes `~/.p10k.zsh`
>
> To re-run the wizard at any time: `p10k configure`

### Verify Terminal Environment

```bash
ls "/Applications/iTerm.app/Contents/Resources/utilities/imgcat"       # Expected: file exists
ls ~/.oh-my-zsh/oh-my-zsh.sh                                          # Expected: file exists
test -f ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme && echo "OK"  # Expected: file exists
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions                     # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting                 # Expected: directory exists
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                          # Expected: file exists (p10k font)
ls ~/Library/Fonts/MesloLGSNerdFont-Regular.ttf 2>/dev/null \
  || ls ~/Library/Fonts/MesloLGLNerdFont-Regular.ttf                   # Expected: Nerd Font installed
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Normal Font"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: MesloLGS-NF-Regular 13
```

---

## Step 6 — Install Claude Code Plugins (Skills for Oh-My-OpenCode)

Oh-My-OpenCode scans `~/.claude/plugins/` for Claude Code plugins and loads their SKILL.md files as available skills. Claude Code itself does **not** need to be installed — only the plugin directory structure is required.

This step clones the official plugin marketplace, copies each enabled plugin into the cache directory, clones the superpowers framework separately, and generates the JSON registry files that oh-my-opencode reads at startup.

### 6.1 — Clone the Official Plugin Marketplace

`git clone` fails with exit code 128 if the target directory already exists. Guard with an existence check. If the directory exists, pull the latest changes instead:

```bash
mkdir -p ~/.claude/plugins/marketplaces
if [ -d ~/.claude/plugins/marketplaces/claude-plugins-official/.git ]; then
  git -C ~/.claude/plugins/marketplaces/claude-plugins-official pull --ff-only
else
  git clone --depth=1 --single-branch --branch main \
    https://github.com/anthropics/claude-plugins-official.git \
    ~/.claude/plugins/marketplaces/claude-plugins-official
fi
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
    # Check if any version is already cached (avoids re-cloning on every run)
    EXISTING="$(ls -d "${CACHE}/${NAME}"/*/. 2>/dev/null | head -1)"
    if [ -n "$EXISTING" ]; then
      DEST="${EXISTING%/}"
      VERSION="$(basename "$DEST")"
    else
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

Write the file `~/.config/opencode/package.json` with the following content (versions last verified 2026-03-19):

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.2.20"
  }
}
```

Then install the dependencies (using a subshell to avoid changing the working directory):

```bash
(cd ~/.config/opencode && bun install)
```

This creates `~/.config/opencode/node_modules/` with the OpenCode plugin SDK.

### 7.1 — Pre-cache OpenCode Runtime Dependencies

On first launch, OpenCode downloads four npm packages into `~/.cache/opencode/` using bun. Pre-installing them avoids the startup delay and ensures the environment works immediately — even without internet access.

The four packages are:

| Package | Purpose |
| ------- | ------- |
| `@robinmordasiewicz/oh-my-opencode` | Oh-My-OpenCode plugin — multi-agent orchestration (Sisyphus, Oracle, Librarian, etc.) |
| `@ai-sdk/anthropic` | Vercel AI SDK provider for Anthropic models (Claude) |
| `@ai-sdk/openai-compatible` | Vercel AI SDK provider for OpenAI-compatible proxy endpoints |
| `opencode-anthropic-auth` | Authentication module for Anthropic API access |

Create the cache directory and write its `package.json`:

```bash
mkdir -p ~/.cache/opencode
```

Write the file `~/.cache/opencode/package.json` with the following content (versions last verified 2026-03-19):

```json
{
  "dependencies": {
    "@robinmordasiewicz/oh-my-opencode": "3.11.0-fork.1",
    "@ai-sdk/anthropic": "*",
    "@ai-sdk/openai-compatible": "*",
    "opencode-anthropic-auth": "0.0.13"
  }
}
```

Then install the dependencies (using a subshell to avoid changing the working directory):

```bash
(cd ~/.cache/opencode && bun install)
```

This populates `~/.cache/opencode/node_modules/` with the plugin and AI provider packages. OpenCode detects the existing install on startup and skips the download step.

### Verify Runtime Cache

```bash
ls ~/.cache/opencode/node_modules/@robinmordasiewicz/oh-my-opencode/   # Expected: directory exists
ls ~/.cache/opencode/node_modules/@ai-sdk/anthropic/                   # Expected: directory exists
ls ~/.cache/opencode/node_modules/@ai-sdk/openai-compatible/           # Expected: directory exists
ls ~/.cache/opencode/node_modules/opencode-anthropic-auth/             # Expected: directory exists
```

---

## Step 8 — Create or Update `.env` (Environment File)

This repository includes a `.env.example` template with `@auto-detect` / `@check` / `@manual` annotations. The `.env` file is gitignored and holds secrets used by `docker-compose.yml` (via Podman) and by the OpenCode config files written in later steps.

**Behavior**:

- **First run** (no `.env` exists): copy `.env.example` to `.env`, then auto-detect values.
- **Re-run** (`.env` already exists): read it, only fill in variables that are missing or still contain placeholder values.
- Auto-detectable variables are populated from command-line tools (`gh`, `git config`, system timezone).
- Manual variables that cannot be auto-detected are left as-is; the user is prompted for required ones.

### 8.1 — Bootstrap `.env`

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"
ENV_EXAMPLE="${REPO_DIR}/.env.example"

if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created .env from .env.example"
  else
    touch "$ENV_FILE"
    echo "Created empty .env (no .env.example found)"
  fi
else
  echo ".env already exists — will update in place"
fi
```

### 8.2 — Auto-Detect and Populate Variables

The following script reads `.env`, detects missing or placeholder values, and fills them using command-line tools. It is idempotent — running it again only updates variables that are still empty or set to known placeholder values.

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

# Helper: set a variable in .env only if it is missing, empty, or a known placeholder.
# Usage: env_set VARNAME "value"
env_set() {
  local key="$1" val="$2"
  if [ -z "$val" ]; then return; fi
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    local current
    current="$(grep "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2-)"
    # Strip surrounding quotes for comparison
    current="${current%\"}"
    current="${current#\"}"
    # Skip if already set to a real (non-placeholder) value
    case "$current" in
      ""|sk-example-api-key-here|you@example.com|"Example Name"|ghp_example-*|tskey-auth-example-*|https://proxy.example.com|https://proxy.example.com/*)
        sed -i '' "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
        echo "  Updated: ${key}"
        ;;
      *)
        echo "  Kept:    ${key} (already set)"
        ;;
    esac
  else
    echo "${key}=${val}" >> "$ENV_FILE"
    echo "  Added:   ${key}"
  fi
}

echo "Auto-detecting environment variables..."

# --- Timezone ---
if readlink /etc/localtime >/dev/null 2>&1; then
  _TZ="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
  env_set TZ "$_TZ"
fi

# --- Git identity ---
# Auto-detect from git config. If not configured, the AI agent must ask the
# user for their name and email, set them via git config --global, then retry.
#
# AI agent: if either command below fails (exit code != 0), ask the user:
#   "What is your full name for git commits?" → git config --global user.name "<answer>"
#   "What is your email for git commits?"     → git config --global user.email "<answer>"
# Then re-run the env_set lines.
if git config user.email >/dev/null 2>&1; then
  env_set GIT_AUTHOR_EMAIL "$(git config user.email)"
else
  echo "  PROMPT NEEDED: git user.email is not configured."
  echo "  Ask the user for their email, then run: git config --global user.email \"<email>\""
fi
if git config user.name >/dev/null 2>&1; then
  env_set GIT_AUTHOR_NAME "\"$(git config user.name)\""
else
  echo "  PROMPT NEEDED: git user.name is not configured."
  echo "  Ask the user for their full name, then run: git config --global user.name \"<name>\""
fi

# --- GitHub CLI token ---
if gh auth status >/dev/null 2>&1; then
  _GH_TOKEN="$(gh auth token 2>/dev/null)"
  [ -n "$_GH_TOKEN" ] && env_set GH_TOKEN "$_GH_TOKEN"
fi

# --- AI proxy variables (fallback: read from existing opencode.json) ---
# These two variables are normally provided by the user. However, if
# an opencode.json already exists from a previous setup, extract the values
# from the provider config so the user is not prompted again.
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
if [ -f "$OPENCODE_JSON" ]; then
  _OC_API_KEY="$(jq -r '.provider["openai-proxy"].options.apiKey // empty' "$OPENCODE_JSON" 2>/dev/null)"
  [ -n "$_OC_API_KEY" ] && env_set LITELLM_API_KEY "$_OC_API_KEY"

  _OC_BASE_URL="$(jq -r '.provider["openai-proxy"].options.baseURL // empty' "$OPENCODE_JSON" 2>/dev/null)"
  # Strip /api/v1 suffix to recover the domain-only LITELLM_BASE_URL
  _OC_BASE_URL="${_OC_BASE_URL%/api/v1}"
  [ -n "$_OC_BASE_URL" ] && env_set LITELLM_BASE_URL "$_OC_BASE_URL"
fi

echo "Auto-detection complete."
```

### 8.3 — Prompt for Required Manual Variables

The two AI proxy variables (`LITELLM_API_KEY`, `LITELLM_BASE_URL`) cannot be auto-detected from command-line tools. Step 8.2 already attempted to recover them from an existing `opencode.json`. If they are still missing or placeholders after that, the AI agent **must ask the user** for the values before proceeding.

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

MISSING=""
for VAR in LITELLM_API_KEY LITELLM_BASE_URL; do
  VAL="$(grep "^${VAR}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
  case "$VAL" in
    ""|sk-example-api-key-here|https://proxy.example.com) MISSING="${MISSING} ${VAR}" ;;
  esac
done

if [ -n "$MISSING" ]; then
  echo "The following required variables are missing or have placeholder values in .env:"
  echo " $MISSING"
  echo ""
  echo "These could not be auto-detected from command-line tools or an existing opencode.json."
  echo "Ask the user for LITELLM_API_KEY and LITELLM_BASE_URL, then update .env before proceeding."
  # AI agent: stop here and ask the user for the missing values.
  # Use env_set to write each value to .env once provided.
else
  echo "All required variables are set in .env"
fi
```

### 8.4 — Source `.env` into the Current Shell Session

After `.env` is populated, export all non-comment, non-empty lines so subsequent steps (Steps 9, 14) can reference the variables:

**Important**: macOS ships Bash 3.2 which does not support `lastpipe`. A `grep | while` pipeline runs the `while` in a subshell, so any variables exported inside it are lost when the loop ends. Use process substitution (`< <(...)`) instead to keep exports in the current shell:

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

set -a
while IFS= read -r line; do
  eval "export $line"
done < <(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$')
set +a

# VERIFY: spot-check critical variables
echo "LITELLM_API_KEY=${LITELLM_API_KEY:0:10}..."  # VERIFY: starts with "sk-" (truncated for safety)
echo "TZ=$TZ"                                       # VERIFY: a valid IANA timezone
echo "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL"           # VERIFY: an email address
```

---

## Step 9 — Write `opencode.json`

This is the main OpenCode configuration file. Write the file `~/.config/opencode/opencode.json` with the following content.

The environment variables `LITELLM_API_KEY` and `LITELLM_BASE_URL` were sourced from `.env` in Step 8.4 and should already be in the current shell session. Verify they are set:

```bash
[ -n "$LITELLM_API_KEY" ]    || { echo "ERROR: LITELLM_API_KEY is not set — re-run Step 8"; exit 1; }
[ -n "$LITELLM_BASE_URL" ]   || { echo "ERROR: LITELLM_BASE_URL is not set — re-run Step 8"; exit 1; }
echo "All required environment variables are set"
```

**Base URL derivation**:

The script derives provider URLs from `LITELLM_BASE_URL` (domain only, no path suffix):

- `openai-proxy` gets `${LITELLM_BASE_URL}/api/v1`
- `anthropic-proxy` gets `${LITELLM_BASE_URL}/anthropic/v1`

Do **not** include path suffixes in your `LITELLM_BASE_URL` `.env` value — the heredoc below adds them for you.

**Chrome flags explained**: The `--chromeArg` entries disable Chrome 115+'s automatic HTTP→HTTPS upgrading. Without these flags, Chrome silently redirects `http://` URLs to `https://`, which breaks demo environments that serve plain HTTP only. The three disabled features are:

| Feature Disabled | What It Would Do If Enabled |
| ---------------- | --------------------------- |
| `HttpsFirstBalancedModeAutoEnable` | Automatically enables HTTPS-First Mode on sites Chrome thinks support HTTPS |
| `HttpsUpgrades` | Silently rewrites `http://` navigations to `https://` before the request is sent |
| `HttpsFirstModeV2` | Shows a full-page interstitial warning when falling back to HTTP |

The remaining flags (`--no-first-run`, `--no-default-browser-check`, `--disable-extensions`, `--disable-background-timer-throttling`, `--disable-backgrounding-occluded-windows`) ensure a clean, automation-friendly Chrome session. No sandbox or GPU flags are needed on macOS — those are Linux container workarounds.

Write the file using a heredoc that substitutes the environment variables (note: **not** a quoted heredoc — the `$` variables are intentionally expanded):

```bash
cat > ~/.config/opencode/opencode.json << ENDOFJSON
{
  "\$schema": "https://opencode.ai/config.json",
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
        "baseURL": "${LITELLM_BASE_URL}/api/v1",
        "apiKey": "${LITELLM_API_KEY}"
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
        "baseURL": "${LITELLM_BASE_URL}/anthropic/v1",
        "apiKey": "${LITELLM_API_KEY}"
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
            "output": 128000
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
ENDOFJSON
```

Verify the file was written with actual values (not placeholder strings):

```bash
grep -c 'YOUR_' ~/.config/opencode/opencode.json
# VERIFY: output is 0 (no placeholder strings remain)
jq '.provider["openai-proxy"].options.baseURL' ~/.config/opencode/opencode.json
# VERIFY: output is your actual OpenAI proxy URL (not empty, not a placeholder)
```

---

## Step 10 — Write `oh-my-opencode.json`

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

## Step 11 — Write `AGENTS.md`

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

## Step 12 — Write `tui.json`

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

## Step 13 — Write `.gitignore`

If you plan to version-control your OpenCode config directory, this `.gitignore` prevents tracking generated files. Write the file `~/.config/opencode/.gitignore`:

```
node_modules
package.json
bun.lock
.gitignore
```

### 13.1 — Smoke-Test OpenCode Configuration

After writing all configuration files (Steps 9–13), verify that OpenCode can actually start and communicate with the AI provider.

**Why this step is critical**: A broken `opencode.json` (malformed JSON, wrong API key, unreachable base URL) would prevent OpenCode from launching. If you are an AI agent running inside OpenCode and you wrote a bad config, your next restart will fail — and there will be no running agent to fix it. This smoke test catches config errors **while you still have a working session** to correct them.

**Why this is safe**: `opencode run` with a one-shot prompt spawns a **separate process** that reads `~/.config/opencode/opencode.json`, sends one request to the AI provider, prints the response, and exits. It does **not** interfere with any already-running OpenCode session. Running from `/tmp` ensures no project files are touched. You **must** run this test — do not skip it.

**Strategy**: First validate that the JSON is syntactically correct, then run `opencode run` from `/tmp` with a trivial prompt and check for a non-empty response. If either check fails, stop and report the error — do not proceed to Step 14.

```bash
# Phase 1: Validate JSON syntax of all config files
echo "Validating config file syntax..."
for f in opencode.json oh-my-opencode.json tui.json; do
  if ! jq . "$HOME/.config/opencode/$f" > /dev/null 2>&1; then
    echo "ERROR: $f is not valid JSON. Fix the file and re-run this step."
    echo "  Hint: jq . ~/.config/opencode/$f"
    exit 1
  fi
  echo "  OK: $f"
done

# Phase 2: Live smoke test — launch a separate opencode process from /tmp
# This does NOT conflict with the current session. It spawns a one-shot
# process that reads the config, sends one request, and exits.
echo "Running OpenCode smoke test from /tmp..."
cd /tmp
SMOKE_OUT=$(mktemp)
opencode run "Reply with exactly one word: OPENCODE_OK" > "$SMOKE_OUT" 2>&1 &
OCPID=$!

# Wait up to 120 seconds (first run may download MCP servers)
ELAPSED=0
while kill -0 "$OCPID" 2>/dev/null; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [ "$ELAPSED" -ge 120 ]; then
    kill "$OCPID" 2>/dev/null
    wait "$OCPID" 2>/dev/null
    echo "ERROR: opencode run timed out after 120 seconds."
    echo "  This usually means the AI provider is unreachable."
    echo "  Check LITELLM_API_KEY and LITELLM_BASE_URL in .env"
    cat "$SMOKE_OUT"
    rm -f "$SMOKE_OUT"
    exit 1
  fi
done
wait "$OCPID"
OC_EXIT=$?

# Strip ANSI escape codes and check for non-empty response
CLEAN_OUT=$(sed 's/\x1b\[[0-9;]*m//g' "$SMOKE_OUT" | grep -v '^$' | grep -v '^>' | tail -1)

if [ "$OC_EXIT" -ne 0 ]; then
  echo "ERROR: opencode run exited with code $OC_EXIT"
  cat "$SMOKE_OUT"
  rm -f "$SMOKE_OUT"
  exit 1
elif [ -z "$CLEAN_OUT" ]; then
  echo "ERROR: opencode run produced no response"
  echo "  This may indicate an authentication or provider configuration issue."
  cat "$SMOKE_OUT"
  rm -f "$SMOKE_OUT"
  exit 1
else
  echo "Smoke test passed — OpenCode responded: $CLEAN_OUT"
fi
rm -f "$SMOKE_OUT"
cd - > /dev/null
```

VERIFY: output ends with `Smoke test passed — OpenCode responded: ...` followed by a non-empty AI response. If the smoke test fails, check:

1. **JSON syntax**: `jq . ~/.config/opencode/opencode.json` — any parse error means Step 9's heredoc expanded incorrectly (likely a special character in an API key or URL).
2. **API connectivity**: `curl -s -o /dev/null -w "%{http_code}" "${LITELLM_BASE_URL}/api/v1/models" -H "Authorization: Bearer ${LITELLM_API_KEY}"` — should return `200`.
3. **Plugin load failure**: `rm -rf ~/.cache/opencode/node_modules && opencode run "test"` — forces a clean plugin re-download.

---

## Step 14 — Configure `~/.zshrc` (Environment Variables and PATH)

Oh My Zsh (Step 5) created `~/.zshrc` with its own boilerplate. This step adds environment variables and PATH entries **after** the Oh My Zsh `source` line.

**Idempotency strategy**: Each block below uses `grep -q` to check if the line already exists before appending. This makes the step safe to re-run without creating duplicate entries.

**IMPORTANT**: The `LITELLM_API_KEY` line uses the `$LITELLM_API_KEY` environment variable sourced from `.env` in Step 8.4. That variable must still be set in the current shell session.

### 14.1 — Top of File: Powerlevel10k Instant Prompt

This block **must be the first thing** in `~/.zshrc` (before any other code that produces output). It enables sub-millisecond prompt rendering. Check if already present before adding:

```bash
if ! grep -q 'p10k-instant-prompt' ~/.zshrc; then
  # Prepend the p10k instant prompt block to the top of ~/.zshrc
  TMPFILE=$(mktemp)
  cat > "$TMPFILE" << 'INSTANT_PROMPT'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

INSTANT_PROMPT
  cat ~/.zshrc >> "$TMPFILE"
  mv "$TMPFILE" ~/.zshrc
fi
```

### 14.2 — Middle: Oh My Zsh Settings (already present)

The following lines were set in Step 5.5 via `sed` and should already be in `~/.zshrc`. Verify they are present:

```bash
grep '^ZSH_THEME="powerlevel10k/powerlevel10k"' ~/.zshrc   # VERIFY: line exists
grep '^plugins=(git z zsh-autosuggestions' ~/.zshrc          # VERIFY: line exists
```

### 14.3 — After `source $ZSH/oh-my-zsh.sh`: User Configuration

Append each line only if it is not already present. Each `grep -q` guard prevents duplicates on re-runs:

```bash
# Homebrew (Apple Silicon)
grep -q 'brew shellenv' ~/.zshrc || \
  echo 'eval $(/opt/homebrew/bin/brew shellenv)' >> ~/.zshrc

# Powerlevel10k config (written by `p10k configure` wizard)
grep -q 'p10k.zsh' ~/.zshrc || \
  echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc

# Bun
grep -q 'BUN_INSTALL' ~/.zshrc || \
  echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.zshrc
grep -q 'BUN_INSTALL/bin' ~/.zshrc || \
  echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.zshrc

# Bun completions
grep -q '_bun' ~/.zshrc || \
  echo '[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"' >> ~/.zshrc

# User-local binaries (docker shim, etc.)
grep -q '\.local/bin' ~/.zshrc || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# iTerm2 utilities (imgcat, imgls, it2api, etc.)
grep -q 'iTerm.app' ~/.zshrc || \
  echo 'export PATH="/Applications/iTerm.app/Contents/Resources/utilities:$PATH"' >> ~/.zshrc

# API key for AI proxy (sourced from .env in Step 8.4)
grep -q 'LITELLM_API_KEY' ~/.zshrc || \
  echo "export LITELLM_API_KEY=\"${LITELLM_API_KEY}\"" >> ~/.zshrc

```

### Activate Environment for Current Session

Do **not** run `source ~/.zshrc` — it will fail in a non-interactive shell context (Oh My Zsh and Powerlevel10k require a TTY). Instead, export the critical variables for the current session:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$HOME/.local/bin:/Applications/iTerm.app/Contents/Resources/utilities:$PATH"
eval $(/opt/homebrew/bin/brew shellenv)
```

---

## Step 15 — Install Project Tooling (Containers, Git Hooks, Docker Shim)

These tools support the standard development workflow across all repositories: container-based linting via pre-commit hooks, OCI container builds, and compatibility with tools that expect a `docker` CLI.

### 15.1 — Ensure Podman is Running

The corporate standard container runtime is **Podman**. Docker Desktop is not permitted. Podman runs containers in a lightweight user-space VM with no root privileges required.

The following script is idempotent — it handles all three states (machine running, machine stopped, no machine):

```bash
podman --version  # VERIFY: output contains "podman version 5"

# Idempotent Podman machine setup: init if missing, start if stopped, skip if running
if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
  echo "Podman machine is already running"
elif podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
  podman machine start
else
  podman machine init --memory 10240
  podman machine start
fi

podman machine list  # VERIFY: output shows "Currently running"
```

### 15.2 — Create a Podman-to-Docker Compatibility Shim

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
~/.local/bin/docker --version   # VERIFY: output contains "podman version 5"
docker --version                 # VERIFY: output contains "podman" (requires ~/.local/bin in PATH from Step 14)
```

### 15.3 — Verify pre-commit

pre-commit was installed in Step 1 via Homebrew. Verify it is available:

```bash
pre-commit --version   # VERIFY: output contains "pre-commit 4" or higher
```

To activate pre-commit hooks in any repository that uses `.pre-commit-config.yaml`:

```bash
cd <repository-root>
pre-commit install
```

---

## Step 16 — Verify the Complete Installation

Run each of these commands to confirm everything is in place.

### 16.1 — Core Tools

```bash
opencode --version          # VERIFY: output starts with 1.2 (1.2.20+)
node --version              # VERIFY: output starts with v25 (v25.x+)
bun --version               # VERIFY: output starts with 1 (1.3.x+)
npm --version               # VERIFY: output starts with 11 (11.x+)
rg --version                # VERIFY: contains "ripgrep"
gh --version                # VERIFY: 2.x+
tmux -V                     # VERIFY: tmux 3.x+
jq --version                # VERIFY: jq-1.x+
```

### 16.2 — LSP Servers on PATH

```bash
which bash-language-server   # VERIFY: prints a path (typically /opt/homebrew/bin/...)
which yaml-language-server   # VERIFY: prints a path
which marksman               # VERIFY: prints a path
which terraform-ls           # VERIFY: prints a path
which shellcheck             # VERIFY: prints a path
which shfmt                  # VERIFY: prints a path
```

### 16.3 — npm Global LSP Packages

```bash
npm list -g --depth=0 2>/dev/null | grep -E "(vscode-langservers|bash-language|yaml-language|mdx-js|taplo)"
```

VERIFY: all five packages appear in the output (exact versions may vary).

### 16.4 — Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

VERIFY: output contains `Google Chrome` followed by a version number.

### 16.5 — chrome-devtools-mcp

```bash
npx -y chrome-devtools-mcp@latest --help
```

Expected: prints the CLI help with options like `--executablePath`, `--headless`, etc.

### 16.6 — OpenCode Config Files

```bash
ls -la ~/.config/opencode/opencode.json
ls -la ~/.config/opencode/oh-my-opencode.json
ls -la ~/.config/opencode/AGENTS.md
ls -la ~/.config/opencode/tui.json
ls -la ~/.config/opencode/package.json
ls -la ~/.config/opencode/node_modules/@opencode-ai/plugin/
```

All files should exist and be owned by the current user.

### 16.7 — OpenCode Runtime Cache

```bash
ls ~/.cache/opencode/node_modules/@robinmordasiewicz/oh-my-opencode/package.json  # Expected: file exists
ls ~/.cache/opencode/node_modules/@ai-sdk/anthropic/package.json                  # Expected: file exists
ls ~/.cache/opencode/node_modules/@ai-sdk/openai-compatible/package.json          # Expected: file exists
ls ~/.cache/opencode/node_modules/opencode-anthropic-auth/package.json            # Expected: file exists
```

All four runtime packages should be pre-installed. If any are missing, re-run `(cd ~/.cache/opencode && bun install)`.

### 16.8 — Environment Variables

```bash
echo $BUN_INSTALL            # VERIFY: output is /Users/<username>/.bun (not empty)
echo $LITELLM_API_KEY        # VERIFY: output is your API key (not empty, not a placeholder)
```

### 16.9 — Claude Code Plugins

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

### 16.10 — Project Tooling (Podman, Docker Shim, pre-commit)

```bash
podman --version                # VERIFY: output contains "podman version 5"
podman machine list             # VERIFY: output shows "Currently running"
~/.local/bin/docker --version   # VERIFY: output contains "podman version 5" (via shim)
which docker                    # VERIFY: output is ~/.local/bin/docker
pre-commit --version            # VERIFY: output contains "pre-commit 4"
```

### 16.11 — Terminal Environment (iTerm2, Oh My Zsh, Theme, Plugins)

```bash
ls "/Applications/iTerm.app"                                                    # VERIFY: directory exists
which imgcat                                                                     # VERIFY: prints a path containing iTerm.app
ls ~/.oh-my-zsh/oh-my-zsh.sh                                                    # VERIFY: file exists
test -f ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme && echo "OK" # VERIFY: file exists
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh # VERIFY: file exists
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting                           # VERIFY: directory exists
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                                    # VERIFY: file exists (p10k font)
grep "^ZSH_THEME" ~/.zshrc                                                      # VERIFY: output contains "powerlevel10k"
grep "^plugins=" ~/.zshrc                                                        # VERIFY: output contains "zsh-autosuggestions zsh-syntax-highlighting"
```

### 16.12 — Verify .env File

```bash
REPO_DIR="$(pwd)"
test -f "${REPO_DIR}/.env" && echo "OK: .env exists" || echo "MISSING: .env"
grep -q '^LITELLM_API_KEY=' "${REPO_DIR}/.env" && echo "OK: LITELLM_API_KEY" || echo "MISSING: LITELLM_API_KEY"
grep -q '^LITELLM_BASE_URL=' "${REPO_DIR}/.env" && echo "OK: LITELLM_BASE_URL" || echo "MISSING: LITELLM_BASE_URL"
grep -q '^TZ=' "${REPO_DIR}/.env" && echo "OK: TZ" || echo "MISSING: TZ"
grep -q '^GIT_AUTHOR_EMAIL=' "${REPO_DIR}/.env" && echo "OK: GIT_AUTHOR_EMAIL" || echo "MISSING: GIT_AUTHOR_EMAIL"
grep -q '^GIT_AUTHOR_NAME=' "${REPO_DIR}/.env" && echo "OK: GIT_AUTHOR_NAME" || echo "MISSING: GIT_AUTHOR_NAME"
```

VERIFY: All lines print "OK". Any "MISSING" line means Step 8 did not complete successfully.

### 16.13 — Verify File Manifest

Confirm that all expected directories and files were created:

```bash
# ~/.config/opencode/ structure
test -f ~/.config/opencode/opencode.json        && echo "OK: opencode.json"        || echo "MISSING: opencode.json"
test -f ~/.config/opencode/oh-my-opencode.json  && echo "OK: oh-my-opencode.json"  || echo "MISSING: oh-my-opencode.json"
test -f ~/.config/opencode/AGENTS.md            && echo "OK: AGENTS.md"            || echo "MISSING: AGENTS.md"
test -f ~/.config/opencode/tui.json             && echo "OK: tui.json"             || echo "MISSING: tui.json"
test -f ~/.config/opencode/package.json         && echo "OK: package.json"         || echo "MISSING: package.json"
test -d ~/.config/opencode/node_modules         && echo "OK: node_modules/"        || echo "MISSING: node_modules/"

# ~/.claude/ structure
test -f ~/.claude/settings.json                         && echo "OK: settings.json"            || echo "MISSING: settings.json"
test -f ~/.claude/plugins/installed_plugins.json         && echo "OK: installed_plugins.json"   || echo "MISSING: installed_plugins.json"
test -f ~/.claude/plugins/known_marketplaces.json        && echo "OK: known_marketplaces.json"  || echo "MISSING: known_marketplaces.json"
test -f ~/.claude/plugins/blocklist.json                 && echo "OK: blocklist.json"           || echo "MISSING: blocklist.json"
test -d ~/.claude/plugins/cache/claude-plugins-official  && echo "OK: plugin cache/"            || echo "MISSING: plugin cache/"

# ~/.cache/opencode/ runtime
test -d ~/.cache/opencode/node_modules  && echo "OK: runtime cache/"  || echo "MISSING: runtime cache/"

# ~/.local/bin/ shim
test -x ~/.local/bin/docker  && echo "OK: docker shim"  || echo "MISSING: docker shim"
```

VERIFY: All lines print "OK". Any "MISSING" line indicates a failed step — go back and re-run the corresponding step.

### 16.14 — Launch OpenCode

```bash
opencode
```

OpenCode should start without errors. The Oh-My-OpenCode plugin should load automatically (you will see the Sisyphus agent and multi-agent orchestration capabilities).

### 16.15 — Verify Podman and Print Next Steps

Confirm that Podman and podman-compose are installed and the Podman machine is running, then print instructions for launching the devcontainer.

```bash
echo ""
echo "=== Final Podman Verification ==="

# Verify Podman is installed
if ! command -v podman &>/dev/null; then
  echo "ERROR: podman is not installed. Re-run Step 1."
  exit 1
fi
echo "OK: $(podman --version)"

# Verify podman-compose is installed
if ! command -v podman-compose &>/dev/null; then
  echo "ERROR: podman-compose is not installed. Re-run Step 1."
  exit 1
fi
echo "OK: podman-compose is installed"

# Verify Podman machine is running
if ! podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
  echo "ERROR: Podman machine is not running. Re-run Step 15.1."
  exit 1
fi
echo "OK: Podman machine is running"

# Smoke test: verify podman can pull and run a container
if podman run --rm docker.io/library/alpine:latest echo "PODMAN_OK" 2>/dev/null | grep -q "PODMAN_OK"; then
  echo "OK: Podman smoke test passed"
else
  echo "ERROR: Podman cannot run containers. Check: podman machine list"
  exit 1
fi

CURRENT_DIR="$(pwd)"

# Check Powerlevel10k configuration status
P10K_STATUS=""
if [ ! -f "$HOME/.p10k.zsh" ]; then
  P10K_STATUS="unconfigured"
fi

echo ""
echo "==========================================================="
echo "  Setup complete! All tools installed and verified."
echo "==========================================================="
echo ""
if [ "$P10K_STATUS" = "unconfigured" ]; then
  echo "  ⚠  Powerlevel10k is installed but not yet configured."
  echo "     Open iTerm2 and run:"
  echo ""
  echo "       p10k configure"
  echo ""
  echo "     This launches an interactive wizard that sets your"
  echo "     prompt style and writes ~/.p10k.zsh."
  echo ""
fi
echo "  To launch the devcontainer, open a NEW terminal window"
echo "  and run:"
echo ""
echo "    cd ${CURRENT_DIR}"
echo "    podman-compose down && podman-compose pull && podman-compose up -d && \\"
echo "      podman run --rm -it --env-file .env ghcr.io/f5xc-salesdemos/devcontainer:latest zsh"
echo ""
echo "  What this does:"
echo "    1. podman-compose down    — stops any existing devcontainer"
echo "    2. podman-compose pull    — pulls the latest container image"
echo "    3. podman-compose up -d   — starts the compose services in the background"
echo "    4. podman run ... zsh     — opens an interactive Zsh session in a fresh"
echo "                                container, loading your .env variables"
echo "                                (API keys, Git identity, timezone, etc.)"
echo ""
echo "==========================================================="
```

---

## Troubleshooting

### Homebrew install fails with "is not a directory"

**Symptom**: `brew install <pkg>` fails with:

```
Error: /opt/homebrew/Cellar/<pkg>/<version> is not a directory
```

**Cause**: A previous version's Cellar directory survived an upgrade or partial uninstall. Homebrew refuses to pour a new bottle version when an old version directory already exists. This is commonly seen with `trivy` but can affect any package. Running `brew uninstall --force` does not always remove the stale directory.

**Fix**:

```bash
# Remove the entire Cellar entry for the package
rm -rf /opt/homebrew/Cellar/<pkg>

# Re-install
brew install <pkg>

# If install still fails (stale directory reappears), link whatever is present
brew link --overwrite <pkg>
```

The `brew_install` helper function in Step 1 performs this recovery automatically.

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

If missing, re-run: `curl -fsSL https://bun.sh/install | bash` and then `export PATH="$HOME/.bun/bin:$PATH"`.

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

macOS caches DNS failures (`NXDOMAIN`) in the `mDNSResponder` system daemon. If Chrome
(or any application using the system resolver) queries a domain **before** its DNS record
exists, the negative result is cached for up to 30 minutes (determined by the SOA minimum
TTL). Subsequent lookups — including from a freshly launched Chrome — return the cached
failure even after the real DNS record is created.

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

### Reset to Clean State

If the installation is in a broken state and you need to start over, remove all generated files and directories. Homebrew packages are left in place (they are managed separately).

```bash
# Remove OpenCode config and cache
rm -rf ~/.config/opencode/node_modules ~/.config/opencode/bun.lock
rm -rf ~/.cache/opencode/node_modules ~/.cache/opencode/bun.lock

# Remove Claude Code plugins
rm -rf ~/.claude/plugins ~/.claude/settings.json

# Remove Oh My Zsh (will also remove custom plugins and themes)
rm -rf ~/.oh-my-zsh

# Remove Podman-to-Docker shim
rm -f ~/.local/bin/docker

# Remove npx cache
rm -rf ~/.npm/_npx

# Remove chrome-devtools-mcp profile
rm -rf ~/.cache/chrome-devtools-mcp
```

After cleanup, re-run this document from Step 3 onward (Homebrew packages from Steps 1-2 persist and do not need re-installation).

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

~/.cache/opencode/             # Runtime dependencies and auto-installed LSP servers
├── package.json               # Runtime dependency manifest (4 packages)
├── bun.lock                   # Bun lockfile (auto-generated)
└── node_modules/              # Pre-cached runtime packages
    ├── @robinmordasiewicz/
    │   └── oh-my-opencode/    # Oh-My-OpenCode plugin
    ├── @ai-sdk/
    │   ├── anthropic/         # Vercel AI SDK — Anthropic provider
    │   └── openai-compatible/ # Vercel AI SDK — OpenAI-compatible provider
    └── opencode-anthropic-auth/ # Anthropic auth module
~/.cache/chrome-devtools-mcp/  # Chrome browser profile for MCP
~/.npm/_npx/                   # npx cache for chrome-devtools-mcp
~/.local/share/containers/     # Podman machine storage
```
