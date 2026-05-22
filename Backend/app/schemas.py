from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ExtractionRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8_000)
    currentDate: str = Field(min_length=10, max_length=10)
    currentDateTime: str = Field(min_length=10, max_length=64)
    timezone: str = Field(min_length=1, max_length=128)
    schemaVersion: int = Field(default=1)


class WebRequest(BaseModel):
    text: str = Field(min_length=1, max_length=8_000)
    mode: Literal["answer", "importRecords"]
    currentDate: str = Field(min_length=10, max_length=10)
    currentDateTime: str = Field(min_length=10, max_length=64)
    timezone: str = Field(min_length=1, max_length=128)


class ExtractionResponse(BaseModel):
    rawResponseText: str
    requestJSON: str | None = None
    modelName: str | None = None


class WebAnswerResponse(BaseModel):
    assistantText: str
    modelName: str | None = None


class ErrorResponse(BaseModel):
    code: str
    detail: str
