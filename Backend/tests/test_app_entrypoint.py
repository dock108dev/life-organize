from __future__ import annotations

import importlib
from collections.abc import Iterable
from typing import Any

import pytest
from fastapi import FastAPI, Response
from fastapi.testclient import TestClient

from app.admin_events import admin_events
from app.config import settings
from app.middleware.security_headers import SecurityHeadersMiddleware
from main import app, emit_startup_event

SECURITY_HEADERS = {
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "x-frame-options": "DENY",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "permissions-policy": "camera=(), microphone=(), geolocation=()",
}


async def _collect_asgi_response(
    *,
    method: str,
    path: str,
    headers: Iterable[tuple[bytes, bytes]] = (),
    body: bytes = b"",
) -> tuple[int, dict[str, str], bytes]:
    messages: list[dict[str, Any]] = []
    receive_calls = 0

    async def receive() -> dict[str, Any]:
        nonlocal receive_calls
        receive_calls += 1
        if receive_calls == 1:
            return {"type": "http.request", "body": body, "more_body": False}
        return {"type": "http.disconnect"}

    async def send(message: dict[str, Any]) -> None:
        messages.append(message)

    scope: dict[str, Any] = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "headers": list(headers),
        "client": ("testclient", 50000),
        "server": ("testserver", 80),
    }

    await app(scope, receive, send)

    response_start = next(message for message in messages if message["type"] == "http.response.start")
    response_body = b"".join(
        message.get("body", b"") for message in messages if message["type"] == "http.response.body"
    )
    response_headers = {
        name.decode("latin-1"): value.decode("latin-1")
        for name, value in response_start.get("headers", [])
    }
    return response_start["status"], response_headers, response_body


def test_healthz_is_unauthenticated_minimal_liveness_response(client) -> None:
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_healthz_uses_security_headers(client) -> None:
    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    for name, value in SECURITY_HEADERS.items():
        assert response.headers[name] == value


def test_security_headers_do_not_overwrite_existing_values() -> None:
    protected_app = FastAPI()

    @protected_app.get("/custom-header")
    async def custom_header() -> Response:
        return Response("ok", headers={"X-Frame-Options": "SAMEORIGIN"})

    protected_app.add_middleware(SecurityHeadersMiddleware)

    with TestClient(protected_app) as client:
        response = client.get("/custom-header")

    assert response.status_code == 200
    assert response.headers["x-frame-options"] == "SAMEORIGIN"
    for name, value in SECURITY_HEADERS.items():
        if name != "x-frame-options":
            assert response.headers[name] == value


def test_security_headers_are_skipped_for_options(client) -> None:
    response = client.options("/healthz")

    assert response.status_code == 405
    for name in SECURITY_HEADERS:
        assert name not in response.headers


@pytest.mark.parametrize("declared_size", [3, 4])
def test_request_size_limit_allows_declared_boundary(
    client,
    monkeypatch,
    declared_size: int,
) -> None:
    monkeypatch.setattr(settings, "max_request_bytes", 4)

    response = client.get("/healthz", headers={"content-length": str(declared_size)})

    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_request_size_limit_rejects_oversized_declared_content_length(
    client,
    monkeypatch,
) -> None:
    monkeypatch.setattr(settings, "max_request_bytes", 4)

    response = client.get("/healthz", headers={"content-length": "5"})

    assert response.status_code == 413
    assert response.json() == {
        "code": "request_too_large",
        "detail": "Request body is too large.",
    }
    for name in SECURITY_HEADERS:
        assert name not in response.headers


async def test_request_size_limit_allows_missing_content_length(monkeypatch) -> None:
    monkeypatch.setattr(settings, "max_request_bytes", 4)

    status, headers, body = await _collect_asgi_response(
        method="GET",
        path="/healthz",
        body=b"12345",
    )

    assert status == 200
    assert body == b'{"ok":true}'
    assert headers["x-frame-options"] == "DENY"


async def test_request_size_limit_allows_invalid_content_length(monkeypatch) -> None:
    monkeypatch.setattr(settings, "max_request_bytes", 4)

    status, headers, body = await _collect_asgi_response(
        method="GET",
        path="/healthz",
        headers=[(b"content-length", b"invalid")],
        body=b"12345",
    )

    assert status == 200
    assert body == b'{"ok":true}'
    assert headers["x-frame-options"] == "DENY"


async def test_request_size_limit_rejects_oversized_options(monkeypatch) -> None:
    monkeypatch.setattr(settings, "max_request_bytes", 4)

    status, headers, body = await _collect_asgi_response(
        method="OPTIONS",
        path="/healthz",
        headers=[(b"content-length", b"5")],
    )

    assert status == 413
    assert body == b'{"code":"request_too_large","detail":"Request body is too large."}'
    for name in SECURITY_HEADERS:
        assert name not in headers


@pytest.mark.parametrize(
    ("environment", "expected_docs_url", "expected_redoc_url", "expected_openapi_url"),
    [
        ("production", None, None, None),
        ("staging", None, None, None),
        ("development", "/docs", "/redoc", "/openapi.json"),
    ],
)
def test_docs_and_openapi_visibility_tracks_environment(
    monkeypatch,
    environment: str,
    expected_docs_url: str | None,
    expected_redoc_url: str | None,
    expected_openapi_url: str | None,
) -> None:
    import main as main_module

    original_environment = settings.environment
    try:
        monkeypatch.setattr(settings, "environment", environment)
        reloaded_main = importlib.reload(main_module)

        assert reloaded_main.app.docs_url == expected_docs_url
        assert reloaded_main.app.redoc_url == expected_redoc_url
        assert reloaded_main.app.openapi_url == expected_openapi_url
        with TestClient(reloaded_main.app) as client:
            docs_response = client.get("/docs")
            redoc_response = client.get("/redoc")
            openapi_response = client.get("/openapi.json")

        if expected_openapi_url is None:
            assert docs_response.status_code == 404
            assert redoc_response.status_code == 404
            assert openapi_response.status_code == 404
        else:
            assert docs_response.status_code == 200
            assert redoc_response.status_code == 200
            assert openapi_response.status_code == 200
            assert openapi_response.json()["info"]["title"] == "life-organize-backend"
    finally:
        monkeypatch.setattr(settings, "environment", original_environment)
        importlib.reload(main_module)


async def test_startup_event_emits_runtime_metadata(monkeypatch) -> None:
    emitted = []

    def emit(level: str, category: str, message: str, **details):
        emitted.append((level, category, message, details))

    monkeypatch.setattr(admin_events, "emit", emit)

    await emit_startup_event()

    assert emitted == [
        (
            "info",
            "admin",
            "LifeOrganize backend started",
            {"environment": settings.environment, "model": settings.openai_model},
        )
    ]
