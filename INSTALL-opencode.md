# OpenCode + Oh-My-OpenCode — AI Agent Stack Setup

> **Audience**: Plain-language instructions for OpenCode itself or a human operator.
> **Platform**: macOS on Apple Silicon (arm64). Homebrew is already installed.
> **Prerequisite**: Run `INSTALL-devtools.md` first — it installs Node.js, npm, and other
> foundational tools that this guide depends on.
>
> **Execution**: Steps are sequential and idempotent. Each includes inline VERIFY comments.
> Steps marked **MANUAL STEP** require human interaction.

---

## Preflight Check — Verify Permissions

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
  echo "Paste the following into your terminal, then rerun:"
  echo ""
  echo '  mkdir -p ~/.config/opencode'
  echo '  cat > ~/.config/opencode/opencode.json << '"'"'EOF'"'"''
  echo '  { "$schema": "https://opencode.ai/config.json", "permission": "allow" }'
  echo '  EOF'
  echo ""
  exit 1
fi
echo "Preflight check passed — permissions are configured correctly."
```

---

## Step 1 — Install OpenCode Core Dependencies (Homebrew)

```bash
# Helper function: install a brew package with stale-Cellar recovery.
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
  if [ -d "$cellar" ]; then
    echo "  Attempting to link existing Cellar entry for $pkg..."
    brew link --overwrite "$pkg" 2>&1 || true
  fi
}

# Core runtime (required by opencode)
brew_install node
brew_install ripgrep
brew_install jq

# GitHub CLI (used by opencode for PR/issue operations)
brew_install gh

# Terminal multiplexer (used by opencode for interactive sessions)
brew_install tmux

# LSP servers (opencode auto-detects these on PATH)
brew_install marksman
brew_install shellcheck
brew_install shfmt
brew install hashicorp/tap/terraform-ls 2>/dev/null \
  || brew_install terraform-ls

# Browser automation CLI for AI agents
brew_install playwright-cli
```

### Verify Step 1 — Core Dependencies

```bash
node --version         # VERIFY: v25.x+
npm --version          # VERIFY: 11.x+
rg --version           # VERIFY: contains "ripgrep"
gh --version           # VERIFY: gh version 2.x+
tmux -V                # VERIFY: tmux 3.x+
jq --version           # VERIFY: jq-1.x+
marksman --version     # VERIFY: prints a version string
shellcheck --version   # VERIFY: version 0.10+
shfmt --version        # VERIFY: v3.x+
terraform-ls --version # VERIFY: a version number
playwright-cli --version # VERIFY: a version number
```

---

## Step 2 — Install npm Global Packages (LSP Servers)

**Important**: Node.js is installed via Homebrew, so `npm install -g` writes to `/opt/homebrew/lib` — no `sudo` required.

```bash
npm install -g vscode-langservers-extracted   # HTML, CSS, JSON, ESLint LSP servers
npm install -g bash-language-server           # Bash/Zsh/Shell LSP
npm install -g yaml-language-server           # YAML LSP
npm install -g @mdx-js/language-server        # MDX LSP
npm install -g pyright                        # Python LSP (pyright-langserver)
npm install -g @googleworkspace/cli           # Google Workspace admin CLI (gws)
npm install -g @typescript/native-preview     # tsgo — TypeScript 7 Go port
npm install -g pptxgenjs                      # PowerPoint generation
npm install -g react-icons react react-dom    # React ecosystem
npm install -g sharp                          # Image processing
```

### Verify Step 2 — npm Global Packages

```bash
npm list -g --depth=0 2>/dev/null | grep -E "(vscode-langservers|bash-language|yaml-language|mdx-js|pyright|googleworkspace|native-preview)"
which pyright-langserver   # VERIFY: path to pyright LSP binary
```

---

## Step 3 — Install Bun

Bun is used by OpenCode internally for plugin management.

```bash
npm install -g bun
```

### Verify Step 3 — Bun

```bash
which bun       # VERIFY: /opt/homebrew/bin/bun or ~/.bun/bin/bun
bun --version   # VERIFY: 1.3.x+
```

---

## Step 3b — Install OpenCode (f5xc Fork)

The f5xc fork of OpenCode includes a persistent footer with p10k-style Git status colorization, LiteLLM empty content fixes, and auto-updates from the fork's Homebrew tap.

```bash
brew tap f5xc-salesdemos/tap
brew install f5xc-salesdemos/tap/opencode
```

### Verify Step 3b — OpenCode

```bash
which opencode      # VERIFY: /opt/homebrew/bin/opencode
opencode --version  # VERIFY: version contains "-f5xc."
```

### Upgrade

```bash
brew upgrade f5xc-salesdemos/tap/opencode
```

---

## Step 4 — Install Google Chrome

Chrome is required by the `chrome-devtools-mcp` MCP server for browser automation.

```bash
[ -d "/Applications/Google Chrome.app" ] || brew install --cask google-chrome
```

### Verify Step 4 — Google Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

---

## Step 5 — Install Claude Code Plugins and Settings

The `~/.claude/` directory is the **single source of truth** for the plugin ecosystem shared by both Claude Code and OpenCode.

### 5.1 — Clone Plugin Marketplaces

```bash
mkdir -p ~/.claude/plugins/marketplaces

# Official Anthropic marketplace
if [ -d ~/.claude/plugins/marketplaces/claude-plugins-official/.git ]; then
  git -C ~/.claude/plugins/marketplaces/claude-plugins-official pull --ff-only
else
  rm -rf ~/.claude/plugins/marketplaces/claude-plugins-official
  git clone --depth=1 --single-branch --branch main \
    https://github.com/anthropics/claude-plugins-official.git \
    ~/.claude/plugins/marketplaces/claude-plugins-official
fi

# f5xc-salesdemos marketplace
if [ -d ~/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace/.git ]; then
  git -C ~/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace pull --ff-only
else
  rm -rf ~/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace
  git clone --depth=1 --single-branch --branch main \
    https://github.com/f5xc-salesdemos/marketplace.git \
    ~/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace
fi

# thedotmack/claude-mem — persistent memory plugin (pinned to audited SHA)
# PINNED_DEPS_LAST_AUDITED: 2026-03-28 — next review: 2026-06-28
CLAUDE_MEM_SHA="a656af2bff0fb8bb413a2ad8da1b9f1b4a6d2eb6"
if [ -d ~/.claude/plugins/marketplaces/thedotmack/.git ]; then
  git -C ~/.claude/plugins/marketplaces/thedotmack fetch origin
  git -C ~/.claude/plugins/marketplaces/thedotmack checkout "$CLAUDE_MEM_SHA"
else
  rm -rf ~/.claude/plugins/marketplaces/thedotmack
  git clone --depth=50 --single-branch --branch main \
    https://github.com/thedotmack/claude-mem.git \
    ~/.claude/plugins/marketplaces/thedotmack
  git -C ~/.claude/plugins/marketplaces/thedotmack checkout "$CLAUDE_MEM_SHA"
fi
```

### 5.2 — Install Each Plugin into the Cache

```bash
PLUGIN_BASE="$HOME/.claude/plugins"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
ENTRIES="[]"

for KEY in \
  frontend-design@claude-plugins-official \
  superpowers@claude-plugins-official \
  code-review@claude-plugins-official \
  code-simplifier@claude-plugins-official \
  feature-dev@claude-plugins-official \
  ralph-loop@claude-plugins-official \
  typescript-lsp@claude-plugins-official \
  commit-commands@claude-plugins-official \
  security-guidance@claude-plugins-official \
  claude-md-management@claude-plugins-official \
  pr-review-toolkit@claude-plugins-official \
  skill-creator@claude-plugins-official \
  claude-code-setup@claude-plugins-official \
  hookify@claude-plugins-official \
  f5xc-sales-engineer@f5xc-salesdemos-marketplace \
  f5xc-docs-tools@f5xc-salesdemos-marketplace \
  f5xc-github-ops@f5xc-salesdemos-marketplace \
  f5xc-docs-pipeline@f5xc-salesdemos-marketplace \
  f5xc-brand@f5xc-salesdemos-marketplace \
  f5xc-devcontainer@f5xc-salesdemos-marketplace \
  f5xc-platform@f5xc-salesdemos-marketplace \
  f5xc-meddpicc@f5xc-salesdemos-marketplace \
  claude-mem@thedotmack \
; do
  NAME="$(echo "$KEY" | cut -d@ -f1)"
  MKT="$(echo "$KEY" | cut -d@ -f2)"
  MKT_DIR="${PLUGIN_BASE}/marketplaces/${MKT}"
  CACHE_DIR="${PLUGIN_BASE}/cache/${MKT}"

  mkdir -p "$CACHE_DIR"

  GIT_SHA=""
  if [ -d "$MKT_DIR/.git" ]; then
    GIT_SHA="$(cd "$MKT_DIR" && git rev-parse HEAD)"
  fi

  SRC=""
  if [ -d "${MKT_DIR}/plugins/${NAME}" ]; then
    SRC="${MKT_DIR}/plugins/${NAME}"
  elif [ -d "${MKT_DIR}/external_plugins/${NAME}" ]; then
    SRC="${MKT_DIR}/external_plugins/${NAME}"
  elif [ "$NAME" = "claude-mem" ] && [ -d "${MKT_DIR}/plugin" ]; then
    SRC="${MKT_DIR}/plugin"
  fi

  VERSION="${GIT_SHA:-0.0.0}"
  if [ -n "$SRC" ] && [ -f "${SRC}/.claude-plugin/plugin.json" ]; then
    V="$(jq -r '.version // empty' "${SRC}/.claude-plugin/plugin.json")"
    [ -n "$V" ] && VERSION="$V"
  fi

  DEST="${CACHE_DIR}/${NAME}/${VERSION}"
  mkdir -p "$DEST"

  if [ -n "$SRC" ]; then
    rm -rf "$DEST" && mkdir -p "$DEST"
    cp -a "${SRC}/." "$DEST/"
  elif [ "$NAME" = "superpowers" ]; then
    EXISTING="$(ls -d "${CACHE_DIR}/${NAME}"/*/. 2>/dev/null | head -1)"
    if [ -n "$EXISTING" ]; then
      DEST="${EXISTING%/.}"
      VERSION="$(basename "$DEST")"
    else
      git clone --depth=1 --single-branch --branch main \
        https://github.com/obra/superpowers.git "$DEST"
      if [ -f "${DEST}/.claude-plugin/plugin.json" ]; then
        V="$(jq -r '.version // empty' \
          "${DEST}/.claude-plugin/plugin.json")"
        if [ -n "$V" ] && [ "$V" != "$VERSION" ]; then
          NEW_DEST="${CACHE_DIR}/${NAME}/${V}"
          mkdir -p "$NEW_DEST"
          cp -a "${DEST}/." "$NEW_DEST/"
          rm -rf "$DEST"
          DEST="$NEW_DEST"
          VERSION="$V"
        fi
      fi
    fi
  else
    echo "WARNING: no source for '$NAME' in '$MKT', skipping"
    rm -rf "${CACHE_DIR}/${NAME}"
    continue
  fi

  ENTRIES=$(echo "$ENTRIES" | jq \
    --arg key "$KEY" --arg scope "user" \
    --arg path "$DEST" --arg ver "$VERSION" \
    --arg ts "$TIMESTAMP" --arg sha "$GIT_SHA" \
    '. + [{"key":$key,"scope":$scope,"installPath":$path,
      "version":$ver,"installedAt":$ts,
      "lastUpdated":$ts,"gitCommitSha":$sha}]')
done

# Write v2 format
echo "$ENTRIES" | jq '{
  version: 2,
  plugins: (reduce .[] as $e ({}; .[$e.key] = [($e | del(.key))]))
}' > "${PLUGIN_BASE}/installed_plugins.json"

# claude-mem runtime dependencies
CMEM_PKG=$(find ~/.claude/plugins/cache/thedotmack/claude-mem \
  -name "package.json" -not -path "*/node_modules/*" -maxdepth 3 -print -quit 2>/dev/null)
if [ -n "$CMEM_PKG" ]; then
  (cd "$(dirname "$CMEM_PKG")" && npm install)
fi
```

### 5.3 — Create Supporting Registry Files

```bash
PLUGIN_BASE="$HOME/.claude/plugins"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

jq -n \
  --arg cl "${PLUGIN_BASE}/marketplaces/claude-plugins-official" \
  --arg f5 "${PLUGIN_BASE}/marketplaces/f5xc-salesdemos-marketplace" \
  --arg td "${PLUGIN_BASE}/marketplaces/thedotmack" \
  --arg ts "$TIMESTAMP" '{
  "claude-plugins-official": {
    "source": {"source":"github","repo":"anthropics/claude-plugins-official"},
    "installLocation": $cl, "lastUpdated": $ts, "autoUpdate": true
  },
  "f5xc-salesdemos-marketplace": {
    "source": {"source":"github","repo":"f5xc-salesdemos/marketplace"},
    "installLocation": $f5, "lastUpdated": $ts, "autoUpdate": true
  },
  "thedotmack": {
    "source": {"source":"github","repo":"thedotmack/claude-mem"},
    "installLocation": $td, "lastUpdated": $ts, "autoUpdate": false
  }
}' > "${PLUGIN_BASE}/known_marketplaces.json"

printf '{"fetchedAt":"%s","plugins":[]}' "$TIMESTAMP" > "${PLUGIN_BASE}/blocklist.json"
```

### 5.4 — Install External Skills

```bash
mkdir -p ~/.claude/skills

# frontend-slides (pinned to audited SHA)
# PINNED_DEPS_LAST_AUDITED: 2026-03-28 — next review: 2026-06-28
FRONTEND_SLIDES_SHA="fbf2c17fa4356e7802b055a3626c7dd6a5d509ea"
if [ -d ~/.claude/skills/frontend-slides/.git ]; then
  git -C ~/.claude/skills/frontend-slides fetch origin
  git -C ~/.claude/skills/frontend-slides checkout "$FRONTEND_SLIDES_SHA"
else
  git clone --depth=50 --single-branch --branch main \
    https://github.com/zarazhangrui/frontend-slides.git \
    ~/.claude/skills/frontend-slides
  git -C ~/.claude/skills/frontend-slides checkout "$FRONTEND_SLIDES_SHA"
fi

uv pip install --system --break-system-packages python-pptx
```

### 5.5 — Install Status Line Script

```bash
REPO_DIR="$(pwd)"
SRC="${REPO_DIR}/claude-config/statusline.sh"
DEST="$HOME/.claude/statusline.sh"

if [ -f "$SRC" ]; then
  \cp -f "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "Installed statusline.sh to $DEST"
else
  echo "WARNING: ${SRC} not found — skipping statusline install"
fi
```

### 5.6 — Merge Container Settings into `~/.claude/settings.json`

This step idempotently merges settings into `~/.claude/settings.json`. Local values win on conflict.

```bash
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
    "hookify@claude-plugins-official": true,
    "f5xc-sales-engineer@f5xc-salesdemos-marketplace": true,
    "f5xc-docs-tools@f5xc-salesdemos-marketplace": true,
    "f5xc-github-ops@f5xc-salesdemos-marketplace": true,
    "f5xc-docs-pipeline@f5xc-salesdemos-marketplace": true,
    "f5xc-brand@f5xc-salesdemos-marketplace": true,
    "f5xc-devcontainer@f5xc-salesdemos-marketplace": true,
    "f5xc-platform@f5xc-salesdemos-marketplace": true,
    "f5xc-meddpicc@f5xc-salesdemos-marketplace": true,
    "claude-mem@thedotmack": true
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
  if jq -s '.[0] * .[1]' <(echo "$CONTAINER_SETTINGS") "$LOCAL_FILE" > "${LOCAL_FILE}.tmp" \
     && [ -s "${LOCAL_FILE}.tmp" ]; then
    mv -f "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
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

### 5.7 — Merge MCP Servers into `~/.claude.json`

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
        else {"chrome-devtools": {"command":"npx","args":["-y","chrome-devtools-mcp@^0.20.2","--executablePath","/Applications/Google Chrome.app/Contents/MacOS/Google Chrome","--chromeArg=--disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades,HttpsFirstModeV2","--chromeArg=--no-first-run","--chromeArg=--no-default-browser-check","--chromeArg=--disable-extensions","--chromeArg=--disable-background-timer-throttling","--chromeArg=--disable-backgrounding-occluded-windows"]}}
        end
      ))
  ' "$LOCAL_FILE" > "${LOCAL_FILE}.tmp" && [ -s "${LOCAL_FILE}.tmp" ]; then
    mv -f "${LOCAL_FILE}.tmp" "$LOCAL_FILE"
    echo "Merged MCP servers and marketplace flags into $LOCAL_FILE"
  else
    echo "ERROR: jq merge failed — $LOCAL_FILE left unchanged"
    rm -f "${LOCAL_FILE}.tmp"
  fi
else
  echo "WARNING: $LOCAL_FILE does not exist — skipping (Claude Code creates this on first run)"
fi
```

### 5.8 — Pre-cache Chrome DevTools MCP

```bash
echo "Pre-caching chrome-devtools-mcp..."
if npx -y chrome-devtools-mcp@^0.20.2 -- --version 2>&1; then
  echo "chrome-devtools-mcp cached."
else
  echo "WARNING: Failed to pre-cache chrome-devtools-mcp — it will be downloaded on first use"
fi
```

---

## Step 5b — Install AI Tool Extensions

### NotebookLM MCP CLI

```bash
uv tool install 'notebooklm-mcp-cli>=0.5.2,<1.0'
```

### Playwright CLI Skills

```bash
playwright-cli install --skills
```

### CLI-Anything (Claude Code Plugin)

> **INTERACTIVE STEP**: Start Claude Code (`claude`) and run:
>
> 1. `/plugin marketplace add HKUDS/CLI-Anything`
> 2. `/plugin install cli-anything`

---

## Step 6 — Install OpenCode Plugin SDK Dependencies

```bash
mkdir -p ~/.config/opencode
```

Write `~/.config/opencode/package.json`:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "^1.3.3"
  }
}
```

```bash
(cd ~/.config/opencode && bun install)
```

### 6.1 — Pre-cache OpenCode Runtime Dependencies

```bash
mkdir -p ~/.cache/opencode
printf '21' > ~/.cache/opencode/version
```

Write `~/.cache/opencode/package.json`:

```json
{
  "dependencies": {
    "@f5xc-salesdemos/oh-my-openagent": "f5xc",
    "@ai-sdk/anthropic": "^3.0.64",
    "@ai-sdk/openai-compatible": "^2.0.37",
    "opencode-anthropic-auth": "0.0.13"
  }
}
```

```bash
(cd ~/.cache/opencode && bun install)
```

### Verify Runtime Cache

```bash
ls ~/.cache/opencode/node_modules/@f5xc-salesdemos/oh-my-openagent/     # Expected: directory exists
ls ~/.cache/opencode/node_modules/@ai-sdk/anthropic/                   # Expected: directory exists
ls ~/.cache/opencode/node_modules/@ai-sdk/openai-compatible/           # Expected: directory exists
ls ~/.cache/opencode/node_modules/opencode-anthropic-auth/             # Expected: directory exists
```

---

## Step 7 — Create or Update `.env` (Environment File)

This repository includes a `.env.example` template. The `.env` file is gitignored and holds secrets.

### 7.1 — Bootstrap `.env`

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

### 7.2 — Auto-Detect and Populate Variables

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

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

echo "Auto-detecting environment variables..."

if readlink /etc/localtime >/dev/null 2>&1; then
  _TZ="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
  env_set TZ "$_TZ"
fi

if git config user.email >/dev/null 2>&1; then
  env_set GIT_AUTHOR_EMAIL "$(git config user.email)"
else
  echo "  PROMPT NEEDED: git user.email is not configured."
fi
if git config user.name >/dev/null 2>&1; then
  env_set GIT_AUTHOR_NAME "\"$(git config user.name)\""
else
  echo "  PROMPT NEEDED: git user.name is not configured."
fi

if gh auth status >/dev/null 2>&1; then
  _GH_TOKEN="$(gh auth token 2>/dev/null)"
  [ -n "$_GH_TOKEN" ] && env_set GH_TOKEN "$_GH_TOKEN"
fi

OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
if [ -f "$OPENCODE_JSON" ]; then
  _OC_API_KEY="$(jq -r '.provider["openai-proxy"].options.apiKey // empty' "$OPENCODE_JSON" 2>/dev/null)"
  [ -n "$_OC_API_KEY" ] && env_set LITELLM_API_KEY "$_OC_API_KEY"
  _OC_BASE_URL="$(jq -r '.provider["openai-proxy"].options.baseURL // empty' "$OPENCODE_JSON" 2>/dev/null)"
  _OC_BASE_URL="${_OC_BASE_URL%/api/v1}"
  [ -n "$_OC_BASE_URL" ] && env_set LITELLM_BASE_URL "$_OC_BASE_URL"
fi

echo "Auto-detection complete."
```

### 7.3 — Prompt for Required Manual Variables

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

_OAUTH="$(grep "^CLAUDE_CODE_OAUTH_TOKEN=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"

if [ -n "$_OAUTH" ]; then
  echo "CLAUDE_CODE_OAUTH_TOKEN is set — OAuth mode available"
fi

MISSING=""
for VAR in LITELLM_API_KEY LITELLM_BASE_URL; do
  VAL="$(grep "^${VAR}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
  case "$VAL" in
    ""|sk-example-api-key-here|https://proxy.example.com) MISSING="${MISSING} ${VAR}" ;;
  esac
done

if [ -n "$MISSING" ] && [ -z "$_OAUTH" ]; then
  echo "Missing:$MISSING"
  echo "Set LITELLM_API_KEY or CLAUDE_CODE_OAUTH_TOKEN before proceeding."
elif [ -n "$MISSING" ]; then
  echo "LiteLLM proxy not configured — will use OAuth mode (Anthropic only)"
else
  echo "All variables set — will use LiteLLM proxy mode (multi-provider)"
fi
```

### 7.4 — Source `.env`

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"
set -a
source "$ENV_FILE"
set +a
```

---

## Step 8 — Write `opencode.json`

The configuration depends on which authentication mode is available (LiteLLM proxy vs OAuth).

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
        "npx", "-y", "chrome-devtools-mcp@^0.20.2",
        "--executablePath", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "--chromeArg=--disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades,HttpsFirstModeV2",
        "--chromeArg=--no-first-run", "--chromeArg=--no-default-browser-check",
        "--chromeArg=--disable-extensions",
        "--chromeArg=--disable-background-timer-throttling",
        "--chromeArg=--disable-backgrounding-occluded-windows"
      ]
    }
  },
  "provider": {
    "openai-proxy": {
      "name": "OpenAI Proxy",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "${LITELLM_BASE_URL}/api/v1",
        "apiKey": "${LITELLM_API_KEY}"
      },
      "models": {
        "gpt-5.4": {
          "name": "GPT 5.4",
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 1000000, "output": 128000 },
          "options": { "reasoningSummary": null }
        },
        "grok-code-fast-1": {
          "name": "Explore",
          "modalities": { "input": ["text"], "output": ["text"] },
          "limit": { "context": 256000, "output": 256000 }
        }
      }
    },
    "anthropic-proxy": {
      "name": "Anthropic Proxy",
      "npm": "@ai-sdk/anthropic",
      "options": {
        "baseURL": "${LITELLM_BASE_URL}/anthropic/v1",
        "apiKey": "${LITELLM_API_KEY}"
      },
      "models": {
        "claude-opus-4-6": {
          "name": "Claude Opus 4.6",
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 1000000, "output": 128000 }
        },
        "claude-sonnet-4-6": {
          "name": "Claude Sonnet 4.6",
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 1000000, "output": 128000 }
        }
      }
    }
  },
  "model": "anthropic-proxy/claude-opus-4-6",
  "small_model": "anthropic-proxy/claude-sonnet-4-6",
  "permission": "allow",
  "plugin": ["@f5xc-salesdemos/oh-my-openagent@f5xc"],
      "lsp": {
    "marksman": { "command": ["marksman", "server"], "extensions": [".md", ".mdx"] },
    "mdx": { "command": ["mdx-language-server", "--stdio"], "extensions": [".mdx"] },
    "json": { "command": ["vscode-json-language-server", "--stdio"], "extensions": [".json", ".jsonc"] },
    "css": { "command": ["vscode-css-language-server", "--stdio"], "extensions": [".css", ".less", ".scss"] },
    "html": { "command": ["vscode-html-language-server", "--stdio"], "extensions": [".html", ".htm"] },
    "toml": { "command": ["taplo", "lsp", "stdio"], "extensions": [".toml"] },
    "python": { "command": ["pyright-langserver", "--stdio"], "extensions": [".py", ".pyi"] }
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
  "provider": {
    "anthropic": {
      "name": "Anthropic (OAuth)",
      "models": {
        "claude-opus-4-6": {
          "name": "Claude Opus 4.6",
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 1000000, "output": 128000 }
        },
        "claude-sonnet-4-6": {
          "name": "Claude Sonnet 4.6",
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 1000000, "output": 128000 }
        }
      }
    }
  },
  "plugin": ["opencode-claude-auth", "@f5xc-salesdemos/oh-my-openagent@f5xc"],
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "command": [
        "npx", "-y", "chrome-devtools-mcp@^0.20.2",
        "--executablePath", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "--chromeArg=--disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades,HttpsFirstModeV2",
        "--chromeArg=--no-first-run", "--chromeArg=--no-default-browser-check",
        "--chromeArg=--disable-extensions",
        "--chromeArg=--disable-background-timer-throttling",
        "--chromeArg=--disable-backgrounding-occluded-windows"
      ]
    }
  },
  "lsp": {
    "marksman": { "command": ["marksman", "server"], "extensions": [".md", ".mdx"] },
    "mdx": { "command": ["mdx-language-server", "--stdio"], "extensions": [".mdx"] },
    "json": { "command": ["vscode-json-language-server", "--stdio"], "extensions": [".json", ".jsonc"] },
    "css": { "command": ["vscode-css-language-server", "--stdio"], "extensions": [".css", ".less", ".scss"] },
    "html": { "command": ["vscode-html-language-server", "--stdio"], "extensions": [".html", ".htm"] },
    "toml": { "command": ["taplo", "lsp", "stdio"], "extensions": [".toml"] },
    "python": { "command": ["pyright-langserver", "--stdio"], "extensions": [".py", ".pyi"] }
  }
}
ENDOFJSON

  npm install -g opencode-claude-auth
  echo "Installed opencode-claude-auth for OAuth mode"

else
  echo "ERROR: Neither LITELLM_API_KEY nor CLAUDE_CODE_OAUTH_TOKEN is set."
  echo "Re-run Step 7 to configure authentication before proceeding."
fi
```

---

## Step 9 — Write `oh-my-opencode.json`

```bash
if [ -n "$LITELLM_API_KEY" ] && [ -n "$LITELLM_BASE_URL" ]; then
  echo "Writing oh-my-opencode.json (proxy mode — multi-provider agents)..."
  cat > ~/.config/opencode/oh-my-opencode.json << 'ENDOFJSON'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
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
    "providerConcurrency": { "openai-proxy": 5, "anthropic-proxy": 5 }
  },
  "claude_code": {
    "plugins": true, "skills": true, "commands": true,
    "agents": true, "hooks": true, "mcp": true
  }
}
ENDOFJSON

else
  echo "Writing oh-my-opencode.json (OAuth mode — Anthropic models only)..."
  cat > ~/.config/opencode/oh-my-opencode.json << 'ENDOFJSON'
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",
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
    "providerConcurrency": { "anthropic": 5 }
  },
  "claude_code": {
    "plugins": true, "skills": true, "commands": true,
    "agents": true, "hooks": true, "mcp": true
  }
}
ENDOFJSON
fi
```

---

## Step 10 — Write `AGENTS.md`

Write `~/.config/opencode/AGENTS.md`:

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

Write `~/.config/opencode/tui.json`:

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

Write `~/.config/opencode/.gitignore`:

```
node_modules
package.json
bun.lock
.gitignore
```

---

## Step 13 — Smoke-Test OpenCode Configuration

```bash
echo "Validating config file syntax..."
for f in opencode.json oh-my-opencode.json tui.json; do
  if ! jq . "$HOME/.config/opencode/$f" > /dev/null 2>&1; then
    echo "ERROR: $f is not valid JSON."
    exit 1
  fi
  echo "  OK: $f"
done

echo "Running OpenCode smoke test from /tmp..."
cd /tmp
SMOKE_OUT=$(mktemp)
opencode run --format json "Reply with exactly one word: OPENCODE_OK" > "$SMOKE_OUT" 2>&1 &
OCPID=$!

ELAPSED=0
while kill -0 "$OCPID" 2>/dev/null; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [ "$ELAPSED" -ge 120 ]; then
    kill "$OCPID" 2>/dev/null
    wait "$OCPID" 2>/dev/null
    echo "ERROR: opencode run timed out after 120 seconds."
    cat "$SMOKE_OUT"
    rm -f "$SMOKE_OUT"
    exit 1
  fi
done
wait "$OCPID"
OC_EXIT=$?

CLEAN_OUT=$(jq -r 'select(.type=="text") | .part.text' "$SMOKE_OUT" 2>/dev/null | head -1)

if [ "$OC_EXIT" -ne 0 ]; then
  echo "ERROR: opencode run exited with code $OC_EXIT"
  cat "$SMOKE_OUT"
  rm -f "$SMOKE_OUT"
  exit 1
elif [ -z "$CLEAN_OUT" ]; then
  echo "ERROR: opencode run produced no response"
  cat "$SMOKE_OUT"
  rm -f "$SMOKE_OUT"
  exit 1
else
  echo "Smoke test passed — OpenCode responded: $CLEAN_OUT"
fi
rm -f "$SMOKE_OUT"
cd - > /dev/null
```

---

## Step 14 — Configure `.zshrc` (OpenCode-Specific Entries)

These entries add OpenCode-specific environment variables and completions to `~/.zshrc`. They are appended idempotently using `grep -q` guards.

```bash
# OpenCode zsh completion
grep -q 'opencode-completions' ~/.zshrc || \
  opencode completion >> ~/.zshrc

# API key for AI proxy (only in LiteLLM proxy mode)
if [ -n "$LITELLM_API_KEY" ]; then
  grep -q 'LITELLM_API_KEY' ~/.zshrc || \
    echo "export LITELLM_API_KEY=\"${LITELLM_API_KEY}\"" >> ~/.zshrc
fi

# Claude Code plugin autoupdate
grep -q 'FORCE_AUTOUPDATE_PLUGINS' ~/.zshrc || \
  echo 'export FORCE_AUTOUPDATE_PLUGINS=true' >> ~/.zshrc
```

---

## Verify the Complete OpenCode Installation

```bash
opencode --version          # VERIFY: version contains "-f5xc."
node --version              # VERIFY: v25.x+
bun --version               # VERIFY: 1.3.x+

# LSP servers on PATH
which bash-language-server yaml-language-server marksman terraform-ls shellcheck shfmt pyright-langserver

# OpenCode config files
ls -la ~/.config/opencode/opencode.json
ls -la ~/.config/opencode/oh-my-opencode.json
ls -la ~/.config/opencode/AGENTS.md
ls -la ~/.config/opencode/tui.json
ls -la ~/.config/opencode/package.json
ls -la ~/.config/opencode/node_modules/@opencode-ai/plugin/

# Runtime cache
ls ~/.cache/opencode/node_modules/@f5xc-salesdemos/oh-my-openagent/package.json
ls ~/.cache/opencode/node_modules/@ai-sdk/anthropic/package.json
ls ~/.cache/opencode/node_modules/@ai-sdk/openai-compatible/package.json
ls ~/.cache/opencode/node_modules/opencode-anthropic-auth/package.json

# Claude Code plugins
jq '.plugins | length' ~/.claude/plugins/installed_plugins.json  # Expected: 23
jq '.enabledPlugins | keys | length' ~/.claude/settings.json     # Expected: 23
jq '.model' ~/.claude/settings.json                               # Expected: "opus"
test -x ~/.claude/statusline.sh && echo "OK" || echo "MISSING"
jq '.mcpServers | has("chrome-devtools")' ~/.claude.json          # Expected: true

# Chrome
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

---

## Troubleshooting

### Plugin fails to load

```bash
rm -rf ~/.cache/opencode/node_modules
opencode
```

### chrome-devtools-mcp fails

```bash
rm -rf ~/.npm/_npx
npm cache clean --force
rm -rf ~/.cache/chrome-devtools-mcp/chrome-profile
ls "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

### LSP servers not detected

```bash
echo $PATH | tr ':' '\n' | grep homebrew
```

### Bun not found

```bash
which bun
bun --version
```

### Reset to Clean State

```bash
rm -rf ~/.config/opencode/node_modules ~/.config/opencode/bun.lock
rm -rf ~/.cache/opencode/node_modules ~/.cache/opencode/bun.lock
rm -rf ~/.claude/plugins ~/.claude/settings.json
rm -rf ~/.npm/_npx
rm -rf ~/.cache/chrome-devtools-mcp
```
