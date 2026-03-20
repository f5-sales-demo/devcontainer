#!/bin/bash
# ANTHROPIC_API_KEY is derived from LITELLM_API_KEY by entrypoint.sh.
# Fall back to LITELLM_API_KEY if called before entrypoint derivation runs.
echo "${ANTHROPIC_API_KEY:-${LITELLM_API_KEY:-}}"
