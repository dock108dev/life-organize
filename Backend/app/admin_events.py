from __future__ import annotations

import asyncio
import json
from collections import deque
from collections.abc import AsyncIterator
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from itertools import count
from typing import Any

_BLOCKED_DETAIL_KEYS = {
    "apikey",
    "authorization",
    "cookie",
    "devicetoken",
    "input",
    "outputtext",
    "payload",
    "prompt",
    "rawresponse",
    "rawresponsetext",
    "requestjson",
    "response",
    "responsebody",
    "session",
    "text",
    "tokenhash",
    "usertext",
}
_MAX_DETAIL_DEPTH = 3
_MAX_DETAIL_STRING_LENGTH = 300
_MAX_MESSAGE_LENGTH = 500
_TRUNCATION_SUFFIX = "...[truncated]"


@dataclass(frozen=True)
class AdminEvent:
    id: int
    timestamp: str
    level: str
    category: str
    message: str
    details: dict[str, Any]


class AdminEventBus:
    def __init__(self, maxlen: int = 500) -> None:
        self._events: deque[AdminEvent] = deque(maxlen=maxlen)
        self._subscribers: set[asyncio.Queue[AdminEvent]] = set()
        self._ids = count(1)

    def emit(
        self,
        level: str,
        category: str,
        message: str,
        **details: Any,
    ) -> AdminEvent:
        event = AdminEvent(
            id=next(self._ids),
            timestamp=datetime.now(UTC).isoformat(timespec="milliseconds"),
            level=level,
            category=category,
            message=_truncate(str(message), _MAX_MESSAGE_LENGTH),
            details=_sanitize_details(details),
        )
        self._events.append(event)
        for subscriber in tuple(self._subscribers):
            subscriber.put_nowait(event)
        return event

    def recent(self, limit: int = 200) -> list[AdminEvent]:
        return list(self._events)[-limit:]

    async def stream(self, limit: int = 100) -> AsyncIterator[str]:
        for event in self.recent(limit):
            yield sse_event(event)

        queue: asyncio.Queue[AdminEvent] = asyncio.Queue(maxsize=100)
        self._subscribers.add(queue)
        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=15)
                    yield sse_event(event)
                except TimeoutError:
                    yield ": keepalive\n\n"
        finally:
            self._subscribers.discard(queue)


def event_payload(event: AdminEvent) -> dict[str, Any]:
    return asdict(event)


def sse_event(event: AdminEvent) -> str:
    return f"id: {event.id}\nevent: log\ndata: {json.dumps(event_payload(event))}\n\n"


def _sanitize_details(details: dict[str, Any]) -> dict[str, Any]:
    sanitized: dict[str, Any] = {}
    for key, value in details.items():
        if value is None:
            continue
        if _normalized_key(key) in _BLOCKED_DETAIL_KEYS:
            sanitized[key] = "[redacted]"
            continue
        sanitized[key] = _sanitize_value(value, depth=0)
    return sanitized


def _sanitize_value(value: Any, *, depth: int) -> Any:
    if value is None or isinstance(value, bool | int | float):
        return value
    if isinstance(value, str):
        return _truncate(value, _MAX_DETAIL_STRING_LENGTH)
    if depth >= _MAX_DETAIL_DEPTH:
        return _truncate(str(value), _MAX_DETAIL_STRING_LENGTH)
    if isinstance(value, dict):
        return {
            str(key): (
                "[redacted]"
                if _normalized_key(str(key)) in _BLOCKED_DETAIL_KEYS
                else _sanitize_value(item, depth=depth + 1)
            )
            for key, item in value.items()
            if item is not None
        }
    if isinstance(value, list | tuple):
        return [_sanitize_value(item, depth=depth + 1) for item in value]
    return _truncate(str(value), _MAX_DETAIL_STRING_LENGTH)


def _normalized_key(key: str) -> str:
    return "".join(character for character in key.lower() if character.isalnum())


def _truncate(value: str, max_length: int) -> str:
    if len(value) <= max_length:
        return value
    return f"{value[: max_length - len(_TRUNCATION_SUFFIX)]}{_TRUNCATION_SUFFIX}"


admin_events = AdminEventBus()
