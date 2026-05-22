from __future__ import annotations

import json

import pytest

from app.schemas import ExtractionRequest, WebRequest
from app.services.openai_gateway import OpenAIGateway, _output_text


def test_extraction_payload_uses_strict_schema_and_local_date_context(monkeypatch: pytest.MonkeyPatch) -> None:
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
