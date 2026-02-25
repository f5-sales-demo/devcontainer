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
    echo "not reachable (check /tmp/claude-proxy.log)"
  fi
  echo -n "  Checking upstream ($OPENAI_BASE_URL)... "
  if curl -sf --connect-timeout 5 -o /dev/null "$OPENAI_BASE_URL/models" \
    -H "Authorization: Bearer $OPENAI_API_KEY" 2>/dev/null; then
    echo "reachable"
  else
    echo "not reachable (check VPN / network connectivity)"
  fi
else
  echo "  Mode: direct API (no proxy)"
  if [ -z "$ANTHROPIC_API_KEY" ]; then
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
for cmd in node python3 go rustc javac git gh docker kubectl helm terraform \
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
