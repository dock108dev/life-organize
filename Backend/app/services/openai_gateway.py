from __future__ import annotations

import json
import time
from dataclasses import dataclass

import httpx

from app.config import settings
from app.schemas import ExtractionRequest, WebRequest
from app.services.openai_schema import EXTRACTION_SCHEMA, EXTRACTION_SCHEMA_NAME


class OpenAIGatewayError(Exception):
    def __init__(self, code: str, status_code: int, detail: str) -> None:
        self.code = code
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@dataclass
class GatewayResult:
    output_text: str
    request_json: str
    model_name: str
    openai_request_id: str | None
    latency_ms: int


class OpenAIGateway:
    endpoint = "https://api.openai.com/v1/responses"

    async def send_extraction(self, request: ExtractionRequest) -> GatewayResult:
        payload = self._extraction_payload(request)
        return await self._send(payload)

    async def send_web_request(self, request: WebRequest) -> GatewayResult:
        payload = self._web_payload(request)
        return await self._send(payload)

    def _extraction_payload(self, request: ExtractionRequest) -> dict:
        return {
            "model": settings.openai_model,
            "input": [
                {"role": "system", "content": [{"type": "input_text", "text": _EXTRACTION_INSTRUCTIONS}]},
                {"role": "user", "content": [{"type": "input_text", "text": _user_payload(request.text, request.currentDate, request.currentDateTime, request.timezone)}]},
            ],
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": EXTRACTION_SCHEMA_NAME,
                    "strict": True,
                    "schema": EXTRACTION_SCHEMA,
                }
            },
        }

    def _web_payload(self, request: WebRequest) -> dict:
        text_format = None
        if request.mode == "importRecords":
            text_format = {
                "format": {
                    "type": "json_schema",
                    "name": EXTRACTION_SCHEMA_NAME,
                    "strict": True,
                    "schema": EXTRACTION_SCHEMA,
                }
            }
        payload: dict = {
            "model": settings.openai_model,
            "input": [
                {"role": "system", "content": [{"type": "input_text", "text": _web_instructions(request.mode)}]},
                {"role": "user", "content": [{"type": "input_text", "text": _user_payload(request.text, request.currentDate, request.currentDateTime, request.timezone)}]},
            ],
            "tools": [
                {
                    "type": "web_search",
                    "user_location": {
                        "type": "approximate",
                        "country": "US",
                        "timezone": request.timezone,
                    },
                }
            ],
            "include": ["web_search_call.action.sources"],
            "tool_choice": "auto",
        }
        if text_format is not None:
            payload["text"] = text_format
        return payload

    async def _send(self, payload: dict) -> GatewayResult:
        if not settings.openai_api_key:
            raise OpenAIGatewayError("openai_not_configured", 502, "OpenAI is not configured.")

        started = time.perf_counter()
        encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        try:
            async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
                response = await client.post(
                    self.endpoint,
                    headers={
                        "Authorization": f"Bearer {settings.openai_api_key}",
                        "Content-Type": "application/json",
                    },
                    content=encoded,
                )
        except httpx.TimeoutException as exc:
            raise OpenAIGatewayError("timeout", 408, "OpenAI request timed out.") from exc
        except httpx.HTTPError as exc:
            raise OpenAIGatewayError("network_unavailable", 502, "OpenAI network request failed.") from exc

        latency_ms = int((time.perf_counter() - started) * 1000)
        request_id = response.headers.get("x-request-id")
        if response.status_code == 429:
            raise OpenAIGatewayError("rate_limited", 429, "OpenAI rate limit reached.")
        if 500 <= response.status_code:
            raise OpenAIGatewayError("openai_server_error", 502, "OpenAI server error.")
        if response.status_code in {401, 403}:
            raise OpenAIGatewayError("openai_auth_error", 502, "OpenAI authentication failed.")
        if response.status_code < 200 or response.status_code >= 300:
            raise OpenAIGatewayError("openai_invalid_response", 502, "OpenAI returned an invalid response.")

        try:
            body = response.json()
            output_text = _output_text(body)
        except Exception as exc:
            raise OpenAIGatewayError("invalid_model_response", 422, "OpenAI response did not include output text.") from exc

        return GatewayResult(
            output_text=output_text,
            request_json=encoded,
            model_name=str(payload["model"]),
            openai_request_id=request_id,
            latency_ms=latency_ms,
        )


def _output_text(body: dict) -> str:
    direct = body.get("output_text")
    if isinstance(direct, str) and direct:
        return direct
    for item in body.get("output", []):
        for content in item.get("content", []):
            text = content.get("text")
            if isinstance(text, str) and text:
                return text
    raise ValueError("missing output text")


def _user_payload(text: str, current_date: str, current_date_time: str, timezone: str) -> str:
    return json.dumps(
        {
            "currentDate": current_date,
            "currentDateTime": current_date_time,
            "timezone": timezone,
            "userMessage": text,
        },
        ensure_ascii=False,
        sort_keys=True,
    )


def _web_instructions(mode: str) -> str:
    if mode == "answer":
        return (
            "Answer the user's web-backed ledger question using current web results. "
            "Keep the answer concise and factual. Include dates, times, and time zones when relevant. "
            "Include source URLs in the answer text. Do not provide betting advice."
        )
    return (
        "Use web search to find the requested public schedule or dated facts, then return only JSON "
        "matching the provided ledger extraction schema. Do not include prose outside JSON. "
        "Create Things for stable subjects, Events for dated games or appointments, and reminder Rules "
        "for user-stated preparation times such as tailgating before a game. Include source URLs in rawText, notes, or metadata."
    )


_EXTRACTION_INSTRUCTIONS = """
You extract structured data for a local personal ledger app.
Return JSON that matches the provided schema exactly.
Do not provide advice, coaching, emotional analysis, or conversation.
Extract only what the user said or what is obvious from the provided current date and timezone.
Resolve relative dates using currentDate, currentDateTime, and timezone. Never use server time.
If a date is ambiguous, set date to null, lower confidence, and add an error.
Use null instead of guessing and empty arrays when there are no entities of a type.
Use only the eventType values in the schema: generic, maintenance, purchase, visit, replacement,
cleaning, renewal, appointment, project, note, reminder, measurement, status_change, and other.
Choose other instead of inventing a new event ontology.
For ruleType, use reminder for one-time due reminders, restriction for do-not-do commitments,
waiting_period for temporary waiting windows, deadline for due-by commitments, and preference
only for standing preferences.
Prefer Events or reminder Rules for actions, purchases, maintenance, visits, cleaning, renewals,
appointments, projects, and anything due in the future. Do not store those as standalone Notes.
Use top-level Notes sparingly for durable freeform facts that are not actions or obligations.
Treat top-level DateExtraction entries as evidence and link them with ownerRef and ownerField when clear.
Put practical scalar details in metadata when present, including mileage, amount, quantity, vendor,
location, due_date, identifiers, units, and short source spans.
""".strip()
