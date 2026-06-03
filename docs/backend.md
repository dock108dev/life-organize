# Backend

The backend is a private FastAPI gateway for LifeOrganize AI features. The iOS app sends extraction and web requests with a per-device token managed by the app; the backend owns `OPENAI_API_KEY`, builds OpenAI Responses API requests, enrolls active device tokens, rate-limits device tokens, and records request metadata in Postgres.

The iOS app no longer supports direct provider credentials, manual API-key entry, or user-managed device-token setup. AI traffic must go through the backend gateway.

## Public App API

`POST /api/v1/extractions` accepts extraction requests and returns raw provider response text, provider request JSON, and model name.

`POST /api/v1/web-requests` accepts web lookup or web import requests. Answer mode returns assistant text and model name. Import mode returns the same extraction response shape used by `/api/v1/extractions`.

Both routes require:

- `X-LifeOrganize-Device-Token`
- JSON request bodies
- Per-token, per-endpoint rate limit headroom

Short tokens are rejected before provider calls. New valid-length tokens are enrolled as active devices; revoked tokens remain blocked. Request logs store token hashes, endpoint, status, latency, model, provider request ID, and error code. They do not store raw device tokens.

## Admin and Operations API

- `GET /healthz`
- `GET /api/admin/usage`
- `GET /api/admin/logs`
- `GET /api/admin/logs/stream`
- `POST /api/admin/logs/session`
- `POST /api/admin/logs/mark`
- `POST /api/admin/logs/clear`
- `POST /api/admin/logs/logout`
- `GET /admin/logs`, the HTML log panel shell that connects to the authenticated admin API routes.

`GET /` returns a small service/ok payload. FastAPI docs, ReDoc, and OpenAPI JSON are available only outside production/staging.

The log panel uses `LIFE_ORGANIZE_ADMIN_API_KEY` to create an HTTP-only admin session cookie. In production and staging, that cookie is marked secure.
Admin log sessions are process-local and expire after eight hours. The current Compose deployment runs one API process, so shared session storage is not part of the production path.

## Middleware and Hardening

`RequestSizeLimitMiddleware` rejects request bodies above `MAX_REQUEST_BYTES` with `413` and code `request_too_large`.

`SecurityHeadersMiddleware` adds default security headers to HTTP responses except OPTIONS responses:

- `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`
- `Strict-Transport-Security`
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `Permissions-Policy` disabling camera, microphone, and geolocation

`/admin/logs` provides its own page-specific CSP that allows inline script/style needed by the static HTML shell, sets `Cache-Control: no-store`, and sets `X-Robots-Tag: noindex, nofollow`.

## Local Run

See [Local development](local-development.md) for Docker and direct Python run steps.

Minimal direct run shape:

```sh
cd Backend
DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize \
DEVICE_TOKEN_SIGNING_SECRET=dev-secret \
OPENAI_API_KEY=sk-... \
LIFE_ORGANIZE_ADMIN_API_KEY=dev-admin \
.venv/bin/alembic upgrade head

DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize \
DEVICE_TOKEN_SIGNING_SECRET=dev-secret \
OPENAI_API_KEY=sk-... \
LIFE_ORGANIZE_ADMIN_API_KEY=dev-admin \
.venv/bin/python -m uvicorn main:app --reload --port 8787
```

## Production

- Store the OpenAI key only in backend environment/secrets.
- `OPENAI_MODEL` defaults to `gpt-5.5` in `Backend/app/config.py` and `Backend/infra/docker-compose.yml`.
- Set `DEVICE_TOKEN_SIGNING_SECRET` to a stable private value.
- New app-managed device tokens are enrolled automatically. Existing device rows with non-active status remain blocked.
- Set `LIFE_ORGANIZE_ADMIN_API_KEY` to a stable private value for admin routes and the log panel.
- Run Alembic migrations before replacing the API container. The GitHub deploy workflow and manual runbook use the Compose `migrate` service; the API entrypoint also honors `RUN_MIGRATIONS=true` when that path is used.
- Route `life.dock108.dev` to the API container through the Caddy example in `Backend/infra/`.
- Keep `DATABASE_URL` off localhost for `production` and `staging`; startup validation rejects localhost database URLs in those environments.
