from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

from fastapi import Header, HTTPException, Request, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import AIRequestLog, DeviceClient


def hash_device_token(token: str) -> str:
    secret = settings.device_token_signing_secret or "development-device-token-secret"
    return hmac.new(secret.encode("utf-8"), token.encode("utf-8"), hashlib.sha256).hexdigest()


async def require_device_token(
    request: Request,
    x_lifeorganize_device_token: str | None = Header(default=None),
) -> str:
    token = (x_lifeorganize_device_token or "").strip()
    if len(token) < 16:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "missing_device_token", "detail": "Missing device token."},
        )
    token_hash = hash_device_token(token)
    request.state.device_token_hash = token_hash
    return token_hash


async def require_admin_key(x_admin_api_key: str | None = Header(default=None)) -> None:
    expected = settings.admin_api_key
    if not expected:
        if settings.environment in {"production", "staging"}:
            raise HTTPException(
                status_code=500,
                detail={"code": "admin_auth_misconfigured", "detail": "Admin auth is not configured."},
            )
        return
    if not x_admin_api_key or not secrets.compare_digest(x_admin_api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "invalid_admin_key", "detail": "Invalid admin key."},
        )


async def record_device_seen(session: AsyncSession, token_hash: str) -> None:
    existing = await session.scalar(select(DeviceClient).where(DeviceClient.token_hash == token_hash))
    if existing is None:
        session.add(DeviceClient(token_hash=token_hash, request_count=1))
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
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={"code": "rate_limited", "detail": "Rate limit exceeded."},
            headers={"Retry-After": str(settings.device_rate_limit_window_seconds)},
        )
