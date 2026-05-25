from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.schemas import ExtractionRequest, ExtractionResponse, WebAnswerResponse, WebRequest
from app.services.openai_schema import EXTRACTION_SCHEMA, EXTRACTION_SCHEMA_NAME

CONTRACT_DIR = (
    Path(__file__).resolve().parents[2] / "LifeOrganizeTests" / "Fixtures" / "BackendContract"
)


def load_contract_json(name: str) -> dict[str, Any]:
    return json.loads((CONTRACT_DIR / name).read_text(encoding="utf-8"))


def test_extraction_request_fixture_matches_backend_schema() -> None:
    payload = load_contract_json("backend_extraction_request.v1.json")

    request = ExtractionRequest.model_validate(payload)

    assert set(payload) == {
        "text",
        "currentDate",
        "currentDateTime",
        "timezone",
        "schemaVersion",
    }
    assert request.model_dump() == payload


def test_web_request_fixtures_match_backend_schema_and_modes() -> None:
    metadata = load_contract_json("extraction_contract.v1.json")
    answer_payload = load_contract_json("backend_web_answer_request.v1.json")
    import_payload = load_contract_json("backend_web_import_request.v1.json")

    answer_request = WebRequest.model_validate(answer_payload)
    import_request = WebRequest.model_validate(import_payload)

    assert set(answer_payload) == {"text", "mode", "currentDate", "currentDateTime", "timezone"}
    assert answer_request.model_dump() == answer_payload
    assert import_request.model_dump() == import_payload
    assert [answer_request.mode, import_request.mode] == metadata["webModes"]


def test_backend_response_fixtures_match_ios_dto_names() -> None:
    extraction_payload = load_contract_json("backend_extraction_response.v1.json")
    answer_payload = load_contract_json("backend_web_answer_response.v1.json")
    import_payload = load_contract_json("backend_web_import_response.v1.json")

    extraction_response = ExtractionResponse.model_validate(extraction_payload)
    answer_response = WebAnswerResponse.model_validate(answer_payload)
    import_response = ExtractionResponse.model_validate(import_payload)

    assert set(extraction_payload) == {"rawResponseText", "requestJSON", "modelName"}
    assert extraction_response.model_dump() == extraction_payload
    assert set(answer_payload) == {"assistantText", "modelName"}
    assert answer_response.model_dump() == answer_payload
    assert set(import_payload) == {"rawResponseText", "requestJSON", "modelName"}
    assert import_response.model_dump() == import_payload


def test_extraction_schema_version_signals_match_contract_fixture() -> None:
    metadata = load_contract_json("extraction_contract.v1.json")

    assert ExtractionRequest.model_fields["schemaVersion"].default == metadata["requestSchemaVersion"]
    assert metadata["openAISchemaName"] == EXTRACTION_SCHEMA_NAME
    assert EXTRACTION_SCHEMA_NAME == "life_ledger_extraction_v1"
    assert EXTRACTION_SCHEMA["properties"]["schemaVersion"]["enum"] == [
        metadata["openAIOutputSchemaVersion"]
    ]
