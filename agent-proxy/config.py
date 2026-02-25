"""Configuration from environment variables."""

import os


class Config:
    # Anthropic API settings (passed through to claude CLI)
    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    ANTHROPIC_BASE_URL: str = os.getenv("ANTHROPIC_BASE_URL", "")

    # Claude CLI settings
    CLAUDE_MODEL: str = os.getenv("CLAUDE_MODEL", "")
    CLAUDE_MAX_TURNS: int = int(os.getenv("CLAUDE_MAX_TURNS", "25"))
    CLAUDE_WORKSPACE_DIR: str = os.getenv("CLAUDE_WORKSPACE_DIR", "/workspace")
    CLAUDE_ALLOWED_TOOLS: str = os.getenv("CLAUDE_ALLOWED_TOOLS", "")

    # Proxy settings
    AGENT_PROXY_PORT: int = int(os.getenv("AGENT_PROXY_PORT", "8082"))
    AGENT_PROXY_AUTH_TOKEN: str = os.getenv("AGENT_PROXY_AUTH_TOKEN", "")

    # Stream verbosity: minimal, normal, verbose
    CLAUDE_STREAM_VERBOSITY: str = os.getenv("CLAUDE_STREAM_VERBOSITY", "normal")


config = Config()
