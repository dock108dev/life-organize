from __future__ import annotations

import json
from collections.abc import AsyncIterator
from typing import Any

import pytest
from conftest import SyncRouteSession
from fastapi.testclient import TestClient

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


def web_import_body() -> dict[str, Any]:
    return {
        "text": "Import records from this schedule.",
        "mode": "importRecords",
        "currentDate": "2027-01-15",
        "currentDateTime": "2027-01-15T17:30:00Z",
        "timezone": "America/New_York",
    }


@pytest.mark.parametrize(
    ("path", "body"),
    [
        ("/api/v1/extractions", extraction_body()),
        ("/api/v1/web-requests", web_import_body()),
    ],
)
@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"x-lifeorganize-device-token": ""},
        {"x-lifeorganize-device-token": "     "},
        {"x-lifeorganize-device-token": "short-token"},
    ],
)
def test_device_routes_reject_invalid_device_tokens(
    db_client: TestClient,
    sqlite_route_session: SyncRouteSession,
    install_gateway_stub,
    path: str,
    body: dict[str, Any],
    headers: dict[str, str],
) -> None:
    gateway = install_gateway_stub()

    response = db_client.post(path, headers=headers, json=body)

    assert response.status_code == 401
    assert response.json() == {
        "detail": {
            "code": "missing_device_token",
            "detail": "Missing device token.",
        }
    }
    assert gateway.extraction_requests == []
    assert gateway.web_requests == []
    assert sqlite_route_session.count(DeviceClient) == 0
    assert sqlite_route_session.count(AIRequestLog) == 0


def test_extractions_accept_valid_device_token_and_redact_persistence(
    db_client: TestClient,
    sqlite_route_session: SyncRouteSession,
    install_gateway_stub,
    device_headers: dict[str, str],
    admin_headers: dict[str, str],
) -> None:
    raw_token = device_headers["x-lifeorganize-device-token"]
    install_gateway_stub(
        extraction_result=GatewayResult(
            output_text='{"events":[]}',
            request_json='{"test":"extraction"}',
            model_name="test-model",
            openai_request_id="req_extraction_test",
            latency_ms=12,
        )
    )

    response = db_client.post(
        "/api/v1/extractions",
        headers=device_headers,
        json=extraction_body(),
    )
    logs_response = db_client.get("/api/admin/logs", headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == {
        "rawResponseText": '{"events":[]}',
        "requestJSON": '{"test":"extraction"}',
        "modelName": "test-model",
    }
    token_hash = auth.hash_device_token(raw_token)
    devices = sqlite_route_session.all(DeviceClient)
    request_logs = sqlite_route_session.all(AIRequestLog)
    assert len(devices) == 1
    assert len(request_logs) == 1
    assert devices[0].token_hash == token_hash
    assert request_logs[0].token_hash == token_hash
    assert request_logs[0].endpoint == "/api/v1/extractions"
    assert request_logs[0].status_code == 200
    assert raw_token not in devices[0].token_hash
    assert raw_token not in request_logs[0].token_hash
    assert raw_token not in json.dumps(logs_response.json(), sort_keys=True)


@pytest.mark.parametrize(
    ("body", "output_text", "expected"),
    [
        (
            web_answer_body(),
            "Test assistant response",
            {"assistantText": "Test assistant response", "modelName": "test-model"},
        ),
        (
            web_import_body(),
            '{"events":[]}',
            {
                "rawResponseText": '{"events":[]}',
                "requestJSON": '{"test":"web"}',
                "modelName": "test-model",
            },
        ),
    ],
)
def test_web_requests_accept_valid_device_token_modes(
    db_client: TestClient,
    sqlite_route_session: SyncRouteSession,
    install_gateway_stub,
    device_headers: dict[str, str],
    body: dict[str, Any],
    output_text: str,
    expected: dict[str, Any],
) -> None:
    install_gateway_stub(
        web_result=GatewayResult(
            output_text=output_text,
            request_json='{"test":"web"}',
            model_name="test-model",
            openai_request_id="req_web_test",
            latency_ms=15,
        )
    )

    response = db_client.post("/api/v1/web-requests", headers=device_headers, json=body)

    assert response.status_code == 200
    assert response.json() == expected
    request_logs = sqlite_route_session.all(AIRequestLog)
    assert len(request_logs) == 1
    assert request_logs[0].endpoint == "/api/v1/web-requests"


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"x-admin-api-key": ""},
        {"x-admin-api-key": "wrong-admin-key"},
        {"x-admin-api-key": " test-admin-key-123 "},
    ],
)
@pytest.mark.parametrize(
    ("method", "path", "json_body"),
    [
        ("GET", "/api/admin/usage", None),
        ("POST", "/api/admin/logs/session", None),
        ("GET", "/api/admin/logs", None),
        ("GET", "/api/admin/logs/stream", None),
        ("POST", "/api/admin/logs/mark", {"label": "Deploy check"}),
        ("POST", "/api/admin/logs/clear", None),
    ],
)
def test_admin_routes_reject_invalid_admin_keys(
    db_client: TestClient,
    method: str,
    path: str,
    json_body: dict[str, Any] | None,
    headers: dict[str, str],
) -> None:
    response = db_client.request(method, path, headers=headers, json=json_body)

    assert response.status_code == 401
    assert response.json() == {
        "detail": {
            "code": "invalid_admin_key",
            "detail": "Invalid admin key.",
        }
    }


def test_usage_accepts_exact_admin_key(
    db_client: TestClient,
    admin_headers: dict[str, str],
) -> None:
    response = db_client.get("/api/admin/usage", headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == {"devices": 0, "requests": 0}


def test_usage_fails_closed_when_admin_key_missing_in_production(
    db_client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "admin_api_key", None)

    response = db_client.get("/api/admin/usage")

    assert response.status_code == 500
    assert response.json() == {
        "detail": {
            "code": "admin_auth_misconfigured",
            "detail": "Admin auth is not configured.",
        }
    }


def test_logs_session_accepts_exact_admin_key_and_sets_cookie(
    db_client: TestClient,
    admin_headers: dict[str, str],
) -> None:
    response = db_client.post("/api/admin/logs/session", headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert "lifeorganize_admin_session" in response.cookies
    set_cookie = response.headers["set-cookie"]
    assert "HttpOnly" in set_cookie
    assert "SameSite=strict" in set_cookie
    assert "Max-Age=28800" in set_cookie


@pytest.mark.parametrize(
    ("method", "path", "json_body"),
    [
        ("GET", "/api/admin/logs", None),
        ("GET", "/api/admin/logs/stream", None),
        ("POST", "/api/admin/logs/mark", {"label": "Cookie marker"}),
        ("POST", "/api/admin/logs/clear", None),
    ],
)
def test_logs_routes_reject_invalid_session_cookie(
    db_client: TestClient,
    method: str,
    path: str,
    json_body: dict[str, Any] | None,
) -> None:
    response = db_client.request(
        method,
        path,
        headers={"cookie": "lifeorganize_admin_session=fake-session"},
        json=json_body,
    )

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "invalid_admin_key"


@pytest.mark.parametrize(
    ("method", "path", "json_body"),
    [
        ("GET", "/api/admin/logs", None),
        ("POST", "/api/admin/logs/mark", {"label": "Cookie marker"}),
        ("POST", "/api/admin/logs/clear", None),
    ],
)
def test_logs_routes_accept_admin_session_cookie(
    db_client: TestClient,
    admin_headers: dict[str, str],
    method: str,
    path: str,
    json_body: dict[str, Any] | None,
) -> None:
    session_response = db_client.post("/api/admin/logs/session", headers=admin_headers)
    assert session_response.status_code == 200

    response = db_client.request(method, path, json=json_body)

    assert response.status_code == 200


def test_stream_logs_accepts_admin_header_and_session_cookie(
    db_client: TestClient,
    admin_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def finite_stream(_limit: int = 100) -> AsyncIterator[str]:
        yield ": test\n\n"

    monkeypatch.setattr(admin_events, "stream", finite_stream)

    header_response = db_client.get("/api/admin/logs/stream", headers=admin_headers)
    session_response = db_client.post("/api/admin/logs/session", headers=admin_headers)
    cookie_response = db_client.get("/api/admin/logs/stream")

    for response in (header_response, cookie_response):
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/event-stream")
        assert response.headers["cache-control"] == "no-cache"
        assert response.headers["connection"] == "keep-alive"
        assert response.headers["x-accel-buffering"] == "no"
    assert session_response.status_code == 200


def test_logs_page_is_public_shell_without_admin_key(db_client: TestClient) -> None:
    response = db_client.get("/admin/logs")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "content-security-policy" in response.headers
    assert "Backend Logs" in response.text
