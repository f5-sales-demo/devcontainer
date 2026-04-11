#!/bin/bash
# LSP Coverage Test Suite (TDD)
#
# Verifies that all language server binaries are installed and all
# Claude Code LSP plugins are pre-enabled in settings.json.
# This prevents Claude Code's "Would you like to install this LSP plugin?"
# prompts from appearing during sessions.
#
# Run:  bash tests/test-lsp-coverage.sh
set -euo pipefail

PASS=0
FAIL=0
SETTINGS="/workspace/devcontainer/claude-config/settings.json"

test_binary() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  PASS: $name binary found at $(command -v "$cmd")"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name binary '$cmd' not found in PATH"
    FAIL=$((FAIL + 1))
  fi
}

test_plugin_enabled() {
  local plugin="$1"
  if grep -q "\"${plugin}\"" "$SETTINGS" 2>/dev/null; then
    echo "  PASS: Plugin '${plugin}' enabled in settings.json"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: Plugin '${plugin}' NOT in settings.json"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== LSP Binary Tests ==="
echo "--- Existing (13 servers) ---"
test_binary "TypeScript LSP"  "typescript-language-server"
test_binary "Pyright LSP"     "pyright-langserver"
test_binary "Go LSP"          "gopls"
test_binary "Rust LSP"        "rust-analyzer"
test_binary "Terraform LSP"   "terraform-ls"
test_binary "Bash LSP"        "bash-language-server"
test_binary "YAML LSP"        "yaml-language-server"
test_binary "JSON LSP"        "vscode-json-language-server"
test_binary "CSS LSP"         "vscode-css-language-server"
test_binary "HTML LSP"        "vscode-html-language-server"
test_binary "ESLint LSP"      "vscode-eslint-language-server"
test_binary "Markdown LSP"    "vscode-markdown-language-server"
test_binary "MDX LSP"         "mdx-language-server"
test_binary "Marksman"        "marksman"
test_binary "TOML LSP"        "taplo"

echo "--- New binaries (5 servers) ---"
test_binary "C/C++ LSP"       "clangd"
test_binary "Java LSP"        "jdtls"
test_binary "C# LSP"          "csharp-ls"
test_binary "Ruby LSP"        "ruby-lsp"
test_binary "PHP LSP"         "intelephense"

echo ""
echo "=== LSP Plugin Tests ==="
echo "--- Existing (13 plugins) ---"
test_plugin_enabled "typescript-lsp@claude-plugins-official"
test_plugin_enabled "pyright-lsp@claude-plugins-official"
test_plugin_enabled "gopls-lsp@claude-plugins-official"
test_plugin_enabled "rust-analyzer-lsp@claude-plugins-official"
test_plugin_enabled "terraform-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "json-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "bash-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "yaml-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "css-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "html-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "eslint-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "markdown-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "mdx-lsp@f5xc-salesdemos-marketplace"

echo "--- New plugins (6 plugins) ---"
test_plugin_enabled "toml-lsp@f5xc-salesdemos-marketplace"
test_plugin_enabled "clangd-lsp@claude-plugins-official"
test_plugin_enabled "jdtls-lsp@claude-plugins-official"
test_plugin_enabled "csharp-lsp@claude-plugins-official"
test_plugin_enabled "ruby-lsp@claude-plugins-official"
test_plugin_enabled "php-lsp@claude-plugins-official"

echo ""
echo "=== Results ==="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$FAIL"
