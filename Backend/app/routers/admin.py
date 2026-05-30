from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Request, Response
from fastapi.responses import HTMLResponse, StreamingResponse

from app.admin_events import admin_events, event_payload
from app.auth import validate_admin_key
from app.config import settings
from app.routers.admin_logs_page import LOGS_PAGE_HTML

router = APIRouter()
_ADMIN_SESSION_COOKIE = "lifeorganize_admin_session"
_ADMIN_SESSION_TTL = timedelta(hours=8)
_MAX_ADMIN_SESSIONS = 32


@dataclass
class AdminSession:
    created_at: datetime
    expires_at: datetime


# Admin log sessions are intentionally process-local. The production Compose
# service runs one API process, so shared session storage is not required today.
_admin_sessions: dict[str, AdminSession] = {}


def _admin_key_from(request: Request) -> str | None:
    return request.headers.get("x-admin-api-key")


def _require_admin(request: Request) -> None:
    session = request.cookies.get(_ADMIN_SESSION_COOKIE)
    if _is_active_session(session):
        return
    validate_admin_key(_admin_key_from(request))


def _is_active_session(session: str | None) -> bool:
    if not session:
        return False
    _prune_expired_sessions()
    return session in _admin_sessions


def _prune_expired_sessions(now: datetime | None = None) -> None:
    current_time = now or datetime.now(UTC)
    expired = [
        session_id
        for session_id, session in _admin_sessions.items()
        if session.expires_at <= current_time
    ]
    for session_id in expired:
        _admin_sessions.pop(session_id, None)


def _store_admin_session(session_id: str) -> None:
    now = datetime.now(UTC)
    _prune_expired_sessions(now)
    _admin_sessions[session_id] = AdminSession(created_at=now, expires_at=now + _ADMIN_SESSION_TTL)
    while len(_admin_sessions) > _MAX_ADMIN_SESSIONS:
        oldest_session_id = min(_admin_sessions, key=lambda item: _admin_sessions[item].created_at)
        _admin_sessions.pop(oldest_session_id, None)


@router.post("/api/admin/logs/session")
async def create_logs_session(request: Request, response: Response) -> dict:
    validate_admin_key(_admin_key_from(request))
    session = secrets.token_urlsafe(32)
    _store_admin_session(session)
    response.set_cookie(
        _ADMIN_SESSION_COOKIE,
        session,
        httponly=True,
        samesite="strict",
        secure=settings.environment in {"production", "staging"},
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
            ),
            "Cache-Control": "no-store",
            "X-Robots-Tag": "noindex, nofollow",
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


@router.post("/api/admin/logs/logout")
async def logout_logs(request: Request, response: Response) -> dict:
    session = request.cookies.get(_ADMIN_SESSION_COOKIE)
    _require_admin(request)
    if session:
        _admin_sessions.pop(session, None)
    response.delete_cookie(
        _ADMIN_SESSION_COOKIE,
        secure=settings.environment in {"production", "staging"},
        samesite="strict",
    )
    admin_events.emit(
        "info",
        "admin",
        "Admin logs session closed",
        source="logs_page",
    )
    return {"ok": True}
