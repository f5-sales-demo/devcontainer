"""Spawn and manage claude CLI subprocess."""

import asyncio
import os
from collections.abc import AsyncIterator

from config import config


def _build_command(prompt: str) -> list[str]:
    """Build the claude CLI command arguments."""
    cmd = [
        "claude",
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--max-turns",
        str(config.CLAUDE_MAX_TURNS),
        "--dangerously-skip-permissions",
    ]

    if config.CLAUDE_MODEL:
        cmd.extend(["--model", config.CLAUDE_MODEL])

    if config.CLAUDE_ALLOWED_TOOLS:
        cmd.extend(["--allowedTools", config.CLAUDE_ALLOWED_TOOLS])

    return cmd


def _build_env() -> dict[str, str]:
    """Build environment for the subprocess.

    Passes through all ANTHROPIC_* vars and unsets CLAUDECODE
    to prevent nested session detection error.
    """
    env = os.environ.copy()

    # Critical: unset CLAUDECODE to avoid
    # "cannot be launched inside another Claude Code session" error
    env.pop("CLAUDECODE", None)

    # Ensure API settings are passed through
    if config.ANTHROPIC_API_KEY:
        env["ANTHROPIC_API_KEY"] = config.ANTHROPIC_API_KEY
    if config.ANTHROPIC_BASE_URL:
        env["ANTHROPIC_BASE_URL"] = config.ANTHROPIC_BASE_URL

    return env


async def run_claude_stream(prompt: str) -> AsyncIterator[str]:
    """Spawn claude CLI and yield stdout lines as they arrive."""
    cmd = _build_command(prompt)
    env = _build_env()

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=config.CLAUDE_WORKSPACE_DIR,
        env=env,
    )

    try:
        async for line in process.stdout:
            decoded = line.decode("utf-8", errors="replace").strip()
            if decoded:
                yield decoded
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()


async def run_claude_sync(prompt: str) -> str:
    """Spawn claude CLI and return complete output."""
    cmd = _build_command(prompt)
    # For sync mode, use json output instead of stream-json
    cmd[cmd.index("stream-json")] = "json"
    env = _build_env()

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=config.CLAUDE_WORKSPACE_DIR,
        env=env,
    )

    stdout, stderr = await asyncio.wait_for(
        process.communicate(),
        timeout=300,  # 5 minute timeout for non-streaming
    )

    return stdout.decode("utf-8", errors="replace")
