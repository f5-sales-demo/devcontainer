#!/bin/bash
set -e

echo "Running post-start checks..."

# Check AI provider mode
if [ -n "$OPENAI_API_KEY" ]; then
  echo "  Mode: proxy (OpenAI-compatible)"
  echo -n "  Checking proxy (http://localhost:8082)... "
  if curl -sf --connect-timeout 5 "http://localhost:8082/" >/dev/null 2>&1; then
    echo "reachable"
  else
    echo "not reachable (check ~/.local/share/claude-proxy/proxy.log)"
  fi
  echo -n "  Checking Responses API (Codex)... "
  if curl -sf --connect-timeout 5 -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:8082/responses" \
    -H "Content-Type: application/json" \
    -d '{"model":"test","input":"ping","stream":false}' 2>/dev/null | grep -qE '^(200|4[0-9]{2}|500)$'; then
    echo "available"
  else
    echo "not available (proxy may need Responses API endpoints)"
  fi
  echo -n "  Checking upstream ($_UPSTREAM_OPENAI_BASE_URL)... "
  if curl -sf --connect-timeout 5 -o /dev/null "${_UPSTREAM_OPENAI_BASE_URL:-${OPENAI_BASE_URL}}/models" \
    -H "Authorization: Bearer $OPENAI_API_KEY" 2>/dev/null; then
    echo "reachable"
  else
    echo "not reachable (check VPN / network connectivity)"
  fi
  SEARXNG_URL="${SEARXNG_BASE_URL:-http://searxng:8080}"
  echo -n "  Checking SearXNG MCP ($SEARXNG_URL)... "
  if [ -f /opt/searxng-mcp/server.py ]; then
    if curl -sf --connect-timeout 3 "${SEARXNG_URL}/" >/dev/null 2>&1; then
      echo "MCP installed, backend reachable"
    else
      echo "MCP installed, backend not reachable (enable with COMPOSE_PROFILES=search)"
    fi
  else
    echo "MCP server not installed"
  fi
else
  echo "  Mode: direct API (no proxy)"
  if [ -n "$CLAUDE_OAUTH_TOKEN" ]; then
    echo "  Auth: Claude Max (OAuth)"
    if [ -f "$HOME/.claude/.credentials.json" ]; then
      echo "  Credentials file: present (~/.claude/.credentials.json)"
    else
      echo "  WARNING: CLAUDE_OAUTH_TOKEN is set but credentials file is missing"
      echo "           The entrypoint should have created it — check entrypoint.sh"
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
    echo "           If using an OpenAI-compatible provider, set OPENAI_API_KEY"
    echo "           and OPENAI_BASE_URL in .env to enable the built-in proxy."
  else
    echo "  ANTHROPIC_API_KEY is set"
  fi
fi

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh kubectl helm terraform \
  pre-commit uv claude opencode codex openclaw prettier markdownlint-cli2 \
  actionlint act terraform-docs ansible black pylint yamllint yt-dlp \
  aws az pwsh devcontainer brew playwright; do
  if command -v $cmd &>/dev/null; then
    ver=$($cmd --version 2>&1 | head -1 | sed 's/^[[:space:]]*//')
    printf "    %-20s %s\n" "$cmd" "$ver"
  fi
done

echo ""
echo "Ready! Start coding in /workspace"
