from __future__ import annotations

import time

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import enforce_device_rate_limit, record_device_seen, require_admin_key, require_device_token
from app.db import get_session
from app.models import AIRequestLog, DeviceClient
from app.schemas import ExtractionRequest, ExtractionResponse, WebAnswerResponse, WebRequest
from app.services.openai_gateway import OpenAIGateway, OpenAIGatewayError

router = APIRouter()


@router.post("/api/v1/extractions", response_model=ExtractionResponse)
async def extract(
    body: ExtractionRequest,
    request: Request,
    token_hash: str = Depends(require_device_token),
    session: AsyncSession = Depends(get_session),
) -> ExtractionResponse:
    await record_device_seen(session, token_hash)
    await enforce_device_rate_limit(session, token_hash, "/api/v1/extractions")
    started = time.perf_counter()
    model_name: str | None = None
    openai_request_id: str | None = None
    try:
        result = await OpenAIGateway().send_extraction(body)
        model_name = result.model_name
        openai_request_id = result.openai_request_id
        await _log(session, token_hash, request.url.path, 200, result.latency_ms, model_name, openai_request_id, None)
        await session.commit()
        return ExtractionResponse(
            rawResponseText=result.output_text,
            requestJSON=result.request_json,
            modelName=result.model_name,
        )
    except OpenAIGatewayError as exc:
        await _log(session, token_hash, request.url.path, exc.status_code, _elapsed(started), model_name, openai_request_id, exc.code)
        await session.commit()
        raise HTTPException(status_code=exc.status_code, detail={"code": exc.code, "detail": exc.detail}) from exc


@router.post("/api/v1/web-requests")
async def web_request(
    body: WebRequest,
    request: Request,
    token_hash: str = Depends(require_device_token),
    session: AsyncSession = Depends(get_session),
) -> ExtractionResponse | WebAnswerResponse:
    await record_device_seen(session, token_hash)
    await enforce_device_rate_limit(session, token_hash, "/api/v1/web-requests")
    started = time.perf_counter()
    model_name: str | None = None
    openai_request_id: str | None = None
    try:
        result = await OpenAIGateway().send_web_request(body)
        model_name = result.model_name
        openai_request_id = result.openai_request_id
        await _log(session, token_hash, request.url.path, 200, result.latency_ms, model_name, openai_request_id, None)
        await session.commit()
        if body.mode == "answer":
            return WebAnswerResponse(assistantText=result.output_text, modelName=result.model_name)
        return ExtractionResponse(
            rawResponseText=result.output_text,
            requestJSON=result.request_json,
            modelName=result.model_name,
        )
    except OpenAIGatewayError as exc:
        await _log(session, token_hash, request.url.path, exc.status_code, _elapsed(started), model_name, openai_request_id, exc.code)
        await session.commit()
        raise HTTPException(status_code=exc.status_code, detail={"code": exc.code, "detail": exc.detail}) from exc


@router.get("/api/admin/usage", dependencies=[Depends(require_admin_key)])
async def usage(session: AsyncSession = Depends(get_session)) -> dict:
    devices = await session.scalar(select(func.count()).select_from(DeviceClient))
    requests = await session.scalar(select(func.count()).select_from(AIRequestLog))
    return {"devices": devices or 0, "requests": requests or 0}


async def _log(
    session: AsyncSession,
    token_hash: str,
    endpoint: str,
    status_code: int,
    latency_ms: int,
    model_name: str | None,
    openai_request_id: str | None,
    error_code: str | None,
) -> None:
    session.add(
        AIRequestLog(
            token_hash=token_hash,
            endpoint=endpoint,
            status_code=status_code,
            latency_ms=latency_ms,
            model_name=model_name,
            openai_request_id=openai_request_id,
            error_code=error_code,
        )
    )


def _elapsed(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)
