#!/bin/bash
set -euo pipefail

# ============================================================
# Devcontainer smoke test — validates entrypoint rendering,
# env var derivation, daemon health, and tool availability.
#
# Usage:
#   ./tests/smoke-test.sh                             # registry image
#   ./tests/smoke-test.sh localhost/devcontainer:dev   # local build
#
# Two modes determined automatically:
#   LITELLM_API_KEY + LITELLM_BASE_URL set → full test (render + functional)
#   Not set → render-only test with dummy values (functional tests skipped)
# ============================================================

# Auto-detect container runtime
if command -v podman >/dev/null 2>&1; then
  RT=podman
elif command -v docker >/dev/null 2>&1; then
  RT=docker
else
  echo "Error: neither podman nor docker found" >&2
  exit 1
fi

IMAGE="${1:-ghcr.io/f5xc-salesdemos/devcontainer:latest}"
CONTAINER="smoke-test-$$"
COMPOSE_DIR=$(mktemp -d /tmp/smoke-XXXX)
PASS=0
FAIL=0
SKIP=0

# shellcheck disable=SC2329,SC2317
cleanup() {
  "$RT" stop "$CONTAINER" >/dev/null 2>&1 || true
  "$RT" rm "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$COMPOSE_DIR"
}
trap cleanup EXIT

ok() {
  PASS=$((PASS + 1))
  printf '  \033[32m✓\033[0m %s\n' "$*"
}
fail() {
  FAIL=$((FAIL + 1))
  printf '  \033[31m✗\033[0m %s\n' "$*"
}
# shellcheck disable=SC2329
skip() {
  SKIP=$((SKIP + 1))
  printf '  \033[33m-\033[0m %s\n' "$*"
}

assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    ok "$desc"
  else fail "$desc (expected='$expected' got='$actual')"; fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    ok "$desc"
  else fail "$desc (missing: '$needle')"; fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    fail "$desc (unexpected: '$needle')"
  else ok "$desc"; fi
}

assert_file() {
  local desc="$1" path="$2"
  if run test -f "$path"; then
    ok "$desc"
  else fail "$desc ($path missing)"; fi
}

assert_dir() {
  local desc="$1" path="$2"
  if run test -d "$path"; then
    ok "$desc"
  else fail "$desc ($path missing)"; fi
}

assert_bin() {
  local name="$1"
  if "$RT" exec -u vscode "$CONTAINER" zsh -c "command -v $name" >/dev/null 2>&1; then
    ok "$name"
  else
    fail "$name (not on PATH)"
  fi
}

assert_bin_ver() {
  local name="$1" cmd="$2" pattern="$3"
  local out
  out=$("$RT" exec -u vscode "$CONTAINER" zsh -c "$cmd" 2>&1 || true)
  if echo "$out" | grep -qi "$pattern"; then
    ok "$name"
  else fail "$name (version check failed)"; fi
}

run() { "$RT" exec -u vscode "$CONTAINER" "$@" 2>/dev/null; }
zrun() { "$RT" exec -u vscode "$CONTAINER" zsh -c "$*" 2>/dev/null; }

# ============================================================
# Determine test mode: live (real creds) or render-only (dummy)
# ============================================================
DUMMY_URL="https://litellm.example.com"
DUMMY_KEY="not-a-real-key" # gitleaks:allow

if [ -n "${LITELLM_API_KEY:-}" ] && [ -n "${LITELLM_BASE_URL:-}" ]; then
  TEST_URL="$LITELLM_BASE_URL"
  TEST_KEY="$LITELLM_API_KEY"
  LIVE_API=true
else
  TEST_URL="$DUMMY_URL"
  TEST_KEY="$DUMMY_KEY"
  LIVE_API=false
fi

# ============================================================
# Setup
# ============================================================
echo ""
echo "Devcontainer Smoke Test"
echo "======================="
echo "Image: $IMAGE"
if [ "$LIVE_API" = true ]; then
  echo "Mode:  LIVE (functional tests enabled)"
else
  echo "Mode:  RENDER-ONLY (functional tests skipped — no LITELLM credentials)"
fi
echo ""

cat >"$COMPOSE_DIR/docker-compose.yml" <<YAML
---
services:
  dev:
    image: $IMAGE
    pull_policy: never
    container_name: $CONTAINER
    hostname: $CONTAINER
    env_file:
      - path: .env
        required: false
    environment:
      - TZ=America/Toronto
      - GH_TOKEN=test-gh-token-12345
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETUID
      - SETGID
      - NET_RAW
      - NET_ADMIN
    mem_limit: 4g
    cpus: 2
    tmpfs:
      - /tmp:size=256m
    stdin_open: true
    tty: true
    init: true
    restart: "no"
    user: vscode
    entrypoint: ["/usr/local/bin/entrypoint.sh"]
    command: sleep infinity
YAML

cat >"$COMPOSE_DIR/.env" <<EOF
LITELLM_BASE_URL=$TEST_URL
LITELLM_API_KEY=$TEST_KEY
GIT_AUTHOR_NAME=Smoke Tester
GIT_AUTHOR_EMAIL=smoke@test.local
EOF

echo "Starting container ..."
"$RT" compose -f "$COMPOSE_DIR/docker-compose.yml" up -d >/dev/null 2>&1

echo "Waiting for entrypoint ..."
for _ in $(seq 1 90); do
  if run test -f /run/entrypoint-env.sh; then break; fi
  sleep 1
done
sleep 5

# ============================================================
# 1. Entrypoint env rendering (always runs — real or dummy values)
# ============================================================
echo ""
echo "Entrypoint env derivation"
echo "-------------------------"
ENV_FILE=$(run cat /run/entrypoint-env.sh)
assert_file "/run/entrypoint-env.sh exists" "/run/entrypoint-env.sh"
assert_contains "ANTHROPIC_API_KEY derived" "$ENV_FILE" "ANTHROPIC_API_KEY=$TEST_KEY"
assert_contains "ANTHROPIC_BASE_URL derived" "$ENV_FILE" "ANTHROPIC_BASE_URL=${TEST_URL}/anthropic"
assert_contains "ANTHROPIC_API_ENDPOINT derived" "$ENV_FILE" "ANTHROPIC_API_ENDPOINT=${TEST_URL}/anthropic"
assert_contains "OPENAI_API_KEY derived" "$ENV_FILE" "OPENAI_API_KEY=$TEST_KEY"
assert_contains "OPENAI_BASE_URL derived" "$ENV_FILE" "OPENAI_BASE_URL=${TEST_URL}/openai/v1"
assert_contains "ANTHROPIC_SMALL_FAST_MODEL" "$ENV_FILE" "claude-haiku-4-5"
assert_contains "ANTHROPIC_DEFAULT_HAIKU_MODEL" "$ENV_FILE" "claude-haiku-4-5"
assert_contains "ANTHROPIC_DEFAULT_SONNET_MODEL" "$ENV_FILE" "claude-sonnet-4-6"
assert_contains "ANTHROPIC_DEFAULT_OPUS_MODEL" "$ENV_FILE" "pd-claude-opus-4-7"
assert_contains "GIT_COMMITTER_NAME derived" "$ENV_FILE" "GIT_COMMITTER_NAME="
assert_contains "GIT_COMMITTER_EMAIL derived" "$ENV_FILE" "GIT_COMMITTER_EMAIL=smoke@test.local"

assert_contains "PI_DEFAULT_MODEL set" "$ENV_FILE" "PI_DEFAULT_MODEL=anthropic/claude-sonnet-4-6"
assert_contains "PI_SMOL_MODEL set" "$ENV_FILE" "PI_SMOL_MODEL=anthropic/claude-haiku-4-5"
assert_contains "PI_SLOW_MODEL set" "$ENV_FILE" "PI_SLOW_MODEL=anthropic/pd-claude-opus-4-7"
assert_contains "PI_PLAN_MODEL set" "$ENV_FILE" "PI_PLAN_MODEL=anthropic/pd-claude-opus-4-7"

# Verify shell inheritance of PI_* model vars (xcsh/pi/omp read these)
SHELL_PI_DEFAULT=$(zrun 'echo $PI_DEFAULT_MODEL')
assert_eq "zsh inherits PI_DEFAULT_MODEL" "$SHELL_PI_DEFAULT" "anthropic/claude-sonnet-4-6"
SHELL_PI_SMOL=$(zrun 'echo $PI_SMOL_MODEL')
assert_eq "zsh inherits PI_SMOL_MODEL" "$SHELL_PI_SMOL" "anthropic/claude-haiku-4-5"
SHELL_PI_SLOW=$(zrun 'echo $PI_SLOW_MODEL')
assert_eq "zsh inherits PI_SLOW_MODEL" "$SHELL_PI_SLOW" "anthropic/pd-claude-opus-4-7"

# ============================================================
# 2. Shell sourcing
# ============================================================
echo ""
echo "Shell env sourcing"
echo "------------------"
assert_file "/etc/zsh/zshenv" "/etc/zsh/zshenv"
assert_contains "System zshenv sources env" "$(run cat /etc/zsh/zshenv)" "entrypoint-env"
assert_file "vscode .zshenv" "/home/vscode/.zshenv"
assert_contains "User zshenv sources env" "$(run cat /home/vscode/.zshenv)" "entrypoint-env"
PROFILED=$(run readlink /etc/profile.d/99-entrypoint-env.sh)
assert_eq "profile.d symlink" "$PROFILED" "/run/entrypoint-env.sh"
SHELL_KEY=$(zrun 'echo $ANTHROPIC_API_KEY')
assert_eq "zsh -c inherits ANTHROPIC_API_KEY" "$SHELL_KEY" "$TEST_KEY"

# ============================================================
# 3. Environment
# ============================================================
echo ""
echo "Environment"
echo "-----------"
assert_eq "TZ=EDT" "$(run date +%Z)" "EDT"
assert_eq "GH_TOKEN" "$(run printenv GH_TOKEN)" "test-gh-token-12345"
assert_eq "git user.name" "$(run git config --global user.name)" "Smoke Tester"
assert_eq "git user.email" "$(run git config --global user.email)" "smoke@test.local"
assert_eq "HOME=/home/vscode" "$(run printenv HOME)" "/home/vscode"
assert_eq "user=vscode" "$(run whoami)" "vscode"

# ============================================================
# 4. AI assistant configs (always runs — validates rendering)
# ============================================================
echo ""
echo "AI assistant configs"
echo "--------------------"

# Claude Code
CS=$(run cat /home/vscode/.claude/settings.json)
assert_contains "Claude: sonnet model in settings" "$CS" "claude-sonnet-4-6"
assert_contains "Claude: opus model in settings" "$CS" "pd-claude-opus-4-7"
assert_contains "Claude: haiku model in settings" "$CS" "claude-haiku-4-5"
CJ=$(run cat /home/vscode/.claude.json)
assert_contains "Claude: auto-approve key" "$CJ" "customApiKeyResponses"

# Crush
CRUSH=$(run cat /home/vscode/.config/crush/crush.json)
assert_not_contains "Crush: no __CRUSH_BASE_URL__ placeholder" "$CRUSH" "__CRUSH_BASE_URL__"
assert_contains "Crush: base_url rendered" "$CRUSH" "${TEST_URL}/anthropic"
assert_contains "Crush: opus model" "$CRUSH" "pd-claude-opus-4-7"
assert_contains "Crush: auto-update disabled" "$CRUSH" "disable_provider_auto_update"

# Pi
PI=$(run cat /home/vscode/.pi/agent/settings.json)
assert_contains "Pi: provider=anthropic" "$PI" "anthropic"
assert_contains "Pi: model=opus" "$PI" "pd-claude-opus-4-7"

# OMP
OMP_S=$(run cat /home/vscode/.omp/agent/settings.json)
assert_contains "OMP: provider=anthropic" "$OMP_S" "anthropic"
assert_contains "OMP: model=opus" "$OMP_S" "pd-claude-opus-4-7"
OMP_C=$(run cat /home/vscode/.omp/agent/config.yml)
assert_contains "OMP: haiku role" "$OMP_C" "claude-haiku-4-5"
assert_contains "OMP: opus default role" "$OMP_C" "pd-claude-opus-4-7"

# Codex
CODEX=$(run cat /home/vscode/.codex/config.toml)
assert_contains "Codex: litellm provider" "$CODEX" 'model_provider = "litellm"'
assert_contains "Codex: base_url rendered" "$CODEX" "${TEST_URL}/openai/v1"
assert_contains "Codex: reads OPENAI_API_KEY" "$CODEX" 'env_key = "OPENAI_API_KEY"'

# OpenCode
OC=$(run cat /home/vscode/.config/opencode/opencode.json)
assert_contains "OpenCode: anthropic-proxy provider" "$OC" "anthropic-proxy"
assert_contains "OpenCode: opus model" "$OC" "pd-claude-opus-4-7"
assert_contains "OpenCode: sonnet model" "$OC" "claude-sonnet-4-6"
assert_contains "OpenCode: openai-proxy provider" "$OC" "openai-proxy"

# xcsh: models.json registered, models.yml written, modelRoles configured
assert_file "xcsh models.json" "/home/vscode/.xcsh/agent/models.json"
assert_file "xcsh models.yml" "/home/vscode/.xcsh/agent/models.yml"
XCSH_ROLES=$(zrun 'xcsh config get modelRoles 2>/dev/null')
assert_contains "xcsh: default role = sonnet" "$XCSH_ROLES" "claude-sonnet-4-6"
assert_contains "xcsh: slow role = opus" "$XCSH_ROLES" "pd-claude-opus-4-7"
assert_contains "xcsh: smol role = haiku" "$XCSH_ROLES" "claude-haiku-4-5"

# Maki: dynamic provider script staged, executable, base URL substituted
assert_file "maki provider script" "/home/vscode/.maki/providers/litellm"
MAKI_INFO=$(run /home/vscode/.maki/providers/litellm info)
assert_contains "Maki: info reports anthropic base" "$MAKI_INFO" '"base":"anthropic"'
MAKI_SCRIPT=$(run cat /home/vscode/.maki/providers/litellm)
assert_not_contains "Maki: no __MAKI_BASE_URL__ placeholder" "$MAKI_SCRIPT" "__MAKI_BASE_URL__"
assert_contains "Maki: base URL rendered" "$MAKI_SCRIPT" "${TEST_URL}/anthropic/v1/messages"
MAKI_MODELS=$(run /home/vscode/.maki/providers/litellm models)
assert_contains "Maki: opus in models list" "$MAKI_MODELS" "pd-claude-opus-4-7"

# ============================================================
# 5. AI assistant CLIs
# ============================================================
echo ""
echo "AI assistants"
echo "-------------"
assert_bin_ver "claude" "claude --version" "claude"
assert_bin_ver "crush" "crush --version" "crush"
assert_bin_ver "pi" "pi --version" "[0-9]"
assert_bin_ver "omp" "omp --version" "[0-9]"
assert_bin_ver "xcsh" "xcsh --version" "xcsh"
assert_bin_ver "opencode" "opencode --version" "."
assert_bin_ver "codex" "codex --version" "codex"
assert_bin_ver "maki" "maki --version" "maki"

# ============================================================
# 5b. AI functional tests (LIVE mode only)
# ============================================================
echo ""
echo "AI functional tests"
echo "-------------------"

if [ "$LIVE_API" = true ]; then
  PROMPT="reply with only the single word: hello"
  EXPECTED="hello"

  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "claude -p '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "claude prompt"
  else fail "claude prompt (got: $(echo "$_out" | head -1))"; fi

  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "pi -p '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "pi prompt"
  else fail "pi prompt (got: $(echo "$_out" | head -1))"; fi

  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "crush run '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "crush prompt"
  else fail "crush prompt (got: $(echo "$_out" | head -1))"; fi

  # xcsh: reads PI_DEFAULT_MODEL from env (no explicit --provider/--model needed)
  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "xcsh -p '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "xcsh prompt"
  else fail "xcsh prompt (got: $(echo "$_out" | head -1))"; fi

  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "mkdir -p /tmp/codex-test && cd /tmp/codex-test && git init -q 2>/dev/null; codex exec --skip-git-repo-check '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "codex prompt"
  else fail "codex prompt (got: $(echo "$_out" | head -1))"; fi

  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "cd /tmp && opencode run '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "opencode prompt"
  else fail "opencode prompt (got: $(echo "$_out" | head -1))"; fi

  # -m litellm/... forces the dynamic provider (~/.maki/providers/litellm);
  # without it, maki defaults to claude-opus-4-6 via the built-in anthropic
  # provider and hits api.anthropic.com, which our LiteLLM key can't auth to.
  _out=$(timeout 60 "$RT" exec -u vscode "$CONTAINER" zsh -c "maki -p --yolo --exit-on-done -m litellm/claude-sonnet-4-6 '$PROMPT'" 2>&1 || true)
  if echo "$_out" | grep -qi "$EXPECTED"; then
    ok "maki prompt"
  else fail "maki prompt (got: $(echo "$_out" | head -1))"; fi

  _out=$("$RT" exec -u vscode "$CONTAINER" zsh -c 'curl -sf "$ANTHROPIC_BASE_URL/v1/messages" -X POST -H "x-api-key: $ANTHROPIC_API_KEY" -H "content-type: application/json" -H "anthropic-version: 2023-06-01" -d "{\"model\":\"claude-sonnet-4-6\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"reply only: hello\"}]}" | jq -r ".content[0].text"' 2>&1 || true)
  if echo "$_out" | grep -qi "hello"; then
    ok "API direct curl"
  else fail "API direct curl (got: $(echo "$_out" | head -1))"; fi
else
  skip "claude prompt (no live API)"
  skip "pi prompt (no live API)"
  skip "crush prompt (no live API)"
  skip "xcsh prompt (no live API)"
  skip "codex prompt (no live API)"
  skip "opencode prompt (no live API)"
  skip "maki prompt (no live API)"
  skip "API direct curl (no live API)"
fi

# ============================================================
# 6. Daemons
# ============================================================
echo ""
echo "Daemons"
echo "-------"
REDIS=$(zrun 'redis-cli ping 2>/dev/null || echo FAIL')
assert_eq "Redis responds PONG" "$REDIS" "PONG"

PG=$(zrun 'pg_isready -h $HOME/.local/run/postgresql -q 2>/dev/null && echo OK || echo FAIL')
assert_eq "PostgreSQL ready" "$PG" "OK"

# rabbitmqctl refuses non-root/non-rabbitmq users; check AMQP port instead
RMQ=$(zrun 'timeout 2 bash -c "echo | nc -w1 localhost 5672" >/dev/null 2>&1 && echo OK || echo FAIL')
assert_eq "RabbitMQ listening on 5672" "$RMQ" "OK"

CRON=$(zrun 'crontab -l 2>/dev/null | grep -c nightly-update')
assert_eq "Cron: nightly-update scheduled" "$CRON" "1"

# ============================================================
# 7. Languages & runtimes
# ============================================================
echo ""
echo "Languages"
echo "---------"
assert_bin_ver "node" "node --version" "v"
assert_bin_ver "python3" "python3 --version" "Python"
assert_bin_ver "go" "go version" "go"
assert_bin_ver "rustc" "rustc --version" "rustc"
assert_bin_ver "cargo" "cargo --version" "cargo"
assert_bin_ver "java" "java -version 2>&1" "openjdk"
assert_bin_ver "ruby" "ruby --version" "ruby"
assert_bin_ver "php" "php --version" "PHP"
assert_bin_ver "perl" "perl --version" "perl"
assert_bin_ver "dart" "dart --version 2>&1" "Dart"
assert_bin_ver "dotnet" "dotnet --version" "."
assert_bin_ver "zig" "zig version" "."
assert_bin_ver "bun" "bun --version" "."
assert_bin_ver "lua" "lua5.4 -v 2>&1" "Lua"
assert_bin_ver "Rscript" "Rscript --version 2>&1" "."

# ============================================================
# 8. Cloud CLIs
# ============================================================
echo ""
echo "Cloud CLIs"
echo "----------"
assert_bin_ver "aws" "aws --version" "aws-cli"
assert_bin_ver "gcloud" "gcloud --version 2>&1 | head -1" "Google Cloud"
assert_bin_ver "az" "az --version 2>&1 | head -1" "azure-cli"
assert_bin_ver "kubectl" "kubectl version --client 2>&1" "Client"
assert_bin_ver "helm" "helm version 2>&1" "Version"
assert_bin_ver "terraform" "terraform --version" "Terraform"
assert_bin_ver "gh" "gh --version" "gh"
assert_bin_ver "ibmcloud" "ibmcloud version 2>&1" "ibmcloud"

# ============================================================
# 9. Package managers & build tools
# ============================================================
echo ""
echo "Build tools"
echo "-----------"
assert_bin_ver "npm" "npm --version" "."
assert_bin_ver "pnpm" "pnpm --version" "."
assert_bin_ver "pip" "pip --version" "pip"
assert_bin_ver "uv" "uv --version" "uv"
assert_bin_ver "mvn" "mvn --version 2>&1 | head -1" "Maven"
assert_bin_ver "gradle" "gradle --version 2>&1 | grep Gradle" "Gradle"
assert_bin_ver "gem" "gem --version" "."

# ============================================================
# 10. Linters & formatters
# ============================================================
echo ""
echo "Linters & formatters"
echo "--------------------"
for tool in \
  shellcheck shfmt black pylint ruff flake8 isort mypy yamllint \
  eslint prettier biome markdownlint-cli2 hadolint actionlint \
  tflint terraform-docs terragrunt ansible-lint cfn-lint codespell \
  golangci-lint editorconfig-checker gitleaks phpcs rubocop; do
  assert_bin "$tool"
done

# ============================================================
# 11. LSP servers
# ============================================================
echo ""
echo "LSP servers"
echo "-----------"
for lsp in \
  gopls rust-analyzer clangd taplo marksman \
  bash-language-server yaml-language-server \
  typescript-language-server pyright jdtls; do
  assert_bin "$lsp"
done

# ============================================================
# 12. Security & pentest tools
# ============================================================
echo ""
echo "Security tools"
echo "--------------"
for sec in \
  nmap tshark nuclei subfinder httpx ffuf gobuster feroxbuster \
  dalfox amass trufflehog grype syft testssl searchsploit \
  sherlock recon-ng spiderfoot hydra john sslscan nikto sqlmap; do
  assert_bin "$sec"
done

# ============================================================
# 13. Binary utilities
# ============================================================
echo ""
echo "Utilities"
echo "---------"
for util in \
  git jq yq fzf fd rg bat eza tree tmux htop nvim \
  ffmpeg qrencode dos2unix curl wget socat dig mtr; do
  assert_bin "$util"
done

# ============================================================
# 14. Browser & automation
# ============================================================
echo ""
echo "Browser & automation"
echo "--------------------"
assert_bin "playwright"
assert_dir "Playwright Chromium cache" "/home/vscode/.cache/ms-playwright"

# ============================================================
# 15. Key paths
# ============================================================
echo ""
echo "Key paths"
echo "---------"
assert_dir "/opt/zaproxy" "/opt/zaproxy"
assert_dir "/opt/ghidra" "/opt/ghidra"
assert_dir "/opt/seclists" "/opt/seclists"
assert_dir "/opt/firecrawl" "/opt/firecrawl"
assert_dir "Nerd fonts" "/usr/local/share/fonts/nerd-fonts"
assert_file "Build fingerprint" "/etc/devcontainer-version"
assert_file "Entrypoint" "/usr/local/bin/entrypoint.sh"
assert_dir "Oh-My-Zsh" "/home/vscode/.oh-my-zsh"
assert_dir "Powerlevel10k" "/home/vscode/.oh-my-zsh/custom/themes/powerlevel10k"
assert_dir "Claude plugins" "/home/vscode/.claude/plugins/marketplaces"

# ============================================================
# Summary
# ============================================================
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "=============================="
printf 'Results: \033[32m%d passed\033[0m' "$PASS"
[ "$FAIL" -gt 0 ] && printf ', \033[31m%d failed\033[0m' "$FAIL"
[ "$SKIP" -gt 0 ] && printf ', \033[33m%d skipped\033[0m' "$SKIP"
printf ' (%d total)\n' "$TOTAL"
echo "=============================="

exit "$FAIL"
