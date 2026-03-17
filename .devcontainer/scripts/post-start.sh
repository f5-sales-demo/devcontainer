#!/bin/bash
set -e

echo "Running post-start checks..."

# Detect LiteLLM direct mode
_litellm_direct=false
if [ -n "$ANTHROPIC_BASE_URL" ]; then
  case "$ANTHROPIC_BASE_URL" in
    http://localhost:*|http://localhost) ;;
    *) _litellm_direct=true ;;
  esac
fi

# Check AI provider mode
if [ "$_litellm_direct" = true ]; then
  echo "  Mode: LiteLLM direct (Anthropic-compatible proxy)"
  echo "  Endpoint: $ANTHROPIC_BASE_URL"
  echo -n "  Checking endpoint... "
  if curl -sf --connect-timeout 5 -o /dev/null "${ANTHROPIC_BASE_URL%/}" 2>/dev/null; then
    echo "reachable"
  else
    echo "not reachable (check VPN / network connectivity)"
  fi
  echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:+set}${ANTHROPIC_API_KEY:-NOT SET}"
elif [ -n "$OPENAI_API_KEY" ]; then
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
  echo -n "  Checking Tavily web search... "
  if [ -n "${TAVILY_API_KEY:-}" ]; then
    echo "API key configured"
  else
    echo "TAVILY_API_KEY not set (add to .env for web search)"
  fi
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
    echo "           If using an OpenAI-compatible provider, set OPENAI_API_KEY"
    echo "           and OPENAI_BASE_URL in .env to enable the built-in proxy."
  else
    echo "  ANTHROPIC_API_KEY is set"
  fi
fi
unset _litellm_direct

# Check installed tools
echo "  Installed tools:"
for cmd in node python3 go rustc javac git gh kubectl helm terraform \
  pre-commit uv claude opencode codex prettier markdownlint-cli2 \
  actionlint act terraform-docs ansible black pylint yamllint yt-dlp \
  aws az pwsh devcontainer brew playwright; do
  if command -v $cmd &>/dev/null; then
    ver=$($cmd --version 2>&1 | head -1 | sed 's/^[[:space:]]*//')
    printf "    %-20s %s\n" "$cmd" "$ver"
  fi
done

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
