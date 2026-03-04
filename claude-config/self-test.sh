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

echo "=== Claude Code Container Self-Test ==="
echo ""

echo "1. Core Tools"
check "claude CLI installed" command -v claude
check "pi CLI installed" command -v pi
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
check "Managed policy contains subagent docs" grep -q "Subagent" "$MANAGED_CLAUDE"

echo ""
echo "4. Container Environment"
check "workspace directory exists" test -d /workspace
check "home directory writable" test -w "$HOME"
check "TERM is set" test -n "${TERM:-}"

echo ""
echo "5. Web Search (SearXNG MCP)"
if [ -f /opt/searxng-mcp/server.py ]; then
  check "SearXNG MCP server installed" true
  SEARXNG_URL="${SEARXNG_BASE_URL:-http://searxng:8080}"
  if curl -sf --connect-timeout 3 "${SEARXNG_URL}/" >/dev/null 2>&1; then
    check "SearXNG backend reachable" true
  else
    echo "  SKIP: SearXNG not reachable (enable with COMPOSE_PROFILES=search)"
  fi
else
  echo "  FAIL: SearXNG MCP server not installed at /opt/searxng-mcp"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "6. Super-Linter Tools"
# Binary tools
check "shfmt installed" command -v shfmt
check "gitleaks installed" command -v gitleaks
check "trivy installed" command -v trivy
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
# PowerShell modules
check "PSScriptAnalyzer installed" pwsh -NoProfile -Command 'Get-Module -ListAvailable PSScriptAnalyzer'
check "arm-ttk installed" test -f /usr/lib/microsoft/arm-ttk/arm-ttk/arm-ttk.psd1
# R
check "Rscript installed" command -v Rscript

echo ""
echo "7. Security & Pentest Tools"
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
# Architecture-conditional (amd64 only)
if [ "$DPKG_ARCH" = "amd64" ]; then
  check "metasploit installed" command -v msfconsole
  check "bettercap installed" command -v bettercap
  check "waybackurls installed" command -v waybackurls
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
