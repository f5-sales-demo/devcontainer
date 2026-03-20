#!/bin/bash
# ANTHROPIC_API_KEY is derived from LITELLM_API_KEY by entrypoint.sh.
echo "${ANTHROPIC_API_KEY:-}"
