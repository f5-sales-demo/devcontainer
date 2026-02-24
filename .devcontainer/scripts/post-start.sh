#!/bin/bash
set -e

echo "Running post-start checks..."

# Check AI provider mode
if [ -n "$ANTHROPIC_BASE_URL" ]; then
  echo -n "  Checking AI proxy ($ANTHROPIC_BASE_URL)... "
  if curl -sf --connect-timeout 5 "$ANTHROPIC_BASE_URL/" >/dev/null 2>&1; then
    echo "reachable"
  else
    echo "not reachable (check proxy logs: docker compose logs proxy)"
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
    if [ -n "$OPENAI_API_KEY" ] || [ -n "$OPENAI_BASE_URL" ]; then
      echo "           It looks like you have proxy settings (OPENAI_API_KEY/OPENAI_BASE_URL)"
      echo "           but the proxy profile is not enabled. Add these to .env:"
      echo "             COMPOSE_PROFILES=proxy"
      echo "             ANTHROPIC_BASE_URL=http://proxy:8082"
    else
      echo "           Anthropic API keys start with 'sk-ant-'. Check your .env file."
    fi
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
