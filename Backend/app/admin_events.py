from __future__ import annotations

import asyncio
import json
from collections import deque
from collections.abc import AsyncIterator
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from itertools import count
from typing import Any


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
            message=message,
            details={key: value for key, value in details.items() if value is not None},
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


admin_events = AdminEventBus()
