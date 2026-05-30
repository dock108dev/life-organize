from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from conftest import SyncRouteSession
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

import app.auth as auth
from app.admin_events import admin_events
from app.config import settings
from app.models import AIRequestLog, DeviceClient
from app.services.openai_gateway import GatewayResult


def extraction_body() -> dict[str, Any]:
    return {
        "text": "Changed the hallway filter today.",
        "currentDate": "2027-01-15",
        "currentDateTime": "2027-01-15T17:30:00Z",
        "timezone": "America/New_York",
    }


def web_answer_body() -> dict[str, Any]:
    return {
        "text": "What should I do first today?",
        "mode": "answer",
        "currentDate": "2027-01-15",
        "currentDateTime": "2027-01-15T17:30:00Z",
        "timezone": "America/New_York",
    }


def test_rate_limited_response_includes_retry_after_and_skips_gateway_log(
    db_client: TestClient,
    sqlite_route_session: SyncRouteSession,
    install_gateway_stub,
    enrolled_device_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "device_rate_limit_requests", 1)
    monkeypatch.setattr(settings, "device_rate_limit_window_seconds", 37)
    gateway = install_gateway_stub(
        web_result=GatewayResult(
            output_text="Test assistant response",
            request_json='{"test":"web"}',
            model_name="test-model",
            openai_request_id="req_web_test",
            latency_ms=15,
        )
    )

    first_response = db_client.post(
        "/api/v1/web-requests",
        headers=enrolled_device_headers,
        json=web_answer_body(),
    )
    second_response = db_client.post(
        "/api/v1/web-requests",
        headers=enrolled_device_headers,
        json=web_answer_body(),
    )

    assert first_response.status_code == 200
    assert second_response.status_code == 429
    assert second_response.headers["Retry-After"] == "37"
    assert second_response.json() == {
        "detail": {
            "code": "rate_limited",
            "detail": "Rate limit exceeded.",
        }
    }
    assert gateway.web_requests is not None
    assert len(gateway.web_requests) == 1
    assert sqlite_route_session.count(AIRequestLog) == 1
    security_events = [event for event in admin_events.recent(50) if event.category == "security"]
    assert security_events[-1].message == "Device rate limit exceeded"
    assert security_events[-1].details == {
        "endpoint": "/api/v1/web-requests",
        "window_seconds": 37,
        "limit": 1,
    }


def test_rate_limit_keeps_separate_endpoint_quotas(
    db_client: TestClient,
    install_gateway_stub,
    enrolled_device_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "device_rate_limit_requests", 1)
    monkeypatch.setattr(settings, "device_rate_limit_window_seconds", 60)
    install_gateway_stub()

    extraction_response = db_client.post(
        "/api/v1/extractions",
        headers=enrolled_device_headers,
        json=extraction_body(),
    )
    web_response = db_client.post(
        "/api/v1/web-requests",
        headers=enrolled_device_headers,
        json=web_answer_body(),
    )
    blocked_response = db_client.post(
        "/api/v1/extractions",
        headers=enrolled_device_headers,
        json=extraction_body(),
    )

    assert extraction_response.status_code == 200
    assert web_response.status_code == 200
    assert blocked_response.status_code == 429


def test_rate_limit_does_not_share_quota_by_client_ip(
    db_client: TestClient,
    sqlite_route_session: SyncRouteSession,
    install_gateway_stub,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "device_rate_limit_requests", 1)
    monkeypatch.setattr(settings, "device_rate_limit_window_seconds", 60)
    install_gateway_stub()
    device_a_headers = {"x-lifeorganize-device-token": "device-token-aaaaaaaa"}
    device_b_headers = {"x-lifeorganize-device-token": "device-token-bbbbbbbb"}
    for headers in (device_a_headers, device_b_headers):
        raw_token = headers["x-lifeorganize-device-token"]
        sqlite_route_session.session.add(
            DeviceClient(
                token_hash=auth.hash_device_token(raw_token),
                request_count=0,
                status=auth.ACTIVE_DEVICE_STATUS,
            )
        )
    sqlite_route_session.session.commit()

    first_a = db_client.post(
        "/api/v1/extractions",
        headers=device_a_headers,
        json=extraction_body(),
    )
    first_b = db_client.post(
        "/api/v1/extractions",
        headers=device_b_headers,
        json=extraction_body(),
    )
    second_a = db_client.post(
        "/api/v1/extractions",
        headers=device_a_headers,
        json=extraction_body(),
    )

    assert first_a.status_code == 200
    assert first_b.status_code == 200
    assert second_a.status_code == 429


async def test_enforce_rate_limit_ignores_rows_older_than_window(
    sqlite_route_session: SyncRouteSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fixed_now = datetime(2027, 1, 15, 12, 0, tzinfo=UTC)
    token_hash = auth.hash_device_token("device-token-1234567890")
    _insert_request_log(
        sqlite_route_session.session,
        token_hash,
        "/api/v1/extractions",
        fixed_now - timedelta(seconds=60, microseconds=1),
    )
    monkeypatch.setattr(settings, "device_rate_limit_requests", 1)
    monkeypatch.setattr(settings, "device_rate_limit_window_seconds", 60)
    _freeze_auth_now(monkeypatch, fixed_now)

    await auth.enforce_device_rate_limit(
        sqlite_route_session,
        token_hash,
        "/api/v1/extractions",
    )


async def test_enforce_rate_limit_counts_rows_at_window_boundary(
    sqlite_route_session: SyncRouteSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fixed_now = datetime(2027, 1, 15, 12, 0, tzinfo=UTC)
    token_hash = auth.hash_device_token("device-token-1234567890")
    _insert_request_log(
        sqlite_route_session.session,
        token_hash,
        "/api/v1/extractions",
        fixed_now - timedelta(seconds=60),
    )
    monkeypatch.setattr(settings, "device_rate_limit_requests", 1)
    monkeypatch.setattr(settings, "device_rate_limit_window_seconds", 60)
    _freeze_auth_now(monkeypatch, fixed_now)

    with pytest.raises(HTTPException) as exc_info:
        await auth.enforce_device_rate_limit(
            sqlite_route_session,
            token_hash,
            "/api/v1/extractions",
        )

    assert exc_info.value.status_code == 429
    assert exc_info.value.headers == {"Retry-After": "60"}
    assert exc_info.value.detail == {
        "code": "rate_limited",
        "detail": "Rate limit exceeded.",
    }


def _insert_request_log(
    session: Session,
    token_hash: str,
    endpoint: str,
    created_at: datetime,
) -> None:
    session.add(
        AIRequestLog(
            token_hash=token_hash,
            endpoint=endpoint,
            status_code=200,
            latency_ms=10,
            model_name="test-model",
            openai_request_id="req_test",
            created_at=created_at,
        )
    )
    session.commit()


def _freeze_auth_now(monkeypatch: pytest.MonkeyPatch, fixed_now: datetime) -> None:
    class FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz: object | None = None) -> datetime:
            if tz is None:
                return fixed_now.replace(tzinfo=None)
            return fixed_now.astimezone(tz)

    monkeypatch.setattr(auth, "datetime", FrozenDateTime)
