#!/bin/bash
set -e

echo "Running post-start checks..."

# Check AI provider mode
if [ -n "$LITELLM_BASE_URL" ]; then
  echo "  Mode: LiteLLM proxy"
  echo "  Endpoint: $LITELLM_BASE_URL"
  echo -n "  Checking endpoint... "
  if curl -sf --connect-timeout 5 -o /dev/null "${LITELLM_BASE_URL%/}" 2>/dev/null; then
    echo "reachable"
  else
    echo "not reachable (check VPN / network connectivity)"
  fi
  echo "  OPENAI_API_KEY: ${OPENAI_API_KEY:+set}${OPENAI_API_KEY:-NOT SET}"
  echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+set}${ANTHROPIC_API_KEY:-NOT SET} (for Claude Code)"
else
  echo "  WARNING: LiteLLM proxy is not configured"
  echo "           Set LITELLM_API_KEY and LITELLM_BASE_URL in .env"
  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "           Claude Code will still work via OAuth"
  fi
fi

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh kubectl helm terraform \
  pre-commit uv claude codex opencode crush xcsh prettier markdownlint-cli2 \
  actionlint act terraform-docs ansible black pylint yamllint yt-dlp \
  aws az pwsh devcontainer brew playwright pnpm redis-cli psql tirith \
  marksman terraform-ls taplo yaml-language-server bash-language-server \
  vscode-json-language-server mdx-language-server zig; do
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

# GitLab CLI authentication status
echo ""
echo "  GitLab CLI:"
if [ -n "${GITLAB_TOKEN:-}" ]; then
  if glab auth status 2>&1 | head -3 | sed 's/^/    /'; then
    :
  else
    echo "    WARNING: GITLAB_TOKEN is set but glab auth failed"
    echo "    Check that your token is valid and not expired"
  fi
else
  echo "    Not authenticated (GITLAB_TOKEN not set)"
  echo "    To enable: add GITLAB_TOKEN=glpat-... to .env"
fi

# Salesforce CLI authentication status
echo ""
echo "  Salesforce CLI:"
if sf org list auth 2>&1 | grep -q "Username"; then
  sf org list auth 2>&1 | head -5 | sed 's/^/    /'
else
  echo "    Not authenticated (SFDX_AUTH_URL not set)"
  echo "    To enable: add SFDX_AUTH_URL=force://... to .env"
fi

# Azure CLI authentication status
echo ""
echo "  Azure CLI:"
if az account show >/dev/null 2>&1; then
  az account show --query "{user:user.name, subscription:name, tenant:tenantId}" -o table 2>&1 | sed 's/^/    /'
else
  echo "    Not authenticated"
  echo "    To enable: add AZURE_CONFIG_BASE64 to .env (see .env.example)"
fi

echo ""
echo "Ready! Start coding in /workspace"
