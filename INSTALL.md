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

**Why this is necessary**: OpenCode's default permission policy is `"ask"` — the agent must
request user confirmation before reading or writing files outside the project directory,
running shell commands, or accessing external paths like `~/.config`, `~/.claude`,
`/opt/homebrew`, etc. In interactive mode (the TUI), this works fine — the user clicks
"allow". But `opencode run` is **non-interactive**: there is no UI to approve permission
requests, so the agent fails immediately.

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

**Known issue — stale Cellar directories**: Some packages (notably `trivy`) can leave behind
a Cellar directory from a previous version after an upgrade or partial uninstall. When
Homebrew tries to pour a newer bottle, it fails with
`Error: /opt/homebrew/Cellar/<pkg>/<version> is not a directory` because a directory for a
*different* version already exists. The workaround is to remove the stale Cellar entry and
re-link. A helper function below handles this automatically for all packages.

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
brew install --cask google-cloud-sdk  # Google Cloud CLI (gcloud, gsutil, bq)
brew_install gogcli            # Google Suite CLI — Gmail, Calendar, Drive, Contacts, Tasks, Sheets (gog)
brew_install signal-cli        # Signal Instant Messenger

# Terraform ecosystem
brew_install tflint            # Terraform linter (catches errors before plan)
brew_install terraform-docs    # Auto-generate Terraform module documentation

# Linting and security scanning
brew_install hadolint          # Dockerfile linter (best practices enforcement)
brew_install gitleaks          # Secret scanner (catches leaked credentials pre-commit)
brew_install trivy             # Vulnerability scanner for containers and code
brew_install sslscan           # TLS/SSL configuration scanner
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
gcloud --version       # VERIFY: output contains "Google Cloud SDK"
gog --version          # VERIFY: output contains a version number (gogcli)
tflint --version       # VERIFY: output starts with "TFLint version"
terraform-docs --version # VERIFY: output contains a version number
hadolint --version     # VERIFY: output contains "Haskell Dockerfile Linter"
gitleaks version       # VERIFY: output contains a version number
trivy --version        # VERIFY: output starts with "Version:"
sslscan --version      # VERIFY: output contains "sslscan version"
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

# Google Workspace CLI (mirrors devcontainer toolset)
npm install -g @googleworkspace/cli           # Google Workspace admin CLI (gws)

# TypeScript native compiler (tsgo — 10x faster type checking)
npm install -g @typescript/native-preview     # Provides tsgo binary (TypeScript 7 Go port)

# Code formatters (mirrors devcontainer toolset)
npm install -g prettier                       # Multi-language code formatter
npm install -g @biomejs/biome                 # Fast JS/TS/JSON linter and formatter

# Presentation and React tools
npm install -g pptxgenjs                      # PowerPoint generation
npm install -g react-icons                     # Icon library for React
npm install -g react                          # React core
npm install -g react-dom                      # React DOM
npm install -g sharp                          # Image processing
npm install -g markitdown                     # Markdown processing
```

### Verify npm Global Packages

```bash
npm list -g --depth=0 2>/dev/null | grep -E "(vscode-langservers|bash-language|yaml-language|mdx-js|taplo|prettier|biome|googleworkspace|native-preview)"
```

VERIFY: All nine packages appear in the output (exact versions may differ):

- `@biomejs/biome`
- `@googleworkspace/cli`
- `@mdx-js/language-server`
- `@taplo/cli`
- `@typescript/native-preview`
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

## Step 4b — Install OpenCode Desktop

OpenCode Desktop is the GUI companion for OpenCode. Install via Homebrew Cask:

```bash
brew install --cask opencode-desktop
```

---

## Step 4c — Configure macOS System Defaults

Configure macOS for developer workflows and long-running AI assistant tasks. These settings prevent sleep interruptions, speed up keyboard input, disable code-breaking text substitutions, and optimize the Finder and Dock for productivity.

All commands are idempotent — `defaults write` overwrites existing values. Safe to re-run.

### 4c.1 — Power and Sleep (prevents AI job interruptions)

> **MANUAL STEP**: Power management requires `sudo` which this guide does not use. Configure these settings through the GUI:
>
> 1. Open **System Settings** > **Battery** > **Options**
> 2. Enable **"Prevent automatic sleeping on power adapter when the display is off"**
> 3. Optionally set **"Turn display off on power adapter"** to **Never**
>
> This ensures long-running AI sessions, builds, and background tasks are never interrupted by sleep.

### 4c.2 — Dock

```bash
echo "Configuring Dock..."

# Auto-hide the Dock (reclaim screen space)
defaults write com.apple.dock autohide -bool true

# Remove the show/hide delay (instant reveal on hover)
defaults write com.apple.dock autohide-delay -float 0

# Speed up the show/hide animation
defaults write com.apple.dock autohide-time-modifier -float 0.25

# Smaller icons (45px instead of default 64px)
defaults write com.apple.dock tilesize -int 45

# Scale animation for minimize (faster than genie)
defaults write com.apple.dock mineffect -string "scale"

# Don't show recent apps in the Dock
defaults write com.apple.dock show-recents -bool false

# Apply Dock changes
killall Dock
echo "Dock configured and restarted."
```

### 4c.3 — Finder

```bash
echo "Configuring Finder..."

# Show all file extensions (.txt, .json, .md, etc.)
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files (dotfiles: .gitignore, .env, etc.)
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show path bar at bottom of Finder windows
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar (item count and free space)
defaults write com.apple.finder ShowStatusBar -bool true

# Default to list view (alternatives: icnv, clsv, Flwv)
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Search the current folder by default (not "This Mac")
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Show full POSIX path in Finder title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Apply Finder changes
killall Finder
echo "Finder configured and restarted."
```

### 4c.4 — Keyboard

These settings are critical for developers — smart quotes and dashes silently corrupt code when pasting, and slow key repeat wastes time navigating.

```bash
echo "Configuring keyboard..."

# Fast key repeat (1 = fastest; default is 2)
defaults write -g KeyRepeat -int 1

# Short delay before repeat starts (10 ≈ 80ms; default is 15)
defaults write -g InitialKeyRepeat -int 10

# Disable auto-correct (changes your typos to wrong words)
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable smart quotes ("curly quotes" break code)
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Disable smart dashes (hyphens become em-dashes)
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable period substitution (double-space inserts period)
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Enable full keyboard access for all UI controls (Tab navigates buttons, not just text fields)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Key repeat instead of press-and-hold accent menu (essential for vim/terminal)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

echo "Keyboard configured."
```

### 4c.5 — Trackpad

```bash
echo "Configuring trackpad..."

# Enable tap to click (tap instead of physical press)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Fast tracking speed (range: 0.0 slow to 3.0 fast; default ~1.0)
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.5

echo "Trackpad configured."
```

### 4c.6 — Screenshots

```bash
echo "Configuring screenshots..."

# Save screenshots to ~/Screenshots (not Desktop)
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots

# PNG format (lossless)
defaults write com.apple.screencapture type -string "png"

echo "Screenshots will save to ~/Screenshots as PNG."
```

### 4c.7 — Miscellaneous

```bash
echo "Configuring miscellaneous settings..."

# Prevent .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Prevent .DS_Store files on USB/external drives
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Expand save and print dialogs by default (show all options)
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

echo "Miscellaneous settings configured."
```

### Verify macOS Defaults

```bash
echo "=== Power (manual check) ==="
pmset -g | grep -E "^\s*(sleep|displaysleep)"          # Expected: sleep 0, displaysleep 0 (set via System Settings)

echo "=== Dock ==="
defaults read com.apple.dock autohide                   # Expected: 1
defaults read com.apple.dock autohide-delay             # Expected: 0
defaults read com.apple.dock show-recents               # Expected: 0

echo "=== Finder ==="
defaults read NSGlobalDomain AppleShowAllExtensions     # Expected: 1
defaults read com.apple.finder AppleShowAllFiles        # Expected: 1
defaults read com.apple.finder ShowPathbar              # Expected: 1

echo "=== Keyboard ==="
defaults read -g KeyRepeat                              # Expected: 1
defaults read -g InitialKeyRepeat                       # Expected: 10
defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled  # Expected: 0
defaults read NSGlobalDomain ApplePressAndHoldEnabled    # Expected: 0

echo "=== Screenshots ==="
defaults read com.apple.screencapture location           # Expected: ~/Screenshots

echo "=== Misc ==="
defaults read com.apple.desktopservices DSDontWriteNetworkStores  # Expected: 1
```

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

**Race condition with a running iTerm2**: A running iTerm2 instance holds preferences in
memory and writes them to the plist when it quits — overwriting any external changes. The
script below handles this by gracefully quitting iTerm2 first (if running), waiting for it
to fully exit, and then modifying the plist on disk. The user can relaunch iTerm2 afterward
and the font will be active immediately.

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

### 5.3a — Configure iTerm2 Developer Settings

Configure sensible defaults for developer workflows. These settings are stored in the same plist modified by Step 5.3 and use the same PlistBuddy approach for profile-specific keys. The global appearance theme uses `defaults write` since it is an application-level (not profile-level) setting.

**Prerequisites**: Step 5.3 must have run first — that step handles launching iTerm2 to generate the plist if needed, and quitting a running instance to avoid the in-memory overwrite race condition.

| Setting | Key | Value | Why |
| ------- | --- | ----- | --- |
| Silence bell | `Silence Bell` | `true` | Stops the audible beep on tab completion miss, Ctrl+G, etc. |
| Disable visual bell | `Visual Bell` | `false` | Screen flash is distracting; silence is enough |
| Unlimited scrollback | `Unlimited Scrollback` | `true` | Never lose build output or long log tails |
| Left Option as Esc+ | `Option Key Sends` | `2` | Enables Alt+B / Alt+F word navigation in the shell |
| Right Option as Esc+ | `Right Option Key Sends` | `2` | Same for the right Option key |
| Force dark theme | `TabStyleWithAutomaticOption` | `1` | Terminal stays dark regardless of macOS system appearance |

**Option Key Sends values**: 0 = Normal, 1 = Meta, 2 = Esc+

**TabStyleWithAutomaticOption values**: 0 = Light, 1 = Dark, 2 = Light High Contrast, 3 = Dark High Contrast, 4 = Automatic (follows system), 5 = Minimal

```bash
PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

if [ -f "$PLIST" ]; then
  echo "Configuring iTerm2 developer settings..."

  # --- Profile settings (New Bookmarks → default profile) ---
  # Helper: idempotently set a key in the default profile.
  # Falls back to Add if the key does not exist yet (fresh plist).
  plist_profile_set() {
    local key="$1" type="$2" val="$3"
    local current
    current="$(/usr/libexec/PlistBuddy -c "Print :\"New Bookmarks\":0:\"$key\"" "$PLIST" 2>/dev/null)"
    if [ "$current" = "$val" ]; then
      echo "  Kept:    $key (already $val)"
    else
      /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"$key\" $val" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":0:\"$key\" $type $val" "$PLIST"
      echo "  Updated: $key → $val"
    fi
  }

  # Silence bell (no audible beep)
  plist_profile_set "Silence Bell" bool true

  # Disable visual bell flash
  plist_profile_set "Visual Bell" bool false

  # Unlimited scrollback buffer
  plist_profile_set "Unlimited Scrollback" bool true

  # Option keys send Esc+ (enables Alt+B, Alt+F word navigation)
  plist_profile_set "Option Key Sends" integer 2
  plist_profile_set "Right Option Key Sends" integer 2

  # --- Global settings (application-level) ---
  # Force dark theme (don't follow system appearance)
  # Values: 0=Light, 1=Dark, 2=Light HC, 3=Dark HC, 4=Automatic, 5=Minimal
  CURRENT_THEME="$(defaults read com.googlecode.iterm2 TabStyleWithAutomaticOption 2>/dev/null)"
  if [ "$CURRENT_THEME" = "1" ]; then
    echo "  Kept:    Theme (already Dark)"
  else
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 1
    echo "  Updated: Theme → Dark"
  fi

  echo "iTerm2 developer settings configured."
else
  echo "iTerm2 plist not found — skipping settings (run Step 5.3 first)"
fi
```

### 5.4 — Install Zsh Plugins

Clone third-party plugins into Oh My Zsh's custom plugins directory. These mirror the plugins installed in the devcontainer Dockerfile.

**IMPORTANT**: `git clone` fails with exit code 128 if the target directory already exists. Always guard with an existence check:

```bash
[ -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
    ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

[ -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
    ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

[ -d ~/.oh-my-zsh/custom/plugins/zsh-claudecode-completion ] || \
  git clone --depth=1 https://github.com/wbingli/zsh-claudecode-completion.git \
    ~/.oh-my-zsh/custom/plugins/zsh-claudecode-completion

[ -d ~/.oh-my-zsh/custom/plugins/conda-zsh-completion ] || \
  git clone --depth=1 https://github.com/conda-incubator/conda-zsh-completion.git \
    ~/.oh-my-zsh/custom/plugins/conda-zsh-completion

[ -d ~/.oh-my-zsh/custom/plugins/zsh-eza ] || \
  git clone --depth=1 https://github.com/z-shell/zsh-eza.git \
    ~/.oh-my-zsh/custom/plugins/zsh-eza

[ -d ~/.oh-my-zsh/custom/plugins/zsh-tfenv ] || \
  git clone --depth=1 https://github.com/cda0/zsh-tfenv.git \
    ~/.oh-my-zsh/custom/plugins/zsh-tfenv

[ -d ~/.oh-my-zsh/custom/plugins/zsh-aliases-lsd ] || \
  git clone --depth=1 https://github.com/yuhonas/zsh-aliases-lsd.git \
    ~/.oh-my-zsh/custom/plugins/zsh-aliases-lsd
```

Copy the custom `gh-clone-complete` plugin from this repo:

```bash
mkdir -p ~/.oh-my-zsh/custom/plugins/gh-clone-complete
cp configs/gh-clone-complete.plugin.zsh \
  ~/.oh-my-zsh/custom/plugins/gh-clone-complete/gh-clone-complete.plugin.zsh
```

### 5.5 — Configure `~/.zshrc` for Oh My Zsh

The Oh My Zsh installer creates a `~/.zshrc` with defaults. Two settings must be changed using `sed`. These commands are idempotent — they replace existing lines by pattern match, so running them twice produces the same result.

**Theme** — replace the default `ZSH_THEME="robbyrussell"` line:

```bash
sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
```

**Plugins** — replace the default `plugins=(git)` line with the full plugin set matching the devcontainer:

```bash
sed -i '' 's/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd jsontools gh gh-clone-complete common-aliases zsh-aliases-lsd zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl iterm2 kube-ps1 kubectl sudo vscode aws fzf docker history colored-man-pages command-not-found tmux zsh-claudecode-completion)/' ~/.zshrc
```

VERIFY both changes applied:

```bash
grep '^ZSH_THEME=' ~/.zshrc    # VERIFY: output is ZSH_THEME="powerlevel10k/powerlevel10k"
grep '^plugins=' ~/.zshrc       # VERIFY: output includes zsh-claudecode-completion
```

| Plugin | Source | What It Does |
| ------ | ------ | ------------ |
| `zsh-syntax-highlighting` | Custom clone | Real-time color coding of commands as you type |
| `zsh-autosuggestions` | Custom clone | Fish-like inline suggestions from command history (accept with →) |
| `zsh-interactive-cd` | OMZ built-in | Interactive directory selection with fzf |
| `jsontools` | OMZ built-in | JSON pretty-printing and manipulation (`pp_json`, `is_json`) |
| `gh` | OMZ built-in | GitHub CLI completions |
| `gh-clone-complete` | Custom (configs/) | Tab completion for GitHub repo names during `gh repo clone` |
| `common-aliases` | OMZ built-in | Useful shell aliases (`ll`, `la`, `..`, etc.) |
| `zsh-aliases-lsd` | Custom clone | Aliases that use `lsd` as a modern `ls` replacement |
| `zsh-tfenv` | Custom clone | Terraform version manager completions |
| `conda-zsh-completion` | Custom clone | Conda environment and package completions |
| `z` | OMZ built-in | Frecency-based directory jumping (`z project`) |
| `pip` | OMZ built-in | Python pip completions |
| `terraform` | OMZ built-in | Terraform completions and aliases |
| `fluxcd` | OMZ built-in | FluxCD completions |
| `azure` | OMZ built-in | Azure CLI completions |
| `git-auto-fetch` | OMZ built-in | Auto-fetches git remotes in background |
| `helm` | OMZ built-in | Helm completions |
| `istioctl` | OMZ built-in | Istio CLI completions |
| `iterm2` | OMZ built-in | iTerm2 shell integration |
| `kube-ps1` | OMZ built-in | Kubernetes context/namespace in prompt |
| `kubectl` | OMZ built-in | kubectl completions and aliases |
| `sudo` | OMZ built-in | Press Escape twice to prepend `sudo` to current command |
| `vscode` | OMZ built-in | VS Code aliases (`code .`, etc.) |
| `aws` | OMZ built-in | AWS CLI completions |
| `fzf` | OMZ built-in | Fuzzy finder integration (Ctrl+R history, Ctrl+T files) |
| `docker` | OMZ built-in | Docker completions |
| `history` | OMZ built-in | History search aliases (`h`, `hs`) |
| `colored-man-pages` | OMZ built-in | Colorized man pages |
| `command-not-found` | OMZ built-in | Suggests packages when a command is not found |
| `tmux` | OMZ built-in | Tmux aliases and completions |
| `zsh-claudecode-completion` | Custom clone | Tab completions for Claude Code CLI |
| `zsh-eza` | Custom clone | Enhanced `ls` using `eza` with icons and git status |

**Note**: The devcontainer also includes the `ubuntu` plugin which is Linux-only and not applicable to macOS.

### 5.6 — Install Powerlevel10k Configuration

Copy the pre-built Powerlevel10k configuration from this repo. This is the same config installed in the devcontainer (rainbow theme, 2-line prompt, Nerdfont icons, transient prompt):

```bash
cp configs/.p10k.zsh ~/.p10k.zsh
```

To customize the prompt style later, run `p10k configure` in iTerm2.

### 5.7 — Install Dotfiles

Copy shell environment dotfiles from this repo to match the devcontainer setup:

```bash
cp configs/.tmux.conf ~/.tmux.conf

# Install Tmux Plugin Manager (tpm) — required by .tmux.conf
[ -d ~/.tmux/plugins/tpm ] || \
  git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
cp configs/.digrc ~/.digrc
cp configs/.inputrc ~/.inputrc
cp configs/.nanorc ~/.nanorc
cp configs/.lessfilter ~/.lessfilter
chmod +x ~/.lessfilter
touch ~/.hushlogin
```

| File | Purpose |
| ---- | ------- |
| `.tmux.conf` | Tmux terminal multiplexer — true color, extended keys, Vi bindings |
| `.digrc` | Cleaner `dig` output (`+nostats +nocomments +nocmd`) |
| `.inputrc` | Readline — case-insensitive tab completion, history substring search |
| `.lessfilter` | Syntax highlighting when viewing files with `less` |
| `.nanorc` | Nano editor defaults |
| `.hushlogin` | Suppress the "Last login" banner on new terminal sessions |

### Verify Terminal Environment

```bash
ls "/Applications/iTerm.app/Contents/Resources/utilities/imgcat"       # Expected: file exists
ls ~/.oh-my-zsh/oh-my-zsh.sh                                          # Expected: file exists
test -f ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme && echo "OK"  # Expected: file exists
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions                     # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting                 # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-claudecode-completion               # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/conda-zsh-completion                    # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-eza                                 # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-tfenv                               # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/zsh-aliases-lsd                         # Expected: directory exists
ls ~/.oh-my-zsh/custom/plugins/gh-clone-complete                       # Expected: directory exists
test -f ~/.p10k.zsh && echo "OK: p10k config"                         # Expected: OK
test -f ~/.tmux.conf && echo "OK: tmux config"                        # Expected: OK
test -f ~/.digrc && echo "OK: digrc"                                  # Expected: OK
test -f ~/.inputrc && echo "OK: inputrc"                              # Expected: OK
test -x ~/.lessfilter && echo "OK: lessfilter (executable)"           # Expected: OK
test -f ~/.nanorc && echo "OK: nanorc"                                # Expected: OK
test -f ~/.hushlogin && echo "OK: hushlogin"                          # Expected: OK
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                          # Expected: file exists (p10k font)
ls ~/Library/Fonts/MesloLGSNerdFont-Regular.ttf 2>/dev/null \
  || ls ~/Library/Fonts/MesloLGLNerdFont-Regular.ttf                   # Expected: Nerd Font installed
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Normal Font"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: MesloLGS-NF-Regular 13
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Silence Bell"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: true
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Visual Bell"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: false
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Unlimited Scrollback"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: true
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Option Key Sends"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                    # Expected: 2
defaults read com.googlecode.iterm2 TabStyleWithAutomaticOption        # Expected: 1 (Dark)
```

---

### 5.8 — Install Claude Code (Native Binary)

Claude Code is installed as a native binary (not via npm). The native installer is idempotent — re-running it updates to the latest version. Claude Code requires an Anthropic Pro, Max, Teams, or Enterprise account.

```bash
if command -v claude >/dev/null 2>&1; then
  echo "Claude Code already installed: $(claude --version 2>/dev/null)"
else
  echo "Installing Claude Code native binary..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Verify
claude --version
# Expected: output contains "Claude Code" followed by a version number
```

After installation, the binary lives at `~/.local/bin/claude`. First-time users should run `claude` interactively to complete the browser-based OAuth login. The `~/.claude/` directory is created on first run.

---

## Step 6 — Install Claude Code Plugins and Settings

The `~/.claude/` directory is the **single source of truth** for the plugin ecosystem shared by both Claude Code and OpenCode. Oh-My-OpenCode reads directly from Claude Code's plugin infrastructure:

| File | What Oh-My-OpenCode reads |
| ---- | ------------------------- |
| `~/.claude/plugins/installed_plugins.json` | Plugin registry (discovers all installed plugins) |
| `~/.claude/settings.json` → `enabledPlugins` | Which plugins are active |
| `~/.claude/plugins/cache/<plugin>/.claude-plugin/plugin.json` | Plugin manifests (commands, agents, skills, hooks, MCP servers) |
| `~/.claude/plugins/cache/<plugin>/skills/SKILL.md` | Skill definitions |

There is **no separate plugin installation for OpenCode** — installing plugins here serves both tools. OpenCode's own config (`~/.config/opencode/`) handles agent routing and provider settings only, not plugins.

This step clones the official plugin marketplace, copies each enabled plugin into the cache directory, clones the superpowers framework separately, generates the JSON registry files, and merges settings into `~/.claude/settings.json` and `~/.claude.json`.

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

### 6.4 — Merge Container Settings into `~/.claude/settings.json`

This step idempotently merges the container's Claude Code settings (model, status line, permissions, env vars, plugins, accessibility) into the local `~/.claude/settings.json`. If the file already exists, **local values win on conflict** — any user-specific settings (like `voiceEnabled`) are preserved.

**Shared settings note**: `~/.claude/settings.json` is read by **both** Claude Code and Oh-My-OpenCode. The `enabledPlugins` key controls which plugins are active for both tools. The other keys in this file (model, statusLine, permissions, env, preferences) are Claude Code-specific — OpenCode's equivalent settings live in `~/.config/opencode/opencode.json` (Step 9).

The `jq -s '.[0] * .[1]'` pattern uses the container settings as the base (`.[0]`) and the local file as the override (`.[1]`), so existing local keys take precedence.

```bash
REPO_DIR="$(pwd)"

# Container settings adapted for local laptop:
# - statusLine.command points to ~/.claude/statusline.sh (not /opt/claude-config/)
CONTAINER_SETTINGS="$(cat <<SETTINGS
{
  "statusLine": { "type": "command", "command": "${HOME}/.claude/statusline.sh" },
  "model": "opus",
  "spinnerTipsEnabled": false,
  "terminalProgressBarEnabled": false,
  "showTurnDuration": false,
  "prefersReducedMotion": true,
  "companyAnnouncements": [],
  "teammateMode": "tmux",
  "defaultMode": "bypassPermissions",
  "skipDangerousModePermissionPrompt": true,
  "permissions": {
    "allow": ["Bash", "Edit", "Write", "mcp__*"]
  },
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
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "ANTHROPIC_SMALL_FAST_MODEL": "claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6"
  },
  "preferences": {
    "tmuxSplitPanes": true
  },
  "autoUpdatesChannel": "latest"
}
SETTINGS
)"

LOCAL_FILE="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

if [ -f "$LOCAL_FILE" ]; then
  # Deep merge: container as base, local overrides (local wins on conflict)
  if jq -s '.[0] * .[1]' <(echo "$CONTAINER_SETTINGS") "$LOCAL_FILE" > "${LOCAL_FILE}.tmp" \
     && [ -s "${LOCAL_FILE}.tmp" ]; then
    mv "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
    echo "Merged container settings into existing $LOCAL_FILE (local values preserved)"
  else
    echo "ERROR: jq merge failed — $LOCAL_FILE left unchanged"
    rm -f "${LOCAL_FILE}.tmp"
  fi
else
  echo "$CONTAINER_SETTINGS" | jq . > "$LOCAL_FILE"
  echo "Created $LOCAL_FILE from container defaults"
fi
```

### 6.4a — Install Status Line Script

The container runs a custom status line showing context window usage, Git branch, and working tree state. Install the same script locally so the `statusLine.command` in settings.json works:

```bash
REPO_DIR="$(pwd)"
SRC="${REPO_DIR}/claude-config/statusline.sh"
DEST="$HOME/.claude/statusline.sh"

if [ -f "$SRC" ]; then
  cp "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "Installed statusline.sh to $DEST"
else
  echo "WARNING: ${SRC} not found — skipping statusline install"
fi
```

### 6.5 — Merge MCP Servers into `~/.claude.json`

Selectively merge container state into the local `~/.claude.json`. This does **not** overwrite user preferences (theme, tips history) or container-specific project paths. It only sets marketplace flags and adds the Chrome DevTools MCP server if not already present.

```bash
LOCAL_FILE="$HOME/.claude.json"

if [ -f "$LOCAL_FILE" ]; then
  if jq '
    .hasCompletedOnboarding = true
    | .autoUpdates = true
    | .officialMarketplaceAutoInstallAttempted = true
    | .officialMarketplaceAutoInstalled = true
    | .mcpServers = ((.mcpServers // {}) + (
        if (.mcpServers // {} | has("chrome-devtools")) then {}
        else {"chrome-devtools": {"command":"npx","args":["-y","chrome-devtools-mcp@0.20.2","--browserUrl=http://localhost:9222"]}}
        end
      ))
  ' "$LOCAL_FILE" > "${LOCAL_FILE}.tmp" && [ -s "${LOCAL_FILE}.tmp" ]; then
    mv "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
    echo "Merged MCP servers and marketplace flags into $LOCAL_FILE"
  else
    echo "ERROR: jq merge failed — $LOCAL_FILE left unchanged"
    rm -f "${LOCAL_FILE}.tmp"
  fi
else
  echo "WARNING: $LOCAL_FILE does not exist — skipping (Claude Code creates this on first run)"
fi
```

### 6.5a — Pre-cache Chrome DevTools MCP

Pre-download the `chrome-devtools-mcp` package so the first MCP connection is instant. This matches the container's build-time caching:

```bash
echo "Pre-caching chrome-devtools-mcp..."
if npx -y chrome-devtools-mcp@0.20.2 -- --version 2>&1; then
  echo "chrome-devtools-mcp cached."
else
  echo "WARNING: Failed to pre-cache chrome-devtools-mcp — it will be downloaded on first use"
fi
```

### Verify Plugin and Settings Installation

```bash
# Check installed_plugins.json has all 14 plugins
jq 'length' ~/.claude/plugins/installed_plugins.json
# Expected: 14

# Check SKILL.md files were loaded
find ~/.claude/plugins/cache -name "SKILL.md" -type f | wc -l
# Expected: 19 (5 from official plugins + 14 from superpowers)

# Check settings.json has full container settings merged
jq '.enabledPlugins | keys | length' ~/.claude/settings.json  # Expected: 14
jq '.model' ~/.claude/settings.json                            # Expected: "opus"
jq '.statusLine.type' ~/.claude/settings.json                  # Expected: "command"
jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' ~/.claude/settings.json  # Expected: "1"

# Check statusline.sh is installed and executable
test -x ~/.claude/statusline.sh && echo "OK: statusline.sh" || echo "MISSING: statusline.sh"

# Check .claude.json has chrome-devtools MCP
jq '.mcpServers | has("chrome-devtools")' ~/.claude.json       # Expected: true

# Check all files are user-owned
ls -la ~/.claude/settings.json
ls -la ~/.claude/statusline.sh
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

### 8.3 — Google CLI Auth (gogcli + gws)

This section handles bidirectional credential sync for `gogcli` (gog) and Google Workspace CLI (gws). It is idempotent and handles three scenarios per tool:

| Local Auth | `.env` Credentials | Action |
| ---------- | ----------------- | ------ |
| Yes | Any | Export to `.env` (keep in sync) |
| No | Yes | Import from `.env` to local config |
| No | No | Print optional setup instructions |

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

# ── Helpers (re-defined for standalone execution of this code block) ──
env_get() {
  grep "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

env_set() {
  local key="$1" val="$2"
  if [ -z "$val" ]; then return; fi
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    local current
    current="$(grep "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2-)"
    current="${current%\"}"
    current="${current#\"}"
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

brew_install() {
  local pkg="$1"
  brew install "$pkg" 2>&1 || {
    echo "  Retrying $pkg install..."
    brew untap homebrew/core 2>/dev/null; brew install "$pkg"
  }
}

# =====================================================================
# gogcli (gog) — ensure installed, authenticated, and .env populated
# =====================================================================
echo ""
echo "── Google CLI: gogcli (gog) ──"

if ! command -v gog >/dev/null 2>&1; then
  echo "  Installing gogcli via Homebrew..."
  brew_install gogcli
fi

_GOG_AUTHED=false
if command -v gog >/dev/null 2>&1 && gog auth list --plain >/dev/null 2>&1; then
  _GOG_EMAIL="$(gog auth list --plain 2>/dev/null | head -1 | cut -f1)"
  if [ -n "$_GOG_EMAIL" ]; then
    _GOG_AUTHED=true
    echo "  Authenticated: $_GOG_EMAIL"
  fi
fi

if [ "$_GOG_AUTHED" = false ]; then
  # Try to restore from .env
  _ENV_GOG_CREDS="$(env_get GOG_CREDENTIALS_JSON)"
  _ENV_GOG_TOKEN="$(env_get GOG_TOKEN_JSON)"

  if [ -n "$_ENV_GOG_CREDS" ] && [ -n "$_ENV_GOG_TOKEN" ]; then
    echo "  Not authenticated locally — restoring from .env..."
    _GOG_TMP_CREDS="$(mktemp)"
    _GOG_TMP_TOKEN="$(mktemp)"
    echo "$_ENV_GOG_CREDS" | base64 -d > "$_GOG_TMP_CREDS"
    echo "$_ENV_GOG_TOKEN" | base64 -d > "$_GOG_TMP_TOKEN"
    gog auth credentials set "$_GOG_TMP_CREDS" 2>&1 \
      || echo "  WARNING: gog auth credentials set failed"
    gog auth tokens import "$_GOG_TMP_TOKEN" 2>&1 \
      || echo "  WARNING: gog auth tokens import failed"
    rm -f "$_GOG_TMP_CREDS" "$_GOG_TMP_TOKEN"

    # Verify import succeeded
    if gog auth list --plain >/dev/null 2>&1; then
      _GOG_EMAIL="$(gog auth list --plain 2>/dev/null | head -1 | cut -f1)"
      _GOG_AUTHED=true
      echo "  Restored from .env: $_GOG_EMAIL"
    else
      echo "  WARNING: restore from .env failed — credentials may be expired."
    fi
  else
    echo "  Not authenticated and no credentials in .env."
    echo "  OPTIONAL: to enable gogcli, run:"
    echo "    gog auth credentials set ~/Downloads/client_secret_*.json"
    echo "    gog auth add you@gmail.com"
    echo "  Then re-run this step."
  fi
fi

# Export to .env if authenticated (idempotent — env_set skips existing values)
if [ "$_GOG_AUTHED" = true ]; then
  env_set GOG_ACCOUNT "$_GOG_EMAIL"
  env_set GOG_KEYRING_PASSWORD "container"

  _GOG_CREDS_PATH="$HOME/Library/Application Support/gogcli/credentials.json"
  if [ -f "$_GOG_CREDS_PATH" ]; then
    _GOG_CREDS_B64="$(base64 < "$_GOG_CREDS_PATH")"
    [ -n "$_GOG_CREDS_B64" ] && env_set GOG_CREDENTIALS_JSON "$_GOG_CREDS_B64"
  fi

  if [ -n "$_GOG_EMAIL" ]; then
    _GOG_TMP="$(mktemp)"
    if gog auth tokens export "$_GOG_EMAIL" --out "$_GOG_TMP" --overwrite >/dev/null 2>&1; then
      _GOG_TOK_B64="$(base64 < "$_GOG_TMP")"
      [ -n "$_GOG_TOK_B64" ] && env_set GOG_TOKEN_JSON "$_GOG_TOK_B64"
    fi
    rm -f "$_GOG_TMP"
  fi
fi

# =====================================================================
# Google Workspace CLI (gws) — ensure installed, authenticated, .env populated
# =====================================================================
echo ""
echo "── Google CLI: gws (Google Workspace CLI) ──"

if ! command -v gws >/dev/null 2>&1; then
  echo "  Installing @googleworkspace/cli via npm..."
  npm install -g @googleworkspace/cli
fi

_GWS_AUTHED=false
_GWS_CONFIG="$HOME/.config/gws"
if command -v gws >/dev/null 2>&1 && [ -f "$_GWS_CONFIG/client_secret.json" ] && [ -f "$_GWS_CONFIG/credentials.enc" ]; then
  _GWS_AUTHED=true
  echo "  Authenticated (credentials.enc present)"
fi

if [ "$_GWS_AUTHED" = false ]; then
  # Try to restore from .env
  _ENV_GWS_CS="$(env_get GWS_CLIENT_SECRET_JSON)"
  _ENV_GWS_KEY="$(env_get GWS_ENCRYPTION_KEY)"
  _ENV_GWS_ENC="$(env_get GWS_CREDENTIALS_ENC)"

  if [ -n "$_ENV_GWS_CS" ] && [ -n "$_ENV_GWS_KEY" ] && [ -n "$_ENV_GWS_ENC" ]; then
    echo "  Not authenticated locally — restoring from .env..."
    mkdir -p "$_GWS_CONFIG"
    echo "$_ENV_GWS_CS" | base64 -d > "$_GWS_CONFIG/client_secret.json"
    echo "$_ENV_GWS_KEY" > "$_GWS_CONFIG/.encryption_key"
    echo "$_ENV_GWS_ENC" | base64 -d > "$_GWS_CONFIG/credentials.enc"
    chmod 600 "$_GWS_CONFIG/client_secret.json" "$_GWS_CONFIG/.encryption_key" "$_GWS_CONFIG/credentials.enc"

    # Restore token cache if available
    _ENV_GWS_TC="$(env_get GWS_TOKEN_CACHE)"
    if [ -n "$_ENV_GWS_TC" ]; then
      echo "$_ENV_GWS_TC" | base64 -d > "$_GWS_CONFIG/token_cache.json"
      chmod 600 "$_GWS_CONFIG/token_cache.json"
    fi

    _GWS_AUTHED=true
    echo "  Restored from .env"
  else
    echo "  Not authenticated and no credentials in .env."
    echo "  OPTIONAL: to enable gws, run:"
    echo "    gws auth setup --login"
    echo "  Then re-run this step."
  fi
fi

# Export to .env if authenticated (idempotent — env_set skips existing values)
if [ "$_GWS_AUTHED" = true ]; then
  if [ -f "$_GWS_CONFIG/client_secret.json" ]; then
    _GWS_CS_B64="$(base64 < "$_GWS_CONFIG/client_secret.json")"
    [ -n "$_GWS_CS_B64" ] && env_set GWS_CLIENT_SECRET_JSON "$_GWS_CS_B64"
  fi
  if [ -f "$_GWS_CONFIG/credentials.enc" ]; then
    _GWS_KEY="$(security find-generic-password -s "gws-cli" -w 2>/dev/null || cat "$_GWS_CONFIG/.encryption_key" 2>/dev/null)"
    [ -n "$_GWS_KEY" ] && env_set GWS_ENCRYPTION_KEY "$_GWS_KEY"
    _GWS_ENC_B64="$(base64 < "$_GWS_CONFIG/credentials.enc")"
    [ -n "$_GWS_ENC_B64" ] && env_set GWS_CREDENTIALS_ENC "$_GWS_ENC_B64"
  fi
  if [ -f "$_GWS_CONFIG/token_cache.json" ]; then
    _GWS_TC_B64="$(base64 < "$_GWS_CONFIG/token_cache.json")"
    [ -n "$_GWS_TC_B64" ] && env_set GWS_TOKEN_CACHE "$_GWS_TC_B64"
  fi
fi
```

### 8.4 — Prompt for Required Manual Variables

OpenCode supports two authentication modes:

| Mode | Required Variables | What's Available |
| ---- | ----------------- | ---------------- |
| **LiteLLM proxy** | `LITELLM_API_KEY` + `LITELLM_BASE_URL` | Multiple providers (Anthropic, OpenAI, X.ai via proxy) |
| **OAuth (direct)** | `CLAUDE_CODE_OAUTH_TOKEN` | Anthropic models only (Opus, Sonnet, Haiku) |

At least one mode must be configured. If `CLAUDE_CODE_OAUTH_TOKEN` is already set, the LiteLLM variables are optional. Step 8.2 attempted to recover LiteLLM values from an existing `opencode.json`.

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

# Check if OAuth token is set (alternative to LiteLLM proxy)
_OAUTH="$(grep "^CLAUDE_CODE_OAUTH_TOKEN=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"

if [ -n "$_OAUTH" ]; then
  echo "CLAUDE_CODE_OAUTH_TOKEN is set — OAuth mode available (Anthropic models only)"
  echo "LiteLLM proxy variables are optional in this mode."
fi

# Check LiteLLM variables
MISSING=""
for VAR in LITELLM_API_KEY LITELLM_BASE_URL; do
  VAL="$(grep "^${VAR}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
  case "$VAL" in
    ""|sk-example-api-key-here|https://proxy.example.com) MISSING="${MISSING} ${VAR}" ;;
  esac
done

if [ -n "$MISSING" ] && [ -z "$_OAUTH" ]; then
  echo "The following required variables are missing or have placeholder values in .env:"
  echo " $MISSING"
  echo ""
  echo "Neither LITELLM_API_KEY nor CLAUDE_CODE_OAUTH_TOKEN is configured."
  echo "Set one of these authentication methods before proceeding."
  echo ""
  echo "Option 1 (LiteLLM proxy): Ask the user for LITELLM_API_KEY and LITELLM_BASE_URL"
  echo "Option 2 (OAuth direct):  Set CLAUDE_CODE_OAUTH_TOKEN from Claude Code auth"
  # AI agent: stop here and ask the user which auth method to use.
elif [ -n "$MISSING" ]; then
  echo "LiteLLM proxy not configured — Steps 9/10 will use OAuth mode (Anthropic models only)"
else
  echo "All variables are set — Steps 9/10 will use LiteLLM proxy mode (multi-provider)"
fi
```

### 8.5 — Source `.env` into the Current Shell Session

After `.env` is populated, export all non-comment, non-empty lines so subsequent steps (Steps 9, 14) can reference the variables:

**Important**: macOS ships Bash 3.2 which does not support `lastpipe`. A `grep | while` pipeline runs the `while` in a subshell, so any variables exported inside it are lost when the loop ends. Use process substitution (`< <(...)`) instead to keep exports in the current shell:

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

# Source .env using set -a (auto-export) instead of eval.
# eval on .env lines is a code injection risk if values contain shell metacharacters.
set -a
source "$ENV_FILE"
set +a

# VERIFY: spot-check critical variables
if [ -n "$LITELLM_API_KEY" ]; then
  echo "Mode: LiteLLM proxy"
  echo "LITELLM_API_KEY=${LITELLM_API_KEY:0:10}..."
elif [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "Mode: OAuth (Anthropic direct)"
  echo "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:0:15}..."
else
  echo "WARNING: No auth configured"
fi
echo "TZ=$TZ"                                       # VERIFY: a valid IANA timezone
echo "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL"           # VERIFY: an email address
```

---

## Step 9 — Write `opencode.json`

This is the main OpenCode configuration file. The configuration depends on which authentication mode is available:

| Mode | Condition | Providers | Models |
| ---- | --------- | --------- | ------ |
| **LiteLLM proxy** | `LITELLM_API_KEY` is set | `anthropic-proxy` + `openai-proxy` | Opus, Sonnet, GPT-5.4, Grok |
| **OAuth (direct)** | `CLAUDE_CODE_OAUTH_TOKEN` is set | `anthropic` (native) | Opus, Sonnet only |

The script detects which mode to use and writes the appropriate config.

**Base URL derivation** (proxy mode only):

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

Write the file using the appropriate mode. The proxy-mode heredoc substitutes environment variables (note: **not** a quoted heredoc — the `$` variables are intentionally expanded). The OAuth-mode heredoc uses a quoted heredoc (no substitution needed):

```bash
mkdir -p ~/.config/opencode

if [ -n "$LITELLM_API_KEY" ] && [ -n "$LITELLM_BASE_URL" ]; then
  echo "Writing opencode.json (LiteLLM proxy mode — multi-provider)..."
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
  "permission": "allow",
  "plugin": [
    "@robinmordasiewicz/oh-my-opencode@3.11.0-fork.1"
  ],
  "lsp": {
    "marksman": { "command": ["marksman", "server"], "extensions": [".md", ".mdx"] },
    "mdx": { "command": ["mdx-language-server", "--stdio"], "extensions": [".mdx"] },
    "json": { "command": ["vscode-json-language-server", "--stdio"], "extensions": [".json", ".jsonc"] },
    "css": { "command": ["vscode-css-language-server", "--stdio"], "extensions": [".css", ".less", ".scss"] },
    "html": { "command": ["vscode-html-language-server", "--stdio"], "extensions": [".html", ".htm"] },
    "toml": { "command": ["taplo", "lsp", "stdio"], "extensions": [".toml"] }
  }
}
ENDOFJSON

elif [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "Writing opencode.json (OAuth mode — Anthropic models only)..."
  cat > ~/.config/opencode/opencode.json << 'ENDOFJSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "model": "anthropic/claude-opus-4-6",
  "small_model": "anthropic/claude-sonnet-4-6",
  "plugin": ["@robinmordasiewicz/oh-my-opencode@3.11.0-fork.1"],
  "mcp": {},
  "lsp": {
    "marksman": {
      "command": ["marksman", "server"],
      "extensions": [".md", ".mdx"]
    },
    "mdx": {
      "command": ["mdx-language-server", "--stdio"],
      "extensions": [".mdx"]
    },
    "json": {
      "command": ["vscode-json-language-server", "--stdio"],
      "extensions": [".json", ".jsonc"]
    },
    "css": {
      "command": ["vscode-css-language-server", "--stdio"],
      "extensions": [".css", ".less", ".scss"]
    },
    "html": {
      "command": ["vscode-html-language-server", "--stdio"],
      "extensions": [".html", ".htm"]
    },
    "toml": {
      "command": ["taplo", "lsp", "stdio"],
      "extensions": [".toml"]
    }
  }
}
ENDOFJSON

  # OAuth mode also needs auth.json for OpenCode to authenticate with Anthropic.
  # Use jq to safely escape any special characters in the OAuth token.
  mkdir -p ~/.local/share/opencode
  jq -n --arg token "$CLAUDE_CODE_OAUTH_TOKEN" \
    '{"anthropic":{"type":"oauth","access":$token,"refresh":"","expires":9999999999999}}' \
    > ~/.local/share/opencode/auth.json
  echo "Wrote OpenCode auth.json for OAuth mode"

else
  echo "ERROR: Neither LITELLM_API_KEY nor CLAUDE_CODE_OAUTH_TOKEN is set."
  echo "Re-run Step 8 to configure authentication before proceeding."
  echo "Stopping — do not proceed to Step 10 without authentication configured."
fi
```

Verify the file was written correctly:

```bash
jq '.model' ~/.config/opencode/opencode.json
# VERIFY: "anthropic-proxy/claude-opus-4-6" (proxy mode) or "anthropic/claude-opus-4-6" (OAuth mode)

# Proxy mode only:
if jq -e '.provider["openai-proxy"]' ~/.config/opencode/opencode.json >/dev/null 2>&1; then
  jq '.provider["openai-proxy"].options.baseURL' ~/.config/opencode/opencode.json
  # VERIFY: output is your actual OpenAI proxy URL (not empty, not a placeholder)
fi
```

---

## Step 10 — Write `oh-my-opencode.json`

This configures the Oh-My-OpenCode plugin — agent model assignments, task category routing, and background concurrency. The config depends on which authentication mode was detected in Step 9:

- **LiteLLM proxy**: Agents use a mix of `anthropic-proxy/` and `openai-proxy/` models (GPT-5.4 for visual/frontend tasks, Grok for fast exploration)
- **OAuth**: All agents use `anthropic/` models (Opus for heavy tasks, Sonnet for lighter ones)

```bash
if [ -n "$LITELLM_API_KEY" ] && [ -n "$LITELLM_BASE_URL" ]; then
  echo "Writing oh-my-opencode.json (proxy mode — multi-provider agents)..."
  cat > ~/.config/opencode/oh-my-opencode.json << 'ENDOFJSON'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",
  "agents": {
    "sisyphus": { "model": "anthropic-proxy/claude-opus-4-6" },
    "oracle": { "model": "anthropic-proxy/claude-opus-4-6" },
    "librarian": { "model": "anthropic-proxy/claude-opus-4-6" },
    "explore": { "model": "openai-proxy/grok-code-fast-1" },
    "multimodal-looker": { "model": "anthropic-proxy/claude-opus-4-6" },
    "prometheus": { "model": "anthropic-proxy/claude-opus-4-6" },
    "metis": { "model": "anthropic-proxy/claude-opus-4-6" },
    "hephaestus": { "model": "openai-proxy/gpt-5.4" },
    "momus": { "model": "anthropic-proxy/claude-opus-4-6" },
    "atlas": { "model": "anthropic-proxy/claude-sonnet-4-6" },
    "frontend-ui-ux-engineer": { "model": "openai-proxy/gpt-5.4" },
    "document-writer": { "model": "anthropic-proxy/claude-opus-4-6" }
  },
  "categories": {
    "visual-engineering": { "model": "openai-proxy/gpt-5.4" },
    "business-logic": { "model": "openai-proxy/gpt-5.4" },
    "ultrabrain": { "model": "openai-proxy/gpt-5.4" },
    "deep": { "model": "openai-proxy/gpt-5.4" },
    "artistry": { "model": "openai-proxy/gpt-5.4" },
    "quick": { "model": "anthropic-proxy/claude-sonnet-4-6" },
    "unspecified-low": { "model": "anthropic-proxy/claude-opus-4-6" },
    "unspecified-high": { "model": "anthropic-proxy/claude-opus-4-6" },
    "writing": { "model": "anthropic-proxy/claude-opus-4-6" }
  },
  "background_task": {
    "defaultConcurrency": 5,
    "providerConcurrency": {
      "openai-proxy": 5,
      "anthropic-proxy": 5
    }
  },
  "claude_code": {
    "plugins": true,
    "skills": true,
    "commands": true,
    "agents": true,
    "hooks": true,
    "mcp": true
  }
}
ENDOFJSON

else
  echo "Writing oh-my-opencode.json (OAuth mode — Anthropic models only)..."
  cat > ~/.config/opencode/oh-my-opencode.json << 'ENDOFJSON'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",
  "agents": {
    "sisyphus": { "model": "anthropic/claude-opus-4-6" },
    "oracle": { "model": "anthropic/claude-opus-4-6" },
    "librarian": { "model": "anthropic/claude-opus-4-6" },
    "explore": { "model": "anthropic/claude-sonnet-4-6" },
    "multimodal-looker": { "model": "anthropic/claude-opus-4-6" },
    "prometheus": { "model": "anthropic/claude-opus-4-6" },
    "metis": { "model": "anthropic/claude-opus-4-6" },
    "hephaestus": { "model": "anthropic/claude-opus-4-6" },
    "momus": { "model": "anthropic/claude-opus-4-6" },
    "atlas": { "model": "anthropic/claude-sonnet-4-6" },
    "frontend-ui-ux-engineer": { "model": "anthropic/claude-opus-4-6" },
    "document-writer": { "model": "anthropic/claude-opus-4-6" }
  },
  "categories": {
    "visual-engineering": { "model": "anthropic/claude-opus-4-6" },
    "business-logic": { "model": "anthropic/claude-opus-4-6" },
    "ultrabrain": { "model": "anthropic/claude-opus-4-6" },
    "deep": { "model": "anthropic/claude-opus-4-6" },
    "artistry": { "model": "anthropic/claude-opus-4-6" },
    "quick": { "model": "anthropic/claude-sonnet-4-6" },
    "unspecified-low": { "model": "anthropic/claude-opus-4-6" },
    "unspecified-high": { "model": "anthropic/claude-opus-4-6" },
    "writing": { "model": "anthropic/claude-opus-4-6" }
  },
  "background_task": {
    "defaultConcurrency": 5,
    "providerConcurrency": {
      "anthropic": 5
    }
  },
  "claude_code": {
    "plugins": true,
    "skills": true,
    "commands": true,
    "agents": true,
    "hooks": true,
    "mcp": true
  }
}
ENDOFJSON
fi
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
# Use --format json because default format requires a TTY and hangs in
# non-interactive shells (e.g., when an AI agent runs this script).
echo "Running OpenCode smoke test from /tmp..."
cd /tmp
SMOKE_OUT=$(mktemp)
opencode run --format json "Reply with exactly one word: OPENCODE_OK" > "$SMOKE_OUT" 2>&1 &
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
    if [ -n "$LITELLM_API_KEY" ]; then
      echo "  Check LITELLM_API_KEY and LITELLM_BASE_URL in .env"
    else
      echo "  Check CLAUDE_CODE_OAUTH_TOKEN in .env"
    fi
    cat "$SMOKE_OUT"
    rm -f "$SMOKE_OUT"
    exit 1
  fi
done
wait "$OCPID"
OC_EXIT=$?

# Extract the text response from JSON output
CLEAN_OUT=$(jq -r 'select(.type=="text") | .part.text' "$SMOKE_OUT" 2>/dev/null | head -1)

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
2. **API connectivity** (proxy mode): `curl -s -o /dev/null -w "%{http_code}" "${LITELLM_BASE_URL}/api/v1/models" -H "Authorization: Bearer ${LITELLM_API_KEY}"` — should return `200`.
3. **OAuth auth.json** (OAuth mode): `cat ~/.local/share/opencode/auth.json | jq .` — should show a valid JSON with `anthropic.access` set.
4. **Plugin load failure**: `rm -rf ~/.cache/opencode/node_modules && opencode run --format json "test"` — forces a clean plugin re-download.

---

## Step 14 — Configure `~/.zshrc` (Environment Variables and PATH)

Oh My Zsh (Step 5) created `~/.zshrc` with its own boilerplate. This step adds environment variables and PATH entries **after** the Oh My Zsh `source` line.

**Idempotency strategy**: Each block below uses `grep -q` to check if the line already exists before appending. This makes the step safe to re-run without creating duplicate entries.

**IMPORTANT**: The `LITELLM_API_KEY` line uses the `$LITELLM_API_KEY` environment variable sourced from `.env` in Step 8.5. That variable must still be set in the current shell session.

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

### 14.2 — Middle: Oh My Zsh Settings

The theme and plugins were set in Step 5.5. Now add the remaining Oh My Zsh settings that match the devcontainer. These use `sed` to uncomment and set values that Oh My Zsh's default `~/.zshrc` includes as commented-out examples:

```bash
sed -i '' 's/^# HYPHEN_INSENSITIVE=.*/HYPHEN_INSENSITIVE="true"/' ~/.zshrc
sed -i '' 's/^# COMPLETION_WAITING_DOTS=.*/COMPLETION_WAITING_DOTS="true"/' ~/.zshrc
sed -i '' 's/^# HIST_STAMPS=.*/HIST_STAMPS="yyyy-mm-dd"/' ~/.zshrc
```

Verify the theme, plugins, and settings are present:

```bash
grep '^ZSH_THEME="powerlevel10k/powerlevel10k"' ~/.zshrc   # VERIFY: line exists
grep '^plugins=(zsh-syntax-highlighting' ~/.zshrc            # VERIFY: line exists
grep '^HYPHEN_INSENSITIVE="true"' ~/.zshrc                   # VERIFY: line exists
grep '^COMPLETION_WAITING_DOTS="true"' ~/.zshrc              # VERIFY: line exists
grep '^HIST_STAMPS="yyyy-mm-dd"' ~/.zshrc                    # VERIFY: line exists
```

### 14.3 — After `source $ZSH/oh-my-zsh.sh`: User Configuration

Append each line only if it is not already present. Each `grep -q` guard prevents duplicates on re-runs:

```bash
# Homebrew (Apple Silicon)
grep -q 'brew shellenv' ~/.zshrc || \
  echo 'eval $(/opt/homebrew/bin/brew shellenv)' >> ~/.zshrc

# Powerlevel10k config (installed in Step 5.6)
grep -q 'p10k.zsh' ~/.zshrc || \
  echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc

# History size (match devcontainer)
grep -q 'HISTSIZE=50000' ~/.zshrc || \
  echo 'export HISTSIZE=50000' >> ~/.zshrc
grep -q 'SAVEHIST=50000' ~/.zshrc || \
  echo 'export SAVEHIST=50000' >> ~/.zshrc

# Vim alias (use Neovim)
grep -q 'alias vim=nvim' ~/.zshrc || \
  echo 'alias vim=nvim' >> ~/.zshrc

# Less pager configuration
grep -q 'export LESS=' ~/.zshrc || \
  echo 'export LESS="-R -F -X -i -J --mouse"' >> ~/.zshrc
grep -q 'LESSHISTFILE' ~/.zshrc || \
  echo 'export LESSHISTFILE="$HOME/.cache/lesshst"' >> ~/.zshrc
grep -q 'LESSOPEN' ~/.zshrc || \
  echo 'export LESSOPEN="|~/.lessfilter %s"' >> ~/.zshrc

# Man pages with bat syntax highlighting
grep -q 'MANPAGER' ~/.zshrc || \
  echo 'export MANPAGER="sh -c '\''col -bx | bat -l man -p'\''"' >> ~/.zshrc
grep -q 'BAT_THEME' ~/.zshrc || \
  echo 'export BAT_THEME="Coldark-Dark"' >> ~/.zshrc

# Bun
grep -q 'BUN_INSTALL' ~/.zshrc || \
  echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.zshrc
grep -q 'BUN_INSTALL/bin' ~/.zshrc || \
  echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.zshrc

# Bun completions
grep -q '_bun' ~/.zshrc || \
  echo '[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"'  >> ~/.zshrc

# gogcli (gog) zsh completion
# OpenCode zsh completion
opencode completion > /opt/homebrew/share/zsh/site-functions/_opencode 2>/dev/null || true

# gogcli (gog) zsh completion
gog completion zsh > /opt/homebrew/share/zsh/site-functions/_gog 2>/dev/null || true

# User-local binaries (docker shim, etc.)
grep -q '\.local/bin' ~/.zshrc || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# iTerm2 utilities (imgcat, imgls, it2api, etc.)
grep -q 'iTerm.app' ~/.zshrc || \
  echo 'export PATH="/Applications/iTerm.app/Contents/Resources/utilities:$PATH"' >> ~/.zshrc

# API key for AI proxy (sourced from .env in Step 8.5)
# Only write if LITELLM_API_KEY is actually set — in OAuth mode it's empty
if [ -n "$LITELLM_API_KEY" ]; then
  grep -q 'LITELLM_API_KEY' ~/.zshrc || \
    echo "export LITELLM_API_KEY=\"${LITELLM_API_KEY}\"" >> ~/.zshrc
fi

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

### 16.9 — Claude Code Plugins and Settings

```bash
# Verify plugin count
jq 'length' ~/.claude/plugins/installed_plugins.json
# Expected: 14

# Verify SKILL.md files
find ~/.claude/plugins/cache -name "SKILL.md" -type f | wc -l
# Expected: 19

# Verify settings.json has full container settings
jq '.enabledPlugins | keys | length' ~/.claude/settings.json    # Expected: 14
jq '.model' ~/.claude/settings.json                              # Expected: "opus"
jq '.statusLine.type' ~/.claude/settings.json                    # Expected: "command"
jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' ~/.claude/settings.json  # Expected: "1"

# Verify statusline.sh installed
test -x ~/.claude/statusline.sh && echo "OK: statusline.sh" || echo "MISSING"  # Expected: OK

# Verify MCP server configured
jq '.mcpServers | has("chrome-devtools")' ~/.claude.json         # Expected: true
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
ls ~/.oh-my-zsh/custom/plugins/zsh-claudecode-completion                         # VERIFY: directory exists
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf                                    # VERIFY: file exists (p10k font)
grep "^ZSH_THEME" ~/.zshrc                                                      # VERIFY: output contains "powerlevel10k"
grep "^plugins=" ~/.zshrc                                                        # VERIFY: output includes "zsh-claudecode-completion"
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Silence Bell"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                              # VERIFY: true
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Visual Bell"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                              # VERIFY: false
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Unlimited Scrollback"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                              # VERIFY: true
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Option Key Sends"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist                              # VERIFY: 2
defaults read com.googlecode.iterm2 TabStyleWithAutomaticOption                  # VERIFY: 1 (Dark)
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
