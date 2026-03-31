#!/bin/bash
set -e

echo "Running post-start checks..."

# Check AI provider mode
if [ -n "$ANTHROPIC_BASE_URL" ]; then
  echo "  Mode: LiteLLM direct (Anthropic-compatible endpoint)"
  echo "  Endpoint: $ANTHROPIC_BASE_URL"
  echo -n "  Checking endpoint... "
  if curl -sf --connect-timeout 5 -o /dev/null "${ANTHROPIC_BASE_URL%/}" 2>/dev/null; then
    echo "reachable"
  else
    echo "not reachable (check VPN / network connectivity)"
  fi
  echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+set}${ANTHROPIC_API_KEY:-NOT SET}"
else
  echo "  Mode: direct API (no proxy)"
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "  Auth: Claude Max (OAuth via CLAUDE_CODE_OAUTH_TOKEN)"
    if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
      echo "  opencode: OAuth credentials seeded"
    fi
  elif [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "  WARNING: ANTHROPIC_API_KEY is not set — AI tools will not work"
    echo "           Set your key in .env: ANTHROPIC_API_KEY=sk-ant-..."
    echo "           Get a key at https://console.anthropic.com/"
  elif [[ "$ANTHROPIC_API_KEY" == *"your-api-key"* ]] ||
    [[ "$ANTHROPIC_API_KEY" == *"placeholder"* ]] ||
    [[ "$ANTHROPIC_API_KEY" == *"change-me"* ]]; then
    echo "  WARNING: ANTHROPIC_API_KEY appears to be a placeholder"
    echo "           Replace the value in .env with your real API key"
    echo "           Get a key at https://console.anthropic.com/"
  elif [[ "$ANTHROPIC_API_KEY" != sk-ant-* ]]; then
    echo "  WARNING: ANTHROPIC_API_KEY does not look like an Anthropic key"
    echo "           If using an Anthropic-compatible proxy, set ANTHROPIC_BASE_URL"
    echo "           in .env to route Claude Code directly to it."
  else
    echo "  ANTHROPIC_API_KEY is set"
  fi
fi

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh kubectl helm terraform \
  pre-commit uv claude opencode codex prettier markdownlint-cli2 \
  actionlint act terraform-docs ansible black pylint yamllint yt-dlp \
  aws az pwsh devcontainer brew playwright pnpm redis-cli psql tirith \
  marksman terraform-ls taplo yaml-language-server bash-language-server \
  vscode-json-language-server mdx-language-server; do
  if command -v $cmd &>/dev/null; then
    ver=$($cmd --version 2>&1 | head -1 | sed 's/^[[:space:]]*//')
    printf "    %-20s %s\n" "$cmd" "$ver"
  fi
done

# OSINT tools check
echo ""
echo "  OSINT tools:"
for cmd in sherlock maigret holehe h8mail dnsrecon subfinder amass httpx \
  nuclei nmap masscan exiftool whois dig checkip goblob bucketloot \
  iocextract oletools apkleaks frida waybackpack searchsploit \
  recon-ng spiderfoot; do
  if command -v $cmd &>/dev/null; then
    printf "    %-20s %s\n" "$cmd" "OK"
  fi
done

# Firecrawl health check
if curl -sf http://localhost:3002/v1/scrape -X POST -H "Content-Type: application/json" \
  -d '{"url":"https://example.com","formats":["markdown"]}' >/dev/null 2>&1; then
  echo ""
  echo "  Firecrawl: healthy (port 3002)"
fi

# GitHub CLI authentication status
echo ""
echo "  GitHub CLI:"
if [ -n "$GH_TOKEN" ]; then
  if gh auth status 2>&1 | head -3 | sed 's/^/    /'; then
    :
  else
    echo "    WARNING: GH_TOKEN is set but gh auth failed"
    echo "    Check that your token is valid and not expired"
  fi
else
  echo "    Not authenticated (GH_TOKEN not set)"
  echo "    To enable: add GH_TOKEN=ghp_... to .env"
  echo "    Create a token at https://github.com/settings/tokens"
fi

echo ""
echo "Ready! Start coding in /workspace"
