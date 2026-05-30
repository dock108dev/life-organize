from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

from fastapi import Header, HTTPException, Request, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin_events import admin_events
from app.config import settings
from app.models import AIRequestLog, DeviceClient

ACTIVE_DEVICE_STATUS = "active"


def hash_device_token(token: str) -> str:
    secret = settings.device_token_signing_secret or "development-device-token-secret"
    return hmac.new(secret.encode("utf-8"), token.encode("utf-8"), hashlib.sha256).hexdigest()


async def require_device_token(
    request: Request,
    x_lifeorganize_device_token: str | None = Header(default=None),
) -> str:
    token = (x_lifeorganize_device_token or "").strip()
    if len(token) < 16:
        admin_events.emit(
            "warning",
            "security",
            "Device token rejected",
            reason="missing_or_short",
            path=request.scope.get("path", "unknown"),
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "missing_device_token", "detail": "Missing device token."},
        )
    token_hash = hash_device_token(token)
    request.state.device_token_hash = token_hash
    return token_hash


async def require_admin_key(x_admin_api_key: str | None = Header(default=None)) -> None:
    validate_admin_key(x_admin_api_key)


def validate_admin_key(provided: str | None) -> None:
    expected = settings.admin_api_key
    if not expected:
        if settings.environment in {"production", "staging"}:
            admin_events.emit(
                "error",
                "security",
                "Admin auth misconfigured",
                environment=settings.environment,
            )
            raise HTTPException(
                status_code=500,
                detail={
                    "code": "admin_auth_misconfigured",
                    "detail": "Admin auth is not configured.",
                },
            )
        return
    if not provided or not secrets.compare_digest(provided, expected):
        admin_events.emit(
            "warning",
            "security",
            "Admin key rejected",
            reason="missing" if not provided else "invalid",
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_admin_key", "detail": "Invalid admin key."},
        )


async def enforce_active_device_token(session: AsyncSession, token_hash: str) -> None:
    existing = await session.scalar(
        select(DeviceClient).where(DeviceClient.token_hash == token_hash)
    )
    if existing is None:
        admin_events.emit(
            "warning",
            "security",
            "Unknown device token rejected",
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "unknown_device_token", "detail": "Unknown device token."},
        )
    elif existing.status != ACTIVE_DEVICE_STATUS:
        admin_events.emit(
            "warning",
            "security",
            "Inactive device token rejected",
            status=existing.status,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "revoked_device_token", "detail": "Device token is not active."},
        )
    else:
        await session.execute(
            update(DeviceClient)
            .where(DeviceClient.token_hash == token_hash)
            .values(last_seen_at=func.now(), request_count=DeviceClient.request_count + 1)
        )


async def enforce_device_rate_limit(session: AsyncSession, token_hash: str, endpoint: str) -> None:
    window_start = datetime.now(UTC) - timedelta(seconds=settings.device_rate_limit_window_seconds)
    count = await session.scalar(
        select(func.count())
        .select_from(AIRequestLog)
        .where(
            AIRequestLog.token_hash == token_hash,
            AIRequestLog.endpoint == endpoint,
            AIRequestLog.created_at >= window_start,
        )
    )
    if (count or 0) >= settings.device_rate_limit_requests:
        admin_events.emit(
            "warning",
            "security",
            "Device rate limit exceeded",
            endpoint=endpoint,
            window_seconds=settings.device_rate_limit_window_seconds,
            limit=settings.device_rate_limit_requests,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={"code": "rate_limited", "detail": "Rate limit exceeded."},
            headers={"Retry-After": str(settings.device_rate_limit_window_seconds)},
        )
