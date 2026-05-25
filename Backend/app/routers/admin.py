from __future__ import annotations

import secrets

from fastapi import APIRouter, Request, Response
from fastapi.responses import HTMLResponse, StreamingResponse

from app.admin_events import admin_events, event_payload
from app.auth import validate_admin_key
from app.config import settings
from app.routers.admin_logs_page import LOGS_PAGE_HTML

router = APIRouter()
_ADMIN_SESSION_COOKIE = "lifeorganize_admin_session"
_admin_sessions: set[str] = set()


def _admin_key_from(request: Request) -> str | None:
    return request.headers.get("x-admin-api-key")


def _require_admin(request: Request) -> None:
    session = request.cookies.get(_ADMIN_SESSION_COOKIE)
    if session in _admin_sessions:
        return
    validate_admin_key(_admin_key_from(request))


@router.post("/api/admin/logs/session")
async def create_logs_session(request: Request, response: Response) -> dict:
    validate_admin_key(_admin_key_from(request))
    session = secrets.token_urlsafe(32)
    _admin_sessions.add(session)
    response.set_cookie(
        _ADMIN_SESSION_COOKIE,
        session,
        httponly=True,
        samesite="strict",
        secure=False,
        max_age=60 * 60 * 8,
    )
    admin_events.emit(
        "info",
        "admin",
        "Admin logs session opened",
        source="logs_page",
    )
    return {"ok": True}


@router.get("/api/admin/logs")
async def recent_logs(request: Request, limit: int = 200) -> dict:
    _require_admin(request)
    bounded_limit = min(max(limit, 1), 500)
    return {"events": [event_payload(event) for event in admin_events.recent(bounded_limit)]}


@router.get("/api/admin/logs/stream")
async def stream_logs(request: Request, limit: int = 100) -> StreamingResponse:
    _require_admin(request)
    bounded_limit = min(max(limit, 1), 500)
    return StreamingResponse(
        admin_events.stream(bounded_limit),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/admin/logs", response_class=HTMLResponse)
async def logs_page() -> HTMLResponse:
    return HTMLResponse(
        LOGS_PAGE_HTML,
        headers={
            "content-security-policy": (
                "default-src 'self'; "
                "script-src 'unsafe-inline'; "
                "style-src 'unsafe-inline'; "
                "connect-src 'self'; "
                "img-src 'self' data:; "
                "frame-ancestors 'none'"
            )
        },
    )


@router.post("/api/admin/logs/mark")
async def mark_logs(request: Request) -> dict:
    _require_admin(request)
    body = await request.json()
    label = str(body.get("label") or "Manual marker")[:120]
    event = admin_events.emit(
        "info",
        "admin",
        label,
        source="logs_page",
        environment=settings.environment,
    )
    return {"event": event_payload(event)}


@router.post("/api/admin/logs/clear")
async def clear_logs(request: Request) -> dict:
    _require_admin(request)
    admin_events._events.clear()
    event = admin_events.emit(
        "info",
        "admin",
        "Log buffer cleared",
        source="logs_page",
    )
    return {"event": event_payload(event)}
