from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

import httpx
import pytest

from app.schemas import ExtractionRequest, WebRequest
from app.services import openai_gateway
from app.services.openai_gateway import OpenAIGateway, OpenAIGatewayError, _output_text


class FakeGatewayResponse:
    def __init__(
        self,
        *,
        status_code: int,
        body: Any | None = None,
        json_error: Exception | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.status_code = status_code
        self.body = body if body is not None else {"output_text": "ignored"}
        self.json_error = json_error
        self.headers = headers or {}
        self.json_calls = 0

    def json(self) -> Any:
        self.json_calls += 1
        if self.json_error is not None:
            raise self.json_error
        return self.body


def install_fake_client(
    monkeypatch: pytest.MonkeyPatch,
    *,
    response: FakeGatewayResponse | None = None,
    error: httpx.HTTPError | None = None,
    post_calls: list[dict[str, Any]] | None = None,
) -> None:
    class FakeAsyncClient:
        def __init__(self, timeout: float) -> None:
            self.timeout = timeout

        async def __aenter__(self):
            return self

        async def __aexit__(self, _exc_type, _exc, _traceback) -> None:
            return None

        async def post(self, endpoint: str, *, headers: dict, content: str):
            if post_calls is not None:
                post_calls.append(
                    {
                        "endpoint": endpoint,
                        "headers": headers,
                        "content": content,
                        "timeout": self.timeout,
                    }
                )
            if error is not None:
                raise error
            return response or FakeGatewayResponse(status_code=200)

    monkeypatch.setattr(openai_gateway.httpx, "AsyncClient", FakeAsyncClient)


def test_extraction_payload_uses_strict_schema_and_local_date_context(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OPENAI_MODEL", "test-model")
    request = ExtractionRequest(
        text='Changed the "hallway" filter today.',
        currentDate="2027-01-15",
        currentDateTime="2027-01-15T17:30:00Z",
        timezone="America/New_York",
    )

    payload = OpenAIGateway()._extraction_payload(request)
    encoded = json.dumps(payload)
    user_text = payload["input"][1]["content"][0]["text"]

    assert payload["text"]["format"]["type"] == "json_schema"
    assert payload["text"]["format"]["name"] == "life_ledger_extraction_v1"
    assert payload["text"]["format"]["strict"] is True
    assert '"currentDate": "2027-01-15"' in user_text
    assert '"timezone": "America/New_York"' in user_text
    assert "Do not provide advice, coaching, emotional analysis, or conversation." in encoded
    assert "EventMetadataExtraction" in encoded
    assert "recallQueries" in encoded


def test_web_answer_payload_enables_web_search_without_schema() -> None:
    request = WebRequest(
        text="Saturday best college football games with kickoff times.",
        mode="answer",
        currentDate="2027-01-15",
        currentDateTime="2027-01-15T17:30:00Z",
        timezone="America/New_York",
    )

    payload = OpenAIGateway()._web_payload(request)

    assert payload["tools"][0]["type"] == "web_search"
    assert payload["tools"][0]["user_location"]["country"] == "US"
    assert payload["tools"][0]["user_location"]["timezone"] == "America/New_York"
    assert payload["include"] == ["web_search_call.action.sources"]
    assert payload["tool_choice"] == "auto"
    assert "text" not in payload


def test_web_import_payload_uses_schema() -> None:
    request = WebRequest(
        text="Add Rutgers football home games for 2026.",
        mode="importRecords",
        currentDate="2027-01-15",
        currentDateTime="2027-01-15T17:30:00Z",
        timezone="America/New_York",
    )

    payload = OpenAIGateway()._web_payload(request)

    assert payload["text"]["format"]["type"] == "json_schema"
    assert payload["text"]["format"]["name"] == "life_ledger_extraction_v1"


def test_output_text_accepts_response_api_shapes() -> None:
    assert _output_text({"output_text": "hello"}) == "hello"
    assert _output_text({"output": [{"content": [{"text": "nested"}]}]}) == "nested"


async def test_send_extraction_posts_to_responses_api(monkeypatch: pytest.MonkeyPatch) -> None:
    requests = []
    response = FakeGatewayResponse(
        status_code=200,
        body={"output_text": '{"events":[]}'},
        headers={"x-request-id": "req_123"},
    )

    monkeypatch.setattr(openai_gateway.settings, "openai_api_key", "test-key")
    monkeypatch.setattr(openai_gateway.settings, "openai_model", "test-model")
    monkeypatch.setattr(openai_gateway.settings, "request_timeout_seconds", 7)
    install_fake_client(monkeypatch, response=response, post_calls=requests)

    result = await OpenAIGateway().send_extraction(
        ExtractionRequest(
            text="Changed the hallway filter today.",
            currentDate="2027-01-15",
            currentDateTime="2027-01-15T17:30:00Z",
            timezone="America/New_York",
        )
    )

    request = requests[0]
    assert request["endpoint"] == "https://api.openai.com/v1/responses"
    assert request["headers"]["Authorization"] == "Bearer test-key"
    assert request["timeout"] == 7
    assert json.loads(request["content"])["model"] == "test-model"
    assert result.output_text == '{"events":[]}'
    assert result.openai_request_id == "req_123"


async def test_send_reports_missing_openai_key(monkeypatch: pytest.MonkeyPatch) -> None:
    class UnexpectedAsyncClient:
        def __init__(self, timeout: float) -> None:
            raise AssertionError("HTTP client should not be constructed without an API key.")

    monkeypatch.setattr(openai_gateway.settings, "openai_api_key", None)
    monkeypatch.setattr(openai_gateway.httpx, "AsyncClient", UnexpectedAsyncClient)

    with pytest.raises(OpenAIGatewayError) as exc_info:
        await OpenAIGateway()._send({"model": "test-model"}, kind="extraction")

    assert exc_info.value.code == "openai_not_configured"
    assert exc_info.value.status_code == 502
    assert exc_info.value.detail == "OpenAI is not configured."


@pytest.mark.parametrize(
    ("response_status", "code", "status_code", "detail"),
    [
        (429, "rate_limited", 429, "OpenAI rate limit reached."),
        (500, "openai_server_error", 502, "OpenAI server error."),
        (599, "openai_server_error", 502, "OpenAI server error."),
        (401, "openai_auth_error", 502, "OpenAI authentication failed."),
        (403, "openai_auth_error", 502, "OpenAI authentication failed."),
        (400, "openai_invalid_response", 502, "OpenAI returned an invalid response."),
        (302, "openai_invalid_response", 502, "OpenAI returned an invalid response."),
    ],
)
async def test_send_maps_openai_status_errors(
    monkeypatch: pytest.MonkeyPatch,
    response_status: int,
    code: str,
    status_code: int,
    detail: str,
) -> None:
    response = FakeGatewayResponse(status_code=response_status)

    monkeypatch.setattr(openai_gateway.settings, "openai_api_key", "test-key")
    install_fake_client(monkeypatch, response=response)

    with pytest.raises(OpenAIGatewayError) as exc_info:
        await OpenAIGateway()._send({"model": "test-model"}, kind="extraction")

    assert exc_info.value.code == code
    assert exc_info.value.status_code == status_code
    assert exc_info.value.detail == detail
    assert response.json_calls == 0


@pytest.mark.parametrize(
    ("error_factory", "code", "status_code", "detail"),
    [
        (
            lambda: httpx.TimeoutException("timed out"),
            "timeout",
            408,
            "OpenAI request timed out.",
        ),
        (
            lambda: httpx.ConnectError("connect failed"),
            "network_unavailable",
            502,
            "OpenAI network request failed.",
        ),
    ],
)
async def test_send_maps_transport_errors(
    monkeypatch: pytest.MonkeyPatch,
    error_factory: Callable[[], httpx.HTTPError],
    code: str,
    status_code: int,
    detail: str,
) -> None:
    monkeypatch.setattr(openai_gateway.settings, "openai_api_key", "test-key")
    install_fake_client(monkeypatch, error=error_factory())

    with pytest.raises(OpenAIGatewayError) as exc_info:
        await OpenAIGateway()._send({"model": "test-model"}, kind="extraction")

    assert exc_info.value.code == code
    assert exc_info.value.status_code == status_code
    assert exc_info.value.detail == detail


@pytest.mark.parametrize(
    "response",
    [
        FakeGatewayResponse(status_code=200, json_error=ValueError("malformed json")),
        FakeGatewayResponse(status_code=200, body={"output": [{"content": [{}]}]}),
    ],
)
async def test_send_maps_invalid_model_body_errors(
    monkeypatch: pytest.MonkeyPatch,
    response: FakeGatewayResponse,
) -> None:
    monkeypatch.setattr(openai_gateway.settings, "openai_api_key", "test-key")
    install_fake_client(monkeypatch, response=response)

    with pytest.raises(OpenAIGatewayError) as body_error:
        await OpenAIGateway()._send({"model": "test-model"}, kind="extraction")

    assert body_error.value.code == "invalid_model_response"
    assert body_error.value.status_code == 422
    assert body_error.value.detail == "OpenAI response did not include output text."
