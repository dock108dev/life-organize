from __future__ import annotations

import os
from functools import lru_cache

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_LEGACY_ENVIRONMENT_KEYS = ("AUTO_" + "ENROLL_DEVICE_TOKENS",)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=os.path.join(os.path.dirname(__file__), "..", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = Field(default="development", alias="ENVIRONMENT")
    database_url: str = Field(
        default="postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5432/lifeorganize",
        alias="DATABASE_URL",
    )
    openai_api_key: str | None = Field(default=None, alias="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-5.5", alias="OPENAI_MODEL")
    admin_api_key: str | None = Field(default=None, alias="LIFE_ORGANIZE_ADMIN_API_KEY")
    device_token_signing_secret: str | None = Field(
        default=None, alias="DEVICE_TOKEN_SIGNING_SECRET"
    )
    request_timeout_seconds: float = Field(default=30, alias="REQUEST_TIMEOUT_SECONDS")
    max_request_bytes: int = Field(default=16_384, alias="MAX_REQUEST_BYTES")
    device_rate_limit_requests: int = Field(default=60, alias="DEVICE_RATE_LIMIT_REQUESTS")
    device_rate_limit_window_seconds: int = Field(
        default=3600,
        alias="DEVICE_RATE_LIMIT_WINDOW_SECONDS",
    )

    @model_validator(mode="after")
    def validate_runtime_settings(self) -> Settings:
        if any(os.getenv(key) is not None for key in _LEGACY_ENVIRONMENT_KEYS):
            raise RuntimeError("Legacy path removed — use SSOT implementation")
        if self.environment in {"production", "staging"}:
            missing = [
                name
                for name, value in [
                    ("OPENAI_API_KEY", self.openai_api_key),
                    ("LIFE_ORGANIZE_ADMIN_API_KEY", self.admin_api_key),
                    ("DEVICE_TOKEN_SIGNING_SECRET", self.device_token_signing_secret),
                    ("DATABASE_URL", self.database_url),
                ]
                if not value
            ]
            if missing:
                raise ValueError(f"Missing required production settings: {', '.join(missing)}")
            if "localhost" in self.database_url or "127.0.0.1" in self.database_url:
                raise ValueError("DATABASE_URL must not point at localhost in production/staging.")
        return self


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
