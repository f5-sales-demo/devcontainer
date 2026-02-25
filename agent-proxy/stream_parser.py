"""Translate Claude Code stream-json output to OpenAI SSE format."""

import json
import time
import uuid

from config import config


def generate_id() -> str:
    """Generate a unique chat completion ID."""
    return f"chatcmpl-{uuid.uuid4().hex[:24]}"


def make_chunk(
    chunk_id: str, content: str, finish_reason: str | None = None
) -> str:
    """Create an OpenAI-compatible SSE chunk."""
    data = {
        "id": chunk_id,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": "claude-code",
        "choices": [
            {
                "index": 0,
                "delta": {"content": content} if content else {},
                "finish_reason": finish_reason,
            }
        ],
    }
    return f"data: {json.dumps(data)}\n\n"


def _format_tool_use(tool_name: str, tool_input: dict) -> str:
    """Format a tool use event as readable markdown."""
    verbosity = config.CLAUDE_STREAM_VERBOSITY

    if verbosity == "minimal":
        return f"\n🔧 *{tool_name}*\n"

    # Normal and verbose: show tool name + key params
    detail = ""
    if tool_name in ("Read", "Write", "Edit", "MultiEdit"):
        path = tool_input.get("file_path", tool_input.get("filePath", ""))
        detail = f" `{path}`" if path else ""
    elif tool_name == "Bash":
        command = tool_input.get("command", "")
        if verbosity == "verbose":
            detail = f"\n```bash\n{command}\n```"
        else:
            preview = command[:120] + ("..." if len(command) > 120 else "")
            detail = f" `{preview}`"
    elif tool_name in ("Glob", "Grep"):
        pattern = tool_input.get("pattern", tool_input.get("query", ""))
        detail = f" `{pattern}`" if pattern else ""

    return f"\n🔧 **{tool_name}**{detail}\n\n"


def _format_tool_result(content: str) -> str:
    """Format a tool result for display."""
    verbosity = config.CLAUDE_STREAM_VERBOSITY

    if verbosity == "minimal":
        return ""

    if not content:
        return "> ✅ Done\n\n"

    if verbosity == "verbose":
        return f"> **Result:**\n```\n{content}\n```\n\n"

    # Normal: truncate long output
    lines = content.split("\n")
    if len(lines) > 15:
        preview = "\n".join(lines[:12])
        remaining = len(lines) - 12
        return (
            f"> **Result** ({len(lines)} lines):\n"
            f"```\n{preview}\n... ({remaining} more lines)\n```\n\n"
        )
    if len(content) > 800:
        return f"> **Result:**\n```\n{content[:800]}...\n```\n\n"

    return f"> **Result:**\n```\n{content}\n```\n\n"


def parse_stream_event(line: str, chunk_id: str) -> str | None:
    """Parse a single stream-json line and return an SSE chunk or None."""
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return None

    event_type = event.get("type")

    if event_type == "assistant":
        message = event.get("message", {})
        content_blocks = message.get("content", [])

        chunks = []
        for block in content_blocks:
            if block.get("type") == "text":
                text = block.get("text", "")
                if text:
                    chunks.append(make_chunk(chunk_id, text))
            elif block.get("type") == "tool_use":
                tool_name = block.get("name", "unknown")
                tool_input = block.get("input", {})
                formatted = _format_tool_use(tool_name, tool_input)
                chunks.append(make_chunk(chunk_id, formatted))

        return "".join(chunks) if chunks else None

    if event_type == "tool":
        content = event.get("content", "")
        if isinstance(content, list):
            text_parts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text_parts.append(block.get("text", ""))
            content = "\n".join(text_parts)

        formatted = _format_tool_result(content)
        if formatted:
            return make_chunk(chunk_id, formatted)
        return None

    if event_type == "result":
        text = event.get("result", "")
        if text:
            return make_chunk(chunk_id, f"\n{text}")
        return None

    return None


def make_done_event() -> str:
    """Return the SSE stream termination event."""
    return "data: [DONE]\n\n"


def make_keepalive() -> str:
    """Return an SSE comment for keepalive."""
    return ": keepalive\n\n"


def parse_sync_response(output: str) -> dict:
    """Parse claude CLI json output into an OpenAI-compatible response."""
    try:
        data = json.loads(output)
    except json.JSONDecodeError:
        data = {"result": output}

    result_text = data.get("result", str(data))
    response_id = generate_id()

    return {
        "id": response_id,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": "claude-code",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": result_text},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
        },
    }
