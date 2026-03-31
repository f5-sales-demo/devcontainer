#!/bin/bash
# Start open-responses-server bridge for Codex CLI.
# Translates OpenAI Responses API (from codex) → Chat Completions (upstream proxy).
# Called from entrypoint.sh when LITELLM_API_KEY is set.
# OPENAI_BASE_URL_INTERNAL is set by the caller (entrypoint.sh).
exec otc start
