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

        headers = {name.lower(): value for name, value in scope.get("headers", [])}
        content_length = headers.get(b"content-length")
        if content_length is not None:
            try:
                if int(content_length.decode("ascii")) > settings.max_request_bytes:
                    response = JSONResponse(
                        {"code": "request_too_large", "detail": "Request body is too large."},
                        status_code=413,
                    )
                    await response(scope, receive, send)
                    return
            except ValueError:
                pass

        await self.app(scope, receive, send)
