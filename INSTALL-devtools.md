# CLI Development & Security Toolchain Setup

> **Audience**: Plain-language instructions for OpenCode or a human operator.
> **Platform**: macOS on Apple Silicon (arm64). Homebrew is already installed.
> **Prerequisite**: None — this guide is fully standalone.
>
> **Execution**: Steps are sequential and idempotent. Each includes inline VERIFY comments.

---

## Step 1 — Install Core CLI Utilities (Homebrew)

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

# Common CLI utilities
brew_install wget
brew_install curl
brew_install watch
brew_install coreutils
brew_install gnu-sed
brew_install tree
brew_install bat
brew_install eza
brew_install fzf
brew_install poppler
brew_install tmux

# Media tools
brew_install ffmpeg
brew_install yt-dlp
```

### Verify Step 1 — Core CLI Utilities

```bash
wget --version | head -1     # VERIFY: contains "GNU Wget"
curl --version | head -1     # VERIFY: starts with "curl"
watch --version              # VERIFY: contains "watch from procps"
gdate --version | head -1    # VERIFY: contains "GNU coreutils"
gsed --version | head -1     # VERIFY: contains "GNU sed"
tree --version               # VERIFY: contains "tree v"
bat --version                # VERIFY: starts with "bat"
eza --version                # VERIFY: starts with "v"
fzf --version                # VERIFY: a version number
pdftotext -v 2>&1 | head -1 # VERIFY: contains "pdftotext version"
tmux -V                      # VERIFY: tmux 3.x+
ffmpeg -version | head -1    # VERIFY: starts with "ffmpeg version"
yt-dlp --version             # VERIFY: a version string
```

---

## Step 2 — Install Development Runtimes

```bash
brew_install python
brew_install go
brew_install terraform
brew_install uv
```

### Verify Step 2 — Development Runtimes

```bash
python3 --version      # VERIFY: Python 3.x
go version             # VERIFY: go1.x
terraform --version    # VERIFY: Terraform v1.x
uv --version           # VERIFY: uv x.x
```

---

## Step 3 — Install Cloud CLIs

```bash
brew_install azure-cli
brew install --cask google-cloud-sdk
brew_install gogcli
```

### Verify Step 3 — Cloud CLIs

```bash
az --version 2>&1 | head -1   # VERIFY: contains "azure-cli"
gcloud --version | head -1     # VERIFY: contains "Google Cloud SDK"
gog --version                  # VERIFY: a version number
```

---

## Step 4 — Install Terraform Ecosystem

```bash
brew_install tflint
brew_install terraform-docs
```

### Verify Step 4 — Terraform Ecosystem

```bash
tflint --version         # VERIFY: "TFLint version"
terraform-docs --version # VERIFY: a version number
```

---

## Step 5 — Install Linters, Formatters, and Security Scanners

```bash
brew_install hadolint
brew_install actionlint
brew_install checkov
brew_install zizmor
brew_install pre-commit
```

### Verify Step 5 — Linters and Security Scanners

```bash
hadolint --version               # VERIFY: "Haskell Dockerfile Linter"
actionlint -version              # VERIFY: a version number
checkov --version                # VERIFY: a version number
zizmor --version                 # VERIFY: a version number
pre-commit --version             # VERIFY: "pre-commit 4" or higher
```

---

## Step 6 — Install Container Runtime (Podman)

Podman is the corporate-standard container runtime. Docker Desktop is **not permitted**.

```bash
brew_install podman
brew_install podman-compose
```

### 6.1 — Ensure Podman Machine is Running

```bash
if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
  echo "Podman machine is already running"
elif podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
  podman machine start
else
  podman machine init --memory 10240
  podman machine start
fi
```

### 6.2 — Create Docker Compatibility Shim

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/docker << 'EOF'
#!/bin/sh
exec /opt/homebrew/bin/podman "$@"
EOF
chmod +x ~/.local/bin/docker
```

### Verify Step 6 — Container Runtime

```bash
podman --version              # VERIFY: "podman version 5"
podman machine list           # VERIFY: shows "Currently running"
~/.local/bin/docker --version # VERIFY: "podman version 5"
pre-commit --version          # VERIFY: "pre-commit 4"
```

---

## Step 7 — Google CLI Auth (gogcli + gws)

This section handles bidirectional credential sync for `gogcli` (gog) and Google Workspace CLI (gws).

### 7.1 — gogcli

```bash
REPO_DIR="$(pwd)"
ENV_FILE="${REPO_DIR}/.env"

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
        ;;
      *) ;;
    esac
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

_GOG_AUTHED=false
if command -v gog >/dev/null 2>&1 && gog auth list --plain >/dev/null 2>&1; then
  _GOG_EMAIL="$(gog auth list --plain 2>/dev/null | head -1 | cut -f1)"
  [ -n "$_GOG_EMAIL" ] && _GOG_AUTHED=true
fi

if [ "$_GOG_AUTHED" = false ]; then
  _ENV_GOG_CREDS="$(env_get GOG_CREDENTIALS_JSON)"
  _ENV_GOG_TOKEN="$(env_get GOG_TOKEN_JSON)"
  if [ -n "$_ENV_GOG_CREDS" ] && [ -n "$_ENV_GOG_TOKEN" ]; then
    _GOG_TMP_CREDS="$(mktemp)"; _GOG_TMP_TOKEN="$(mktemp)"
    echo "$_ENV_GOG_CREDS" | base64 -d > "$_GOG_TMP_CREDS"
    echo "$_ENV_GOG_TOKEN" | base64 -d > "$_GOG_TMP_TOKEN"
    gog auth credentials set "$_GOG_TMP_CREDS" 2>&1 || true
    gog auth tokens import "$_GOG_TMP_TOKEN" 2>&1 || true
    rm -f "$_GOG_TMP_CREDS" "$_GOG_TMP_TOKEN"
    if gog auth list --plain >/dev/null 2>&1; then
      _GOG_EMAIL="$(gog auth list --plain 2>/dev/null | head -1 | cut -f1)"
      _GOG_AUTHED=true
    fi
  else
    echo "  Not authenticated. OPTIONAL: gog auth credentials set ~/Downloads/client_secret_*.json"
  fi
fi

if [ "$_GOG_AUTHED" = true ]; then
  env_set GOG_ACCOUNT "$_GOG_EMAIL"
  env_set GOG_KEYRING_PASSWORD "container"
  _GOG_CREDS_PATH="$HOME/Library/Application Support/gogcli/credentials.json"
  [ -f "$_GOG_CREDS_PATH" ] && env_set GOG_CREDENTIALS_JSON "$(base64 < "$_GOG_CREDS_PATH")"
  if [ -n "$_GOG_EMAIL" ]; then
    _GOG_TMP="$(mktemp)"
    if gog auth tokens export "$_GOG_EMAIL" --out "$_GOG_TMP" --overwrite >/dev/null 2>&1; then
      env_set GOG_TOKEN_JSON "$(base64 < "$_GOG_TMP")"
    fi
    rm -f "$_GOG_TMP"
  fi
fi
```

### 7.2 — Google Workspace CLI (gws)

```bash
if ! command -v gws >/dev/null 2>&1; then
  npm install -g @googleworkspace/cli
fi

_GWS_AUTHED=false
_GWS_CONFIG="$HOME/.config/gws"
if [ -f "$_GWS_CONFIG/client_secret.json" ] && [ -f "$_GWS_CONFIG/credentials.enc" ]; then
  _GWS_AUTHED=true
fi

if [ "$_GWS_AUTHED" = false ]; then
  _ENV_GWS_CS="$(env_get GWS_CLIENT_SECRET_JSON)"
  _ENV_GWS_KEY="$(env_get GWS_ENCRYPTION_KEY)"
  _ENV_GWS_ENC="$(env_get GWS_CREDENTIALS_ENC)"
  if [ -n "$_ENV_GWS_CS" ] && [ -n "$_ENV_GWS_KEY" ] && [ -n "$_ENV_GWS_ENC" ]; then
    mkdir -p "$_GWS_CONFIG"
    echo "$_ENV_GWS_CS" | base64 -d > "$_GWS_CONFIG/client_secret.json"
    echo "$_ENV_GWS_KEY" > "$_GWS_CONFIG/.encryption_key"
    echo "$_ENV_GWS_ENC" | base64 -d > "$_GWS_CONFIG/credentials.enc"
    chmod 600 "$_GWS_CONFIG/client_secret.json" "$_GWS_CONFIG/.encryption_key" "$_GWS_CONFIG/credentials.enc"
    _ENV_GWS_TC="$(env_get GWS_TOKEN_CACHE)"
    if [ -n "$_ENV_GWS_TC" ]; then
      echo "$_ENV_GWS_TC" | base64 -d > "$_GWS_CONFIG/token_cache.json"
      chmod 600 "$_GWS_CONFIG/token_cache.json"
    fi
    _GWS_AUTHED=true
  else
    echo "  Not authenticated. OPTIONAL: gws auth setup --login"
  fi
fi

if [ "$_GWS_AUTHED" = true ]; then
  [ -f "$_GWS_CONFIG/client_secret.json" ] && env_set GWS_CLIENT_SECRET_JSON "$(base64 < "$_GWS_CONFIG/client_secret.json")"
  if [ -f "$_GWS_CONFIG/credentials.enc" ]; then
    _GWS_KEY="$(security find-generic-password -s "gws-cli" -w 2>/dev/null || cat "$_GWS_CONFIG/.encryption_key" 2>/dev/null)"
    [ -n "$_GWS_KEY" ] && env_set GWS_ENCRYPTION_KEY "$_GWS_KEY"
    env_set GWS_CREDENTIALS_ENC "$(base64 < "$_GWS_CONFIG/credentials.enc")"
  fi
  [ -f "$_GWS_CONFIG/token_cache.json" ] && env_set GWS_TOKEN_CACHE "$(base64 < "$_GWS_CONFIG/token_cache.json")"
fi

# gogcli completions
bash configs/generate-gog-completions.sh > /opt/homebrew/share/zsh/site-functions/_gog 2>/dev/null \
  || \cp -f configs/_gog /opt/homebrew/share/zsh/site-functions/_gog
mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
\cp -f /opt/homebrew/share/zsh/site-functions/_gog \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions/_gog"
```

---

## Verify the Complete Toolchain

```bash
# CLI utilities
wget --version | head -1
curl --version | head -1
bat --version
eza --version
fzf --version
tmux -V

# Runtimes
python3 --version
go version
terraform --version

# Cloud CLIs
az --version 2>&1 | head -1
gcloud --version | head -1
gog --version

# Terraform ecosystem
tflint --version
terraform-docs --version

# Linters & scanners (CI-focused)
hadolint --version
actionlint -version
checkov --version
zizmor --version
pre-commit --version

# Containers
podman --version
podman machine list
~/.local/bin/docker --version
```

---

## Troubleshooting

### Homebrew install fails with "is not a directory"

```bash
rm -rf /opt/homebrew/Cellar/<pkg>
brew install <pkg>
brew link --overwrite <pkg>
```

### Reset Podman

```bash
podman machine stop
podman machine rm
podman machine init --memory 10240
podman machine start
```

### Remove Docker Shim

```bash
rm -f ~/.local/bin/docker
```
