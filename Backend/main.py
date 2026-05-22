from __future__ import annotations

from fastapi import FastAPI

from app.config import settings
from app.middleware.request_size import RequestSizeLimitMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.routers.ai import router as ai_router


app = FastAPI(
    title="life-organize-backend",
    version="0.1.0",
    docs_url=None if settings.environment in {"production", "staging"} else "/docs",
    redoc_url=None if settings.environment in {"production", "staging"} else "/redoc",
    openapi_url=None if settings.environment in {"production", "staging"} else "/openapi.json",
)

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestSizeLimitMiddleware)


@app.get("/healthz")
async def healthz() -> dict[str, bool]:
    return {"ok": True}


app.include_router(ai_router)
