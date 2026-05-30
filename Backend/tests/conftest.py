from __future__ import annotations

import os
from collections.abc import AsyncIterator, Callable, Iterator
from dataclasses import dataclass
from itertools import count
from typing import Any

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

VALID_DEVICE_TOKEN = "device-token-1234567890"
VALID_ADMIN_KEY = "test-admin-key-123"
TEST_TOKEN_HASH = "test-token-hash"

_TEST_ENVIRONMENT = {
    "ENVIRONMENT": "test",
    "DATABASE_URL": "postgresql+asyncpg://test:test@127.0.0.1:1/lifeorganize_test",
    "OPENAI_API_KEY": "test-openai-key",
    "OPENAI_MODEL": "test-model",
    "LIFE_ORGANIZE_ADMIN_API_KEY": VALID_ADMIN_KEY,
    "DEVICE_TOKEN_SIGNING_SECRET": "test-device-signing-secret",
    "REQUEST_TIMEOUT_SECONDS": "3",
    "MAX_REQUEST_BYTES": "16384",
    "DEVICE_RATE_LIMIT_REQUESTS": "60",
    "DEVICE_RATE_LIMIT_WINDOW_SECONDS": "3600",
    "AUTO_ENROLL_DEVICE_TOKENS": "true",
}
_PREVIOUS_ENVIRONMENT = {key: os.environ.get(key) for key in _TEST_ENVIRONMENT}
os.environ.update(_TEST_ENVIRONMENT)

from app import auth  # noqa: E402
from app.admin_events import admin_events  # noqa: E402
from app.config import settings  # noqa: E402
from app.db import Base, get_session  # noqa: E402
from app.routers import admin, ai  # noqa: E402
from app.services.openai_gateway import GatewayResult, OpenAIGatewayError  # noqa: E402
from main import app as fastapi_app  # noqa: E402

for key, value in _PREVIOUS_ENVIRONMENT.items():
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value


@dataclass
class RouteSession:
    scalar_values: list[Any]
    added: list[Any]
    commits: int = 0
    executed: int = 0

    async def scalar(self, statement: Any) -> Any:
        if self.scalar_values:
            return self.scalar_values.pop(0)
        return 0

    async def execute(self, statement: Any) -> None:
        self.executed += 1

    def add(self, item: Any) -> None:
        self.added.append(item)

    async def commit(self) -> None:
        self.commits += 1


class SyncRouteSession:
    def __init__(self, session: Session) -> None:
        self.session = session

    async def scalar(self, statement: Any) -> Any:
        return self.session.scalar(statement)

    async def execute(self, statement: Any) -> None:
        self.session.execute(statement)

    def add(self, item: Any) -> None:
        self.session.add(item)

    async def commit(self) -> None:
        self.session.commit()

    def count(self, model: type[Any]) -> int:
        return self.session.scalar(select(func.count()).select_from(model)) or 0

    def all(self, model: type[Any]) -> list[Any]:
        return list(self.session.scalars(select(model)))


@dataclass
class StubOpenAIGateway:
    extraction_result: GatewayResult | None = None
    web_result: GatewayResult | None = None
    extraction_error: OpenAIGatewayError | None = None
    web_error: OpenAIGatewayError | None = None
    extraction_requests: list[Any] | None = None
    web_requests: list[Any] | None = None

    def __post_init__(self) -> None:
        self.extraction_requests = []
        self.web_requests = []

    async def send_extraction(self, request: Any) -> GatewayResult:
        assert self.extraction_requests is not None
        self.extraction_requests.append(request)
        if self.extraction_error is not None:
            raise self.extraction_error
        return self.extraction_result or gateway_result()

    async def send_web_request(self, request: Any) -> GatewayResult:
        assert self.web_requests is not None
        self.web_requests.append(request)
        if self.web_error is not None:
            raise self.web_error
        return self.web_result or gateway_result()


def gateway_result(
    *,
    output_text: str = '{"events":[]}',
    request_json: str = '{"fixture":true}',
    model_name: str = "test-model",
    openai_request_id: str | None = "req_test",
    latency_ms: int = 12,
) -> GatewayResult:
    return GatewayResult(
        output_text=output_text,
        request_json=request_json,
        model_name=model_name,
        openai_request_id=openai_request_id,
        latency_ms=latency_ms,
    )


@pytest.fixture(autouse=True)
def isolated_backend_state(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    app_settings = {
        "environment": "test",
        "database_url": "postgresql+asyncpg://test:test@127.0.0.1:1/lifeorganize_test",
        "openai_api_key": "test-openai-key",
        "openai_model": "test-model",
        "admin_api_key": VALID_ADMIN_KEY,
        "device_token_signing_secret": "test-device-signing-secret",
        "request_timeout_seconds": 3,
        "max_request_bytes": 16_384,
        "device_rate_limit_requests": 60,
        "device_rate_limit_window_seconds": 3600,
        "auto_enroll_device_tokens": True,
    }
    for name, value in app_settings.items():
        monkeypatch.setattr(settings, name, value)
    fastapi_app.dependency_overrides.clear()
    admin._admin_sessions.clear()
    admin_events._events.clear()
    admin_events._subscribers.clear()
    admin_events._ids = count(1)

    yield

    fastapi_app.dependency_overrides.clear()
    admin._admin_sessions.clear()
    admin_events._events.clear()
    admin_events._subscribers.clear()
    admin_events._ids = count(1)


@pytest.fixture
def backend_app() -> FastAPI:
    return fastapi_app


@pytest.fixture
def client(backend_app: FastAPI) -> Iterator[TestClient]:
    with TestClient(backend_app) as test_client:
        yield test_client


@pytest.fixture
async def async_client(backend_app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=backend_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        yield test_client


@pytest.fixture
def settings_override() -> Any:
    return settings


@pytest.fixture
def route_session(backend_app: FastAPI) -> Iterator[RouteSession]:
    session = RouteSession(scalar_values=[None, 0], added=[])

    async def fake_get_session() -> AsyncIterator[RouteSession]:
        yield session

    backend_app.dependency_overrides[get_session] = fake_get_session
    yield session
    backend_app.dependency_overrides.pop(get_session, None)


@pytest.fixture
def sqlite_route_session(backend_app: FastAPI) -> Iterator[SyncRouteSession]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    db_session = session_factory()
    session = SyncRouteSession(db_session)

    async def fake_get_session() -> AsyncIterator[SyncRouteSession]:
        yield session

    backend_app.dependency_overrides[get_session] = fake_get_session
    yield session
    backend_app.dependency_overrides.pop(get_session, None)
    db_session.close()
    engine.dispose()


@pytest.fixture
def db_client(
    backend_app: FastAPI,
    sqlite_route_session: SyncRouteSession,
) -> Iterator[TestClient]:
    with TestClient(backend_app) as test_client:
        yield test_client


@pytest.fixture
def token_hash_override(backend_app: FastAPI) -> Iterator[str]:
    async def fake_device_token() -> str:
        return TEST_TOKEN_HASH

    backend_app.dependency_overrides[auth.require_device_token] = fake_device_token
    yield TEST_TOKEN_HASH
    backend_app.dependency_overrides.pop(auth.require_device_token, None)


@pytest.fixture
def install_gateway_stub(
    monkeypatch: pytest.MonkeyPatch,
) -> Callable[..., StubOpenAIGateway]:
    def install(
        *,
        extraction_result: GatewayResult | None = None,
        web_result: GatewayResult | None = None,
        extraction_error: OpenAIGatewayError | None = None,
        web_error: OpenAIGatewayError | None = None,
    ) -> StubOpenAIGateway:
        gateway = StubOpenAIGateway(
            extraction_result=extraction_result,
            web_result=web_result,
            extraction_error=extraction_error,
            web_error=web_error,
        )
        monkeypatch.setattr(ai, "OpenAIGateway", lambda: gateway)
        return gateway

    return install


@pytest.fixture
def device_headers() -> dict[str, str]:
    return {"x-lifeorganize-device-token": VALID_DEVICE_TOKEN}


@pytest.fixture
def admin_headers() -> dict[str, str]:
    return {"x-admin-api-key": VALID_ADMIN_KEY}


@pytest.fixture
def extraction_request_body() -> dict[str, Any]:
    return {
        "text": "Changed the hallway filter today.",
        "currentDate": "2027-01-15",
        "currentDateTime": "2027-01-15T17:30:00Z",
        "timezone": "America/New_York",
    }


@pytest.fixture
def web_answer_request_body(extraction_request_body: dict[str, Any]) -> dict[str, Any]:
    return {**extraction_request_body, "mode": "answer"}
