#!/bin/bash
# Claude Code Container Self-Test
set -euo pipefail

PASS=0
FAIL=0
WARN=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

warn() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  WARN: $desc"
    WARN=$((WARN + 1))
  fi
}

echo "=== Claude Code Container Self-Test ==="
echo ""

echo "1. Core Tools"
# Text browser (amd64 + arm64)
check "browsh installed" command -v browsh
check "firefox-esr installed" command -v firefox-esr
check "claude CLI installed" command -v claude
check "pi CLI installed" command -v pi
check "omp CLI installed" command -v omp
check "node installed" command -v node
check "python installed" command -v python3
check "git installed" command -v git
check "gh CLI installed" command -v gh

echo ""
echo "2. Claude Code Configuration"
check ".claude.json exists" test -f "$HOME/.claude.json"
check ".claude directory exists" test -d "$HOME/.claude"
check "settings.json exists" test -f "$HOME/.claude/settings.json"

echo ""
echo "3. Tool Awareness (Managed policy)"
MANAGED_CLAUDE="/etc/claude-code/CLAUDE.md"
check "$MANAGED_CLAUDE exists" test -f "$MANAGED_CLAUDE"
check "Managed policy contains PascalCase reference" grep -q "PascalCase" "$MANAGED_CLAUDE"
check "Managed policy contains tool table" grep -q "Read file contents" "$MANAGED_CLAUDE"
check "Managed policy contains Agent tool docs" grep -q "Agent" "$MANAGED_CLAUDE"

echo ""
echo "4. Container Environment"
check "workspace directory exists" test -d /workspace
check "home directory writable" test -w "$HOME"
check "TERM is set" test -n "${TERM:-}"

echo ""
echo "5. Super-Linter Tools"
# Binary tools
check "shfmt installed" command -v shfmt
check "gitleaks installed" command -v gitleaks
check "editorconfig-checker installed" command -v editorconfig-checker
check "golangci-lint installed" command -v golangci-lint
check "kubeconform installed" command -v kubeconform
check "clj-kondo installed" command -v clj-kondo
check "dotenv-linter installed" command -v dotenv-linter
check "scalafmt installed" command -v scalafmt
check "ktlint installed" command -v ktlint
check "protolint installed" command -v protolint
check "kustomize installed" command -v kustomize
check "goreleaser installed" command -v goreleaser
# Java JAR tools
check "checkstyle installed" command -v checkstyle
check "google-java-format installed" command -v google-java-format
# npm tools
check "eslint installed" command -v eslint
check "biome installed" command -v biome
check "jscpd installed" command -v jscpd
check "textlint installed" command -v textlint
check "stylelint installed" command -v stylelint
check "htmlhint installed" command -v htmlhint
check "spectral installed" command -v spectral
check "renovate installed" command -v renovate
check "markdownlint installed" command -v markdownlint
# pip tools
check "ruff installed" command -v ruff
check "flake8 installed" command -v flake8
check "mypy installed" command -v mypy
check "isort installed" command -v isort
check "ansible-lint installed" command -v ansible-lint
check "codespell installed" command -v codespell
check "sqlfluff installed" command -v sqlfluff
check "cpplint installed" command -v cpplint
# Language-specific
check "rubocop installed" command -v rubocop
check "phpcs installed" command -v phpcs
check "phpstan installed" command -v phpstan
check "psalm installed" command -v psalm
check "perlcritic installed" command -v perlcritic
check "luacheck installed" command -v luacheck
check "dart installed" command -v dart
check "dotnet installed" command -v dotnet
check "clang-format installed" command -v clang-format
check "xmllint installed" command -v xmllint
check "chktex installed" command -v chktex
check "clippy available" rustup component list --installed
check "rustfmt available" command -v rustfmt
# Additional formatters
check "cljfmt installed" command -v cljfmt
check "gleam installed" command -v gleam
check "pint installed" command -v pint
check "htmlbeautifier installed" command -v htmlbeautifier
check "standardrb installed" command -v standardrb
check "air installed" command -v air
check "dfmt installed" command -v dfmt
check "nixfmt installed" command -v nixfmt
check "ormolu installed" command -v ormolu
check "oxfmt installed" command -v oxfmt
# PowerShell modules
check "PSScriptAnalyzer installed" pwsh -NoProfile -Command 'Get-Module -ListAvailable PSScriptAnalyzer'
check "arm-ttk installed" test -f /usr/lib/microsoft/arm-ttk/arm-ttk/arm-ttk.psd1
# R
check "Rscript installed" command -v Rscript

echo ""
echo "6. Security & Pentest Tools"
DPKG_ARCH=$(dpkg --print-architecture)
# Network tools
check "tshark installed" command -v tshark
check "wireshark installed" command -v wireshark
check "masscan installed" command -v masscan
check "socat installed" command -v socat
check "hping3 installed" command -v hping3
check "iperf3 installed" command -v iperf3
# Web scanners
check "nikto installed" command -v nikto
check "sqlmap installed" command -v sqlmap
check "dirb installed" command -v dirb
check "whatweb installed" command -v whatweb
check "sslscan installed" command -v sslscan
# Password tools
check "hydra installed" command -v hydra
check "john installed" command -v john
check "hashcat installed" command -v hashcat
# RE / forensics
check "radare2 installed" command -v r2
check "gdb installed" command -v gdb
check "binwalk installed" command -v binwalk
check "exiftool installed" command -v exiftool
# Binary tools
check "nuclei installed" command -v nuclei
check "subfinder installed" command -v subfinder
check "httpx installed" command -v httpx
check "ffuf installed" command -v ffuf
check "gobuster installed" command -v gobuster
check "feroxbuster installed" command -v feroxbuster
check "dalfox installed" command -v dalfox
check "amass installed" command -v amass
check "gau installed" command -v gau
check "trufflehog installed" command -v trufflehog
check "grype installed" command -v grype
check "syft installed" command -v syft
check "kube-bench installed" command -v kube-bench
# Heavy tools
check "ZAP installed" test -x /opt/zaproxy/zap.sh
check "Ghidra installed" test -x /opt/ghidra/ghidraRun
check "SecLists installed" test -d /opt/seclists
check "testssl installed" command -v testssl
check "searchsploit installed" command -v searchsploit
# pip tools
check "scapy installed" python3 -c "import scapy"
check "mitmproxy installed" command -v mitmproxy
check "impacket installed" python3 -c "import impacket"
check "prowler installed" command -v prowler
# Ruby gems
check "wpscan installed" command -v wpscan
check "evil-winrm installed" command -v evil-winrm
# MITRE ATT&CK tools
check "mitreattack-python installed" python3 -c "import mitreattack"
check "ATT&CK Navigator installed" test -d /opt/attack-navigator
check "CALDERA installed" test -f /opt/caldera/server.py
# Architecture-conditional (amd64 only)
if [ "$DPKG_ARCH" = "amd64" ]; then
  check "metasploit installed" command -v msfconsole
  check "bettercap installed" command -v bettercap
  check "waybackurls installed" command -v waybackurls
fi

echo ""
echo "7. Claude Code Plugins"
check "enabledPlugins in settings.json" \
  jq -e '.enabledPlugins' "$HOME/.claude/settings.json"
ENABLED_COUNT=$(jq '.enabledPlugins | length' "$HOME/.claude/settings.json")
check "${ENABLED_COUNT} plugins configured (at least 1)" \
  test "$ENABLED_COUNT" -ge 1
check "FORCE_AUTOUPDATE_PLUGINS set" test "$FORCE_AUTOUPDATE_PLUGINS" = "true"
check "official marketplace cached" \
  test -d "$HOME/.claude/plugins/marketplaces/claude-plugins-official"
warn "official marketplace.json in cache (Anthropic may not include one)" \
  test -f "$HOME/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json"
check "f5xc marketplace cached" \
  test -d "$HOME/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace"
check "f5xc marketplace.json in cache" \
  test -f "$HOME/.claude/plugins/marketplaces/f5xc-salesdemos-marketplace/.claude-plugin/marketplace.json"
check "known_marketplaces.json exists" \
  test -f "$HOME/.claude/plugins/known_marketplaces.json"
check "installed_plugins.json exists" \
  test -f "$HOME/.claude/plugins/installed_plugins.json"
check "official plugin cache populated" \
  test -d "$HOME/.claude/plugins/cache/claude-plugins-official"
check "f5xc plugin cache populated" \
  test -d "$HOME/.claude/plugins/cache/f5xc-salesdemos-marketplace"
check "superpowers pre-installed" \
  test -d "$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
CACHED_COUNT=$(jq '.plugins | keys | length' "$HOME/.claude/plugins/installed_plugins.json")
check "all ${ENABLED_COUNT} enabled plugins cached (${CACHED_COUNT} found)" \
  test "$CACHED_COUNT" -eq "$ENABLED_COUNT"
check "frontend-slides skill installed" \
  test -f "$HOME/.claude/skills/frontend-slides/SKILL.md"
check "Codex skills symlink exists" \
  test -L "$HOME/.agents/skills"
check "Codex skills symlink resolves" \
  test -d "$HOME/.agents/skills"
check "Codex can see skills via symlink" \
  test -f "$HOME/.agents/skills/frontend-slides/SKILL.md"
CODEX_AGENT_COUNT=$(find "$HOME/.codex/agents" -name "*.toml" 2>/dev/null | wc -l)
check "Codex agents synced from CC plugins (${CODEX_AGENT_COUNT} found)" \
  test "$CODEX_AGENT_COUNT" -gt 0
check "Codex chrome-devtools MCP configured" \
  grep -q "chrome-devtools" "$HOME/.codex/config.toml"
# Check permissions by marketplace to pinpoint source (issue #648)
NON_EXEC_OFFICIAL=$(find "$HOME/.claude/plugins" \
  -path "*/claude-plugins-official/*" -name "*.sh" -type f \
  ! -perm -u+x 2>/dev/null | wc -l)
NON_EXEC_F5XC=$(find "$HOME/.claude/plugins" \
  -path "*/f5xc-salesdemos-marketplace/*" -name "*.sh" -type f \
  ! -perm -u+x 2>/dev/null | wc -l)
NON_EXEC_TOTAL=$((NON_EXEC_OFFICIAL + NON_EXEC_F5XC))
check "all plugin scripts executable (${NON_EXEC_TOTAL} non-exec: ${NON_EXEC_OFFICIAL} official, ${NON_EXEC_F5XC} f5xc)" \
  test "$NON_EXEC_TOTAL" -eq 0
check "neutralize-hooks.sh installed" test -x /opt/claude-config/neutralize-hooks.sh
check "SessionStart hook references neutralize-hooks.sh" \
  jq -e '.hooks.SessionStart[0].hooks[0].command | test("neutralize-hooks")' "$HOME/.claude/settings.json"
# PostToolUse hook removed — background daemon (inotifywait/polling) provides
# persistent coverage for mid-session plugin syncs. See devcontainer#654.
# Ensure marketplace symlinks are current before checking (handles race
# between Claude Code's runtime plugin sync and self-test execution)
/opt/claude-config/neutralize-hooks.sh 2>/dev/null || true
# Check that all enabled plugins have marketplace directories
MISSING_MKT_DIRS=0
while IFS= read -r KEY; do
  PNAME="${KEY%%@*}"
  MNAME="${KEY#*@}"
  MKT_DIR="$HOME/.claude/plugins/marketplaces/${MNAME}/plugins/${PNAME}"
  if [ -d "$MKT_DIR" ] || [ -L "$MKT_DIR" ]; then
    continue
  fi
  MISSING_MKT_DIRS=$((MISSING_MKT_DIRS + 1))
done < <(jq -r '.enabledPlugins | keys[]' "$HOME/.claude/settings.json" 2>/dev/null)
check "all enabled plugins have marketplace directories (${MISSING_MKT_DIRS} missing)" \
  test "$MISSING_MKT_DIRS" -eq 0
# Check for hooks from non-enabled plugins (cc#40013)
NON_ENABLED_HOOKS=0
for hf in "$HOME/.claude/plugins/marketplaces"/*/plugins/*/hooks/hooks.json; do
  [ -f "$hf" ] || continue
  PNAME=$(basename "$(dirname "$(dirname "$hf")")")
  MNAME=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$hf")")")")")
  KEY="${PNAME}@${MNAME}"
  if jq -e --arg k "$KEY" '.enabledPlugins[$k]' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    continue
  fi
  CONTENT=$(cat "$hf")
  if [ "$CONTENT" != "{}" ]; then
    NON_ENABLED_HOOKS=$((NON_ENABLED_HOOKS + 1))
  fi
done
check "no active hooks from non-enabled plugins (${NON_ENABLED_HOOKS} found)" \
  test "$NON_ENABLED_HOOKS" -eq 0
# Track upstream workarounds — the SessionStart hook and entrypoint chmod
# sweep exist for TWO upstream bugs.  The workaround can only be removed
# when BOTH are resolved:
#   - #648  (f5xc-salesdemos/devcontainer) — plugin syncs reset .sh perms  [CLOSED 2026-03-27]
#   - #40013 (anthropics/claude-code)       — hooks fire from ALL plugins   [still open]
CC_STATE=$(gh issue view 40013 --repo anthropics/claude-code \
  --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
if [ "$CC_STATE" = "CLOSED" ]; then
  warn "cc#40013 is closed — neutralize-hooks workaround in settings.json hooks and entrypoint.sh can be removed" false
elif [ "$CC_STATE" = "UNKNOWN" ]; then
  echo "  SKIP: could not check cc#40013 status (no GH_TOKEN or network)"
else
  echo "  INFO: cc#40013 still open — neutralize-hooks workaround still required"
fi

echo ""
echo "8. Chrome DevTools MCP"
check "Chrome symlink exists" test -L /opt/google/chrome/chrome
check "Chrome symlink target exists" test -e /opt/google/chrome/chrome
check "Chrome binary responds" /opt/google/chrome/chrome --version
check "chrome-browser.sh installed" test -f /usr/local/lib/chrome-browser.sh
check "Chrome remote debugging active" curl -sf --connect-timeout 2 http://localhost:9222/json/version
check "chrome-devtools in settings" grep -q '"chrome-devtools"' "$HOME/.claude.json"
MCP_MAIN_FILE=$(find /home/vscode/.npm/_npx -name 'chrome-devtools-mcp-main.js' \
  -path '*/bin/*' 2>/dev/null | head -1)
if [ -n "$MCP_MAIN_FILE" ]; then
  check "chrome-devtools pre-cached" true
else
  echo "  SKIP: chrome-devtools not yet cached (will download on first use)"
fi

echo ""
echo "9. iTerm2 Utilities"
check "imgcat installed" command -v imgcat
check "imgls installed" command -v imgls
check "it2dl installed" command -v it2dl
check "it2ul installed" command -v it2ul
check "it2copy installed" command -v it2copy
check "it2check installed" command -v it2check

echo ""
echo "10. Anti-Bot Detection Tools"
check "puppeteer installed (npm)" node -e "require('puppeteer')"
check "puppeteer-extra installed (npm)" node -e "require('puppeteer-extra')"
check "puppeteer-extra-plugin-stealth installed (npm)" node -e "require('puppeteer-extra-plugin-stealth')"
check "playwright-stealth installed (pip)" python3 -c "import playwright_stealth"
check "undetected-chromedriver installed (pip)" python3 -c "import undetected_chromedriver"
check "nodriver installed (pip)" python3 -c "import nodriver"
check "browserforge installed (pip)" python3 -c "import browserforge"

echo ""
echo "11. Resource Health"
DISK_PCT=$(df / --output=pcent | tail -1 | tr -d ' %')
warn "disk usage below 90% (currently ${DISK_PCT}%)" test "$DISK_PCT" -lt 90
MEM_AVAIL_MB=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
warn "available memory above 512MB (currently ${MEM_AVAIL_MB}MB)" test "$MEM_AVAIL_MB" -gt 512

echo ""
echo "12. claude-mem Plugin"
CMEM_ROOT=$(find "$HOME/.claude/plugins/cache/thedotmack/claude-mem" \
  -name "plugin.json" -path "*/.claude-plugin/*" -print -quit 2>/dev/null || true)
if [ -n "$CMEM_ROOT" ]; then
  CMEM_DIR=$(dirname "$(dirname "$CMEM_ROOT")")
  check "claude-mem plugin.json exists" test -f "$CMEM_ROOT"
  check "claude-mem hooks.json exists" test -f "$CMEM_DIR/hooks/hooks.json"
  check "claude-mem mcp-server.cjs exists" test -f "$CMEM_DIR/scripts/mcp-server.cjs"
  check "claude-mem worker-service.cjs exists" test -f "$CMEM_DIR/scripts/worker-service.cjs"
  check "claude-mem node_modules installed" test -d "$CMEM_DIR/node_modules"
  check "claude-mem enabled in settings" \
    jq -e '.enabledPlugins["claude-mem@thedotmack"]' "$HOME/.claude/settings.json"
  check "claude-mem in installed_plugins" \
    jq -e '.plugins["claude-mem@thedotmack"]' "$HOME/.claude/plugins/installed_plugins.json"
  NON_EXEC_CMEM=$(find "$CMEM_DIR" -name "*.sh" -type f ! -perm -u+x 2>/dev/null | wc -l)
  check "claude-mem scripts executable (${NON_EXEC_CMEM} non-exec)" \
    test "$NON_EXEC_CMEM" -eq 0
else
  echo "  SKIP: claude-mem not installed"
fi

echo ""
echo "13. Source Drift"
AUDIT_DIR="/tmp/devcontainer-audit"
if [ -d "$AUDIT_DIR" ]; then
  warn "managed CLAUDE.md matches source" \
    diff -q /etc/claude-code/CLAUDE.md "$AUDIT_DIR/claude-config/CLAUDE.md"
  warn "user CLAUDE.md matches source" \
    diff -q "$HOME/.claude/CLAUDE.md" "$AUDIT_DIR/claude-config/user-CLAUDE.md"
  warn "settings.json matches source (ignoring runtime state)" \
    diff -q "$HOME/.claude/settings.json" "$AUDIT_DIR/claude-config/settings.json"
else
  echo "  SKIP: source repo not cloned (run: gh repo clone f5xc-salesdemos/devcontainer $AUDIT_DIR)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $WARN warnings ==="

if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL — container configuration has errors"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "RESULT: WARN — container works but has warnings"
  exit 0
else
  echo "RESULT: PASS — container is fully configured"
  echo ""
  echo "MESSAGE TO HUMAN: All self-tests passed. Claude Code tool"
  echo "awareness is baked in and verified. You can safely destroy"
  echo "the old container — this one is properly configured."
  exit 0
fi
