from __future__ import annotations

import pytest
from fastapi import HTTPException
from starlette.requests import Request

import app.auth as auth
from app.config import Settings


def _request() -> Request:
    return Request({"type": "http", "headers": []})


async def test_require_device_token_rejects_short_tokens() -> None:
    with pytest.raises(HTTPException) as exc_info:
        await auth.require_device_token(_request(), "short")

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "missing_device_token"


async def test_require_device_token_stores_hash_on_request_state() -> None:
    request = _request()

    token_hash = await auth.require_device_token(request, "device-token-1234567890")

    assert token_hash == request.state.device_token_hash
    assert token_hash == auth.hash_device_token("device-token-1234567890")


def test_admin_key_allows_development_without_config(monkeypatch) -> None:
    monkeypatch.setattr(auth.settings, "environment", "development")
    monkeypatch.setattr(auth.settings, "admin_api_key", None)

    auth.validate_admin_key(None)


def test_admin_key_rejects_invalid_configured_key(monkeypatch) -> None:
    monkeypatch.setattr(auth.settings, "environment", "production")
    monkeypatch.setattr(auth.settings, "admin_api_key", "expected-key")

    with pytest.raises(HTTPException) as exc_info:
        auth.validate_admin_key("wrong-key")

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail["code"] == "invalid_admin_key"


def test_admin_key_reports_production_misconfiguration(monkeypatch) -> None:
    monkeypatch.setattr(auth.settings, "environment", "production")
    monkeypatch.setattr(auth.settings, "admin_api_key", None)

    with pytest.raises(HTTPException) as exc_info:
        auth.validate_admin_key(None)

    assert exc_info.value.status_code == 500
    assert exc_info.value.detail["code"] == "admin_auth_misconfigured"


def test_production_settings_require_secrets_and_remote_database() -> None:
    for environment in ("production", "staging"):
        with pytest.raises(ValueError, match="Missing required production settings"):
            Settings(
                _env_file=None,
                ENVIRONMENT=environment,
                DATABASE_URL="postgresql+asyncpg://lifeorganize:lifeorganize@db.internal/lifeorganize",
            )

        with pytest.raises(ValueError, match="must not point at localhost"):
            Settings(
                _env_file=None,
                ENVIRONMENT=environment,
                OPENAI_API_KEY="openai-key",
                LIFE_ORGANIZE_ADMIN_API_KEY="admin-key",
                DEVICE_TOKEN_SIGNING_SECRET="signing-secret",
                DATABASE_URL="postgresql+asyncpg://lifeorganize:lifeorganize@localhost/lifeorganize",
            )

    production_settings = Settings(
        _env_file=None,
        ENVIRONMENT="production",
        OPENAI_API_KEY="openai-key",
        LIFE_ORGANIZE_ADMIN_API_KEY="admin-key",
        DEVICE_TOKEN_SIGNING_SECRET="signing-secret",
        DATABASE_URL="postgresql+asyncpg://lifeorganize:lifeorganize@db.internal/lifeorganize",
    )

    development_settings = Settings(_env_file=None)

    assert production_settings.environment == "production"
    assert not hasattr(production_settings, "auto_" + "enroll_device_tokens")
    assert development_settings.environment == "development"
    assert development_settings.openai_api_key is None
    assert "localhost" in development_settings.database_url


def test_removed_auto_enrollment_config_fails_hard(monkeypatch) -> None:
    monkeypatch.setenv("AUTO_" + "ENROLL_DEVICE_TOKENS", "true")

    with pytest.raises(RuntimeError, match="Legacy path removed"):
        Settings(_env_file=None)


async def test_device_token_auth_has_no_expiration_claim_contract() -> None:
    request = _request()

    token_hash = await auth.require_device_token(request, "expired-token-000000")

    assert token_hash == request.state.device_token_hash
    assert token_hash == auth.hash_device_token("expired-token-000000")


async def test_rate_limit_rejection_sets_retry_after(monkeypatch) -> None:
    class FakeSession:
        async def scalar(self, _statement):
            return 3

    monkeypatch.setattr(auth.settings, "device_rate_limit_requests", 3)
    monkeypatch.setattr(auth.settings, "device_rate_limit_window_seconds", 45)

    with pytest.raises(HTTPException) as exc_info:
        await auth.enforce_device_rate_limit(FakeSession(), "token-hash", "/api/v1/extractions")

    assert exc_info.value.status_code == 429
    assert exc_info.value.headers == {"Retry-After": "45"}
    assert exc_info.value.detail["code"] == "rate_limited"
