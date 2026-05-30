from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from typing import Any

import pytest

from app.admin_events import AdminEventBus, admin_events, event_payload, sse_event
from app.routers import admin
from app.services.openai_gateway import GatewayResult

_EVENT_FIELDS = {"id", "timestamp", "level", "category", "message", "details"}


def test_admin_event_bus_formats_recent_events() -> None:
    bus = AdminEventBus(maxlen=2)

    bus.emit("info", "request", "first", hidden=None)
    event = bus.emit("warning", "openai", "second", request_id="req_123")

    assert bus.recent(1) == [event]
    payload = event_payload(event)
    assert set(payload) == _EVENT_FIELDS
    assert payload["details"] == {"request_id": "req_123"}
    assert sse_event(event) == f"id: {event.id}\nevent: log\ndata: {json.dumps(payload)}\n\n"


def test_admin_event_bus_redacts_sensitive_detail_fields() -> None:
    bus = AdminEventBus()

    event = bus.emit(
        "info",
        "request",
        "safe summary",
        endpoint="/api/v1/extractions",
        status_code=200,
        api_key="sk-test-secret",
        request_json='{"text":"private user text"}',
        rawResponseText='{"answer":"private model output"}',
        nested={"deviceToken": "raw-device-token", "latency_ms": 42},
    )

    payload_text = json.dumps(event_payload(event), sort_keys=True)
    assert "sk-test-secret" not in payload_text
    assert "private user text" not in payload_text
    assert "private model output" not in payload_text
    assert "raw-device-token" not in payload_text
    assert event.details["endpoint"] == "/api/v1/extractions"
    assert event.details["status_code"] == 200
    assert event.details["api_key"] == "[redacted]"
    assert event.details["request_json"] == "[redacted]"
    assert event.details["rawResponseText"] == "[redacted]"
    assert event.details["nested"] == {"deviceToken": "[redacted]", "latency_ms": 42}


def test_admin_event_bus_retains_fixed_buffer_without_resetting_ids() -> None:
    bus = AdminEventBus(maxlen=3)

    for index in range(5):
        bus.emit("info", "admin", f"event-{index}")

    assert [event.id for event in bus.recent(500)] == [3, 4, 5]


def test_admin_event_bus_drops_backpressured_subscriber_without_raising() -> None:
    bus = AdminEventBus()
    subscriber: asyncio.Queue = asyncio.Queue(maxsize=1)
    subscriber.put_nowait(bus.emit("info", "admin", "fills subscriber"))
    bus._subscribers.add(subscriber)

    event = bus.emit("warning", "security", "request path should keep running")

    assert event.message == "request path should keep running"
    assert bus.recent(1) == [event]
    assert subscriber not in bus._subscribers


def test_admin_log_routes_use_header_and_session_auth(client, admin_headers: dict[str, str]) -> None:
    unauthorized = client.get("/api/admin/logs")
    assert unauthorized.status_code == 401

    session_response = client.post("/api/admin/logs/session", headers=admin_headers)
    assert session_response.status_code == 200
    assert session_response.json() == {"ok": True}
    assert "lifeorganize_admin_session" in session_response.cookies

    session_events = client.get("/api/admin/logs", params={"limit": 1})
    assert session_events.status_code == 200
    session_payload = session_events.json()["events"][0]
    assert set(session_payload) == _EVENT_FIELDS
    assert session_payload["level"] == "info"
    assert session_payload["category"] == "admin"
    assert session_payload["message"] == "Admin logs session opened"
    assert session_payload["details"] == {"source": "logs_page"}

    mark_response = client.post("/api/admin/logs/mark", json={"label": "Deploy marker"})
    assert mark_response.status_code == 200
    assert mark_response.json()["event"]["message"] == "Deploy marker"

    recent_response = client.get("/api/admin/logs", params={"limit": 1})
    assert recent_response.status_code == 200
    assert recent_response.json()["events"][0]["message"] == "Deploy marker"

    clear_response = client.post("/api/admin/logs/clear")
    assert clear_response.status_code == 200
    assert clear_response.json()["event"]["message"] == "Log buffer cleared"


def test_admin_log_clear_keeps_marker_and_monotonic_ids(
    client,
    admin_headers: dict[str, str],
) -> None:
    client.post("/api/admin/logs/session", headers=admin_headers)
    first_marker = client.post("/api/admin/logs/mark", json={"label": "Before clear"})

    clear_response = client.post("/api/admin/logs/clear")
    recent_response = client.get("/api/admin/logs", params={"limit": 500})

    clear_event = clear_response.json()["event"]
    assert clear_event["message"] == "Log buffer cleared"
    assert clear_event["id"] > first_marker.json()["event"]["id"]
    assert recent_response.json()["events"] == [clear_event]


def test_admin_log_stream_uses_cookie_session_and_rest_event_shape(
    client,
    admin_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session_response = client.post("/api/admin/logs/session", headers=admin_headers)
    assert session_response.status_code == 200
    rest_event = client.get("/api/admin/logs", params={"limit": 1}).json()["events"][0]

    async def finite_stream(limit: int = 100) -> AsyncIterator[str]:
        for event in admin_events.recent(limit):
            yield sse_event(event)

    def fail_if_header_auth_is_required(_request: Any) -> str | None:
        raise AssertionError("stream should authenticate with the admin session cookie")

    monkeypatch.setattr(admin_events, "stream", finite_stream)
    monkeypatch.setattr(admin, "_admin_key_from", fail_if_header_auth_is_required)

    stream_response = client.get("/api/admin/logs/stream", params={"limit": 1})

    assert stream_response.status_code == 200
    assert stream_response.headers["content-type"].startswith("text/event-stream")
    assert stream_response.headers["cache-control"] == "no-cache"
    assert stream_response.headers["connection"] == "keep-alive"
    assert stream_response.headers["x-accel-buffering"] == "no"
    assert stream_response.text.startswith(f"id: {rest_event['id']}\nevent: log\ndata: ")
    data_line = next(line for line in stream_response.text.splitlines() if line.startswith("data: "))
    assert json.loads(data_line.removeprefix("data: ")) == rest_event


def test_request_admin_logs_expose_metadata_without_sensitive_values(
    db_client,
    admin_headers: dict[str, str],
    enrolled_device_headers: dict[str, str],
    install_gateway_stub,
    settings_override,
) -> None:
    raw_user_text = "Private cardiology appointment notes and personal reminder."
    raw_provider_body = '{"events":[{"title":"private extracted event"}]}'
    raw_request_json = '{"input":[{"content":"Private cardiology appointment notes"}]}'
    raw_device_token = enrolled_device_headers["x-lifeorganize-device-token"]
    install_gateway_stub(
        extraction_result=GatewayResult(
            output_text=raw_provider_body,
            request_json=raw_request_json,
            model_name="test-redaction-model",
            openai_request_id="req_redaction_test",
            latency_ms=34,
        )
    )

    response = db_client.post(
        "/api/v1/extractions",
        headers=enrolled_device_headers,
        json={
            "text": raw_user_text,
            "currentDate": "2027-01-15",
            "currentDateTime": "2027-01-15T17:30:00Z",
            "timezone": "America/New_York",
            "schemaVersion": 7,
        },
    )
    logs_response = db_client.get("/api/admin/logs", headers=admin_headers)

    assert response.status_code == 200
    events = logs_response.json()["events"]
    request_events = [event for event in events if event["category"] == "request"]
    assert [event["message"] for event in request_events] == [
        "Extraction request received",
        "Extraction request completed",
    ]
    assert request_events[0]["details"] == {
        "endpoint": "/api/v1/extractions",
        "text_length": len(raw_user_text),
        "schema_version": 7,
        "timezone": "America/New_York",
    }
    assert request_events[1]["details"] == {
        "endpoint": "/api/v1/extractions",
        "status_code": 200,
        "latency_ms": 34,
        "model_name": "test-redaction-model",
        "openai_request_id": "req_redaction_test",
    }

    logs_text = json.dumps(logs_response.json(), sort_keys=True)
    assert raw_user_text not in logs_text
    assert raw_provider_body not in logs_text
    assert raw_request_json not in logs_text
    assert raw_device_token not in logs_text
    assert settings_override.openai_api_key not in logs_text
    assert "private extracted event" not in logs_text
    assert "Private cardiology appointment notes" not in logs_text
