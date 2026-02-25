"""FastAPI server exposing OpenAI-compatible API wrapping Claude Code CLI."""

import asyncio
import json
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel

from claude_runner import run_claude_stream, run_claude_sync
from config import config
from stream_parser import (
    generate_id,
    make_done_event,
    make_keepalive,
    parse_stream_event,
    parse_sync_response,
)

app = FastAPI(title="Claude Agent Proxy", version="1.0.0")


# ---------------------------------------------------------------------------
# Auth middleware
# ---------------------------------------------------------------------------
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    if config.AGENT_PROXY_AUTH_TOKEN:
        if request.url.path in ("/health", "/docs", "/openapi.json"):
            return await call_next(request)
        auth = request.headers.get("Authorization", "")
        token = auth.removeprefix("Bearer ").strip()
        if token != config.AGENT_PROXY_AUTH_TOKEN:
            return JSONResponse(status_code=401, content={"error": "Unauthorized"})
    return await call_next(request)


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------
class Message(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    model: str = "claude-code"
    messages: list[Message]
    stream: bool = False
    temperature: float | None = None
    max_tokens: int | None = None


# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------
def _build_prompt(messages: list[Message]) -> str:
    """Convert OpenAI message list into a single prompt for claude -p."""
    system_parts: list[str] = []
    history: list[tuple[str, str]] = []

    for msg in messages:
        if msg.role == "system":
            system_parts.append(msg.content)
        else:
            history.append((msg.role, msg.content))

    parts: list[str] = []

    if system_parts:
        parts.append("System instructions: " + "\n".join(system_parts))

    if len(history) > 1:
        parts.append("\nPrevious conversation for context:")
        parts.append("<conversation_history>")
        for role, content in history[:-1]:
            label = "Human" if role == "user" else "Assistant"
            parts.append(f"{label}: {content}")
        parts.append("</conversation_history>\n")

    # Latest message
    if history:
        parts.append(history[-1][1])
    elif system_parts:
        parts.append("Please respond to the system instructions above.")

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "claude-code",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "anthropic",
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request, body: ChatCompletionRequest):
    prompt = _build_prompt(body.messages)

    if body.stream:
        return StreamingResponse(
            _stream_response(request, prompt),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    output = await run_claude_sync(prompt)
    return parse_sync_response(output)


async def _stream_response(request: Request, prompt: str):
    """Stream SSE events from claude CLI output."""
    chunk_id = generate_id()
    last_event_time = time.monotonic()
    keepalive_interval = 15

    try:
        async for line in run_claude_stream(prompt):
            if await request.is_disconnected():
                break

            chunk = parse_stream_event(line, chunk_id)
            if chunk:
                yield chunk
                last_event_time = time.monotonic()
            elif time.monotonic() - last_event_time > keepalive_interval:
                yield make_keepalive()
                last_event_time = time.monotonic()

    except asyncio.CancelledError:
        pass

    # Send final stop chunk and DONE
    stop_data = {
        "id": chunk_id,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": "claude-code",
        "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
    }
    yield f"data: {json.dumps(stop_data)}\n\n"
    yield make_done_event()
