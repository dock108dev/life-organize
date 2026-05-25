from __future__ import annotations

import json
import os
import subprocess
import sys
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import app.auth as auth
from app.db import get_session
from app.models import AIRequestLog, DeviceClient
from app.services.openai_gateway import GatewayResult

pytestmark = pytest.mark.skipif(
    os.getenv("LIFE_ORGANIZE_RUN_POSTGRES_TESTS") != "1",
    reason="PostgreSQL smoke tests require LIFE_ORGANIZE_RUN_POSTGRES_TESTS=1.",
)

BACKEND_DIR = Path(__file__).resolve().parents[1]
ALEMBIC_REVISION = "20260522_000001"
EXPECTED_TABLES = {"ai_request_logs", "alembic_version", "device_clients"}
EXPECTED_DEVICE_CLIENT_COLUMNS = {
    "id",
    "token_hash",
    "first_seen_at",
    "last_seen_at",
    "request_count",
}
EXPECTED_AI_REQUEST_LOG_COLUMNS = {
    "id",
    "token_hash",
    "endpoint",
    "status_code",
    "latency_ms",
    "model_name",
    "openai_request_id",
    "error_code",
    "created_at",
    "notes",
}
EXPECTED_INDEXES = {
    "ix_ai_request_logs_created_at",
    "ix_ai_request_logs_token_hash",
    "ix_device_clients_token_hash",
}


@pytest.fixture
def postgres_database_url() -> str:
    database_url = os.getenv("LIFE_ORGANIZE_POSTGRES_TEST_DATABASE_URL") or os.getenv(
        "DATABASE_URL"
    )
    if not database_url:
        pytest.skip("PostgreSQL test database URL is not configured.")
    return database_url


@pytest.fixture
async def migrated_database_url(postgres_database_url: str) -> AsyncIterator[str]:
    await _reset_public_schema(postgres_database_url)
    result = _run_alembic_upgrade(postgres_database_url)
    assert result.returncode == 0, result.stderr
    yield postgres_database_url
    await _reset_public_schema(postgres_database_url)


async def test_alembic_upgrade_head_creates_expected_schema_and_is_idempotent(
    postgres_database_url: str,
) -> None:
    await _reset_public_schema(postgres_database_url)
    try:
        first_result = _run_alembic_upgrade(postgres_database_url)
        assert first_result.returncode == 0, first_result.stderr
        first_snapshot = await _schema_snapshot(postgres_database_url)

        second_result = _run_alembic_upgrade(postgres_database_url)
        assert second_result.returncode == 0, second_result.stderr
        second_snapshot = await _schema_snapshot(postgres_database_url)

        assert EXPECTED_TABLES.issubset(first_snapshot["tables"])
        assert EXPECTED_DEVICE_CLIENT_COLUMNS.issubset(first_snapshot["columns"]["device_clients"])
        assert EXPECTED_AI_REQUEST_LOG_COLUMNS.issubset(first_snapshot["columns"]["ai_request_logs"])
        assert EXPECTED_INDEXES.issubset(first_snapshot["indexes"])
        assert first_snapshot["version_rows"] == [ALEMBIC_REVISION]
        assert second_snapshot == first_snapshot
    finally:
        await _reset_public_schema(postgres_database_url)


async def test_request_route_persists_metadata_without_sensitive_fields(
    migrated_database_url: str,
    backend_app: FastAPI,
    async_client,
    install_gateway_stub,
    device_headers: dict[str, str],
    extraction_request_body: dict[str, Any],
) -> None:
    raw_device_token = device_headers["x-lifeorganize-device-token"]
    raw_user_text = extraction_request_body["text"]
    engine = create_async_engine(migrated_database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def postgres_session() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    backend_app.dependency_overrides[get_session] = postgres_session
    install_gateway_stub(
        extraction_result=GatewayResult(
            output_text='{"events":[]}',
            request_json='{"notStored":"provider payload"}',
            model_name="test-model",
            openai_request_id="req_postgres_metadata",
            latency_ms=37,
        )
    )

    try:
        response = await async_client.post(
            "/api/v1/extractions",
            headers=device_headers,
            json=extraction_request_body,
        )

        assert response.status_code == 200
        async with session_factory() as session:
            request_log = await session.scalar(
                select(AIRequestLog).where(
                    AIRequestLog.openai_request_id == "req_postgres_metadata"
                )
            )
            device_client = await session.scalar(
                select(DeviceClient).where(
                    DeviceClient.token_hash == auth.hash_device_token(raw_device_token)
                )
            )

        assert request_log is not None
        assert device_client is not None
        assert request_log.id is not None
        assert request_log.created_at is not None
        assert request_log.token_hash == device_client.token_hash
        assert request_log.endpoint == "/api/v1/extractions"
        assert request_log.status_code == 200
        assert request_log.latency_ms == 37
        assert request_log.model_name == "test-model"
        assert request_log.error_code is None
        persisted_metadata = json.dumps(
            {
                "device": device_client.token_hash,
                "request": {
                    "token_hash": request_log.token_hash,
                    "endpoint": request_log.endpoint,
                    "status_code": request_log.status_code,
                    "latency_ms": request_log.latency_ms,
                    "model_name": request_log.model_name,
                    "openai_request_id": request_log.openai_request_id,
                    "error_code": request_log.error_code,
                    "notes": request_log.notes,
                },
            },
            sort_keys=True,
            default=str,
        )
        assert raw_device_token not in persisted_metadata
        assert raw_user_text not in persisted_metadata
    finally:
        backend_app.dependency_overrides.pop(get_session, None)
        await engine.dispose()


async def test_failed_transaction_rolls_back_request_log(migrated_database_url: str) -> None:
    engine = create_async_engine(migrated_database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            session.add(
                AIRequestLog(
                    token_hash="sha256:rollback-device-token",
                    endpoint="/api/v1/extractions",
                    status_code=200,
                    latency_ms=111,
                    model_name="test-model",
                    openai_request_id="req_should_not_persist",
                    error_code=None,
                    notes="this row should roll back",
                )
            )
            session.add(DeviceClient(token_hash="sha256:duplicate-token", request_count=1))
            session.add(DeviceClient(token_hash="sha256:duplicate-token", request_count=2))

            with pytest.raises(IntegrityError):
                await session.commit()
            await session.rollback()

        async with session_factory() as session:
            request_log = await session.scalar(
                select(AIRequestLog).where(
                    AIRequestLog.openai_request_id == "req_should_not_persist"
                )
            )

        assert request_log is None
    finally:
        await engine.dispose()


def test_alembic_upgrade_fails_with_unreachable_database() -> None:
    result = _run_alembic_upgrade(
        "postgresql+asyncpg://lifeorganize:lifeorganize@127.0.0.1:1/lifeorganize",
        timeout=10,
    )

    assert result.returncode != 0
    assert any(
        signal in result.stderr.lower()
        for signal in (
            "connect call failed",
            "connectionrefusederror",
            "connection refused",
            "could not connect",
        )
    )


def _run_alembic_upgrade(database_url: str, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    env["ENVIRONMENT"] = "test"
    return subprocess.run(
        [sys.executable, "-m", "alembic", "-c", "alembic.ini", "upgrade", "head"],
        cwd=BACKEND_DIR,
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


async def _reset_public_schema(database_url: str) -> None:
    engine = create_async_engine(database_url, isolation_level="AUTOCOMMIT")
    try:
        async with engine.connect() as connection:
            await connection.execute(text("drop schema if exists public cascade"))
            await connection.execute(text("create schema public"))
    finally:
        await engine.dispose()


async def _schema_snapshot(database_url: str) -> dict[str, Any]:
    engine = create_async_engine(database_url, pool_pre_ping=True)
    try:
        async with engine.connect() as connection:
            tables = set(
                await connection.scalars(
                    text(
                        "select table_name from information_schema.tables "
                        "where table_schema = 'public' order by table_name"
                    )
                )
            )
            columns = {
                "device_clients": set(await _column_names(connection, "device_clients")),
                "ai_request_logs": set(await _column_names(connection, "ai_request_logs")),
            }
            indexes = set(
                await connection.scalars(
                    text(
                        "select indexname from pg_indexes "
                        "where schemaname = 'public' "
                        "and tablename in ('device_clients', 'ai_request_logs') "
                        "order by indexname"
                    )
                )
            )
            version_rows = list(
                await connection.scalars(text("select version_num from alembic_version"))
            )
        return {
            "tables": tables,
            "columns": columns,
            "indexes": indexes,
            "version_rows": version_rows,
        }
    finally:
        await engine.dispose()


async def _column_names(connection: Any, table_name: str) -> list[str]:
    return list(
        await connection.scalars(
            text(
                "select column_name from information_schema.columns "
                "where table_schema = 'public' and table_name = :table_name "
                "order by ordinal_position"
            ),
            {"table_name": table_name},
        )
    )
