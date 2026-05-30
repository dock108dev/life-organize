from __future__ import annotations

import json
from typing import Any

from app.services.openai_gateway import OpenAIGatewayError


async def test_async_client_fixture_serves_backend(async_client) -> None:
    response = await async_client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_settings_fixture_uses_isolated_test_values(settings_override) -> None:
    assert settings_override.environment == "test"
    assert settings_override.openai_api_key == "test-openai-key"
    assert settings_override.database_url.endswith("/lifeorganize_test")


async def test_route_harness_stubs_gateway_success_without_sensitive_logs(
    async_client,
    route_session,
    install_gateway_stub,
    device_headers: dict[str, str],
    admin_headers: dict[str, str],
    extraction_request_body: dict[str, Any],
) -> None:
    gateway = install_gateway_stub()

    response = await async_client.post(
        "/api/v1/extractions",
        headers=device_headers,
        json=extraction_request_body,
    )
    logs_response = await async_client.get("/api/admin/logs", headers=admin_headers)

    assert response.status_code == 200
    assert response.json()["rawResponseText"] == '{"events":[]}'
    assert gateway.extraction_requests is not None
    assert gateway.extraction_requests[0].text == extraction_request_body["text"]
    assert route_session.commits == 1
    assert [type(item).__name__ for item in route_session.added] == [
        "AIRequestLog",
    ]

    logs_text = json.dumps(logs_response.json(), sort_keys=True)
    assert device_headers["x-lifeorganize-device-token"] not in logs_text
    assert admin_headers["x-admin-api-key"] not in logs_text
    assert extraction_request_body["text"] not in logs_text
    assert "fixture" not in logs_text


async def test_route_harness_stubs_gateway_failure_without_live_provider_calls(
    async_client,
    route_session,
    install_gateway_stub,
    device_headers: dict[str, str],
    web_answer_request_body: dict[str, Any],
) -> None:
    install_gateway_stub(
        web_error=OpenAIGatewayError("openai_auth_error", 502, "OpenAI authentication failed.")
    )

    response = await async_client.post(
        "/api/v1/web-requests",
        headers=device_headers,
        json=web_answer_request_body,
    )

    assert response.status_code == 502
    assert response.json()["detail"] == {
        "code": "openai_auth_error",
        "detail": "OpenAI authentication failed.",
    }
    assert route_session.commits == 1
    assert route_session.added[-1].error_code == "openai_auth_error"


async def test_admin_usage_uses_overridden_session(
    async_client,
    route_session,
    admin_headers: dict[str, str],
) -> None:
    route_session.scalar_values = [2, 7]

    response = await async_client.get("/api/admin/usage", headers=admin_headers)

    assert response.status_code == 200
    assert response.json() == {"devices": 2, "requests": 7}
