from __future__ import annotations

from typing import Any

from app.services.openai_gateway import GatewayResult, OpenAIGatewayError


def test_extraction_route_logs_success(
    client,
    route_session,
    token_hash_override: str,
    install_gateway_stub,
    extraction_request_body: dict[str, Any],
) -> None:
    install_gateway_stub(
        extraction_result=GatewayResult(
            output_text='{"events":[]}',
            request_json='{"request":true}',
            model_name="test-model",
            openai_request_id="req_123",
            latency_ms=12,
        )
    )

    response = client.post("/api/v1/extractions", json=extraction_request_body)

    assert response.status_code == 200
    assert response.json()["rawResponseText"] == '{"events":[]}'
    assert token_hash_override == "test-token-hash"
    assert route_session.commits == 1
    assert [type(item).__name__ for item in route_session.added] == [
        "AIRequestLog",
    ]
    assert route_session.added[-1].status_code == 200


def test_web_request_route_maps_gateway_errors(
    client,
    route_session,
    token_hash_override: str,
    install_gateway_stub,
    web_answer_request_body: dict[str, Any],
) -> None:
    install_gateway_stub(
        web_error=OpenAIGatewayError("timeout", 408, "OpenAI request timed out.")
    )

    response = client.post("/api/v1/web-requests", json=web_answer_request_body)

    assert response.status_code == 408
    assert response.json()["detail"] == {
        "code": "timeout",
        "detail": "OpenAI request timed out.",
    }
    assert token_hash_override == "test-token-hash"
    assert route_session.commits == 1
    assert route_session.added[-1].status_code == 408
    assert route_session.added[-1].error_code == "timeout"


def test_extraction_route_preserves_gateway_error_contract(
    client,
    route_session,
    token_hash_override: str,
    install_gateway_stub,
    extraction_request_body: dict[str, Any],
) -> None:
    install_gateway_stub(
        extraction_error=OpenAIGatewayError(
            "invalid_model_response",
            422,
            "OpenAI response did not include output text.",
        )
    )

    response = client.post("/api/v1/extractions", json=extraction_request_body)

    assert response.status_code == 422
    assert response.json()["detail"] == {
        "code": "invalid_model_response",
        "detail": "OpenAI response did not include output text.",
    }
    assert token_hash_override == "test-token-hash"
    assert route_session.commits == 1
    assert route_session.added[-1].status_code == 422
    assert route_session.added[-1].error_code == "invalid_model_response"


def test_web_import_route_preserves_gateway_error_contract(
    client,
    route_session,
    token_hash_override: str,
    install_gateway_stub,
    extraction_request_body: dict[str, Any],
) -> None:
    install_gateway_stub(
        web_error=OpenAIGatewayError("rate_limited", 429, "OpenAI rate limit reached.")
    )
    body = {**extraction_request_body, "mode": "importRecords"}

    response = client.post("/api/v1/web-requests", json=body)

    assert response.status_code == 429
    assert response.json()["detail"] == {
        "code": "rate_limited",
        "detail": "OpenAI rate limit reached.",
    }
    assert token_hash_override == "test-token-hash"
    assert route_session.commits == 1
    assert route_session.added[-1].status_code == 429
    assert route_session.added[-1].error_code == "rate_limited"
