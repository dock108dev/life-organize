from __future__ import annotations

from collections.abc import Callable

from starlette.responses import JSONResponse

from app.config import settings


class RequestSizeLimitMiddleware:
    def __init__(self, app: Callable) -> None:
        self.app = app

    async def __call__(self, scope: dict, receive: Callable, send: Callable) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        max_bytes = settings.max_request_bytes
        headers = {name.lower(): value for name, value in scope.get("headers", [])}
        content_length = headers.get(b"content-length")
        if content_length is not None:
            try:
                if int(content_length.decode("ascii")) > max_bytes:
                    await _reject_request(scope, receive, send)
                    return
            except ValueError:
                pass

        if scope.get("method") not in {"POST", "PUT", "PATCH"}:
            await self.app(scope, receive, send)
            return

        # Valid write requests are buffered only up to MAX_REQUEST_BYTES before
        # replay. The current API accepts small JSON bodies, not file uploads.
        messages: list[dict] = []
        received_bytes = 0
        while True:
            message = await receive()
            messages.append(message)
            if message["type"] == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > max_bytes:
                    await _reject_request(scope, receive, send)
                    return
                if not message.get("more_body", False):
                    break
            else:
                break

        index = 0

        async def replay_receive() -> dict:
            nonlocal index
            if index < len(messages):
                message = messages[index]
                index += 1
                return message
            return {"type": "http.request", "body": b"", "more_body": False}

        await self.app(scope, replay_receive, send)


async def _reject_request(scope: dict, receive: Callable, send: Callable) -> None:
    response = JSONResponse(
        {"code": "request_too_large", "detail": "Request body is too large."},
        status_code=413,
    )
    await response(scope, receive, send)
