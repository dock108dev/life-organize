# Backend

The backend is a private FastAPI gateway for LifeOrganize AI features. The iOS app sends extraction and web requests with a per-device service token; the backend owns `OPENAI_API_KEY`, builds OpenAI Responses API requests, enforces known active device tokens, rate-limits device tokens, and records request metadata in Postgres.

## Public App API

`POST /api/v1/extractions` accepts extraction requests and returns raw provider response text, provider request JSON, and model name.

`POST /api/v1/web-requests` accepts web lookup or web import requests. Answer mode returns assistant text and model name. Import mode returns the same extraction response shape used by `/api/v1/extractions`.

Both routes require:

- `X-LifeOrganize-Device-Token`
- JSON request bodies
- A token hash present in `device_clients` with `status='active'`
- Per-token, per-endpoint rate limit headroom

Unknown, revoked, or short tokens are rejected before provider calls. Request logs store token hashes, endpoint, status, latency, model, provider request ID, and error code. They do not store raw device tokens.

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

See [Local development](local-development.md) for Docker, direct Python, and local device-token enrollment steps.

Minimal direct run shape:

```sh
cd Backend
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
- Device token auto-enrollment is no longer supported. Known device token hashes must exist in `device_clients` with `status='active'`; unknown tokens receive `unknown_device_token`.
- Set `LIFE_ORGANIZE_ADMIN_API_KEY` to a stable private value for admin routes and the log panel.
- Run Alembic migrations before replacing the API container. The GitHub deploy workflow and manual runbook use the Compose `migrate` service; the API entrypoint also honors `RUN_MIGRATIONS=true` when that path is used.
- Route `life.dock108.dev` to the API container through the Caddy example in `Backend/infra/`.
- Keep `DATABASE_URL` off localhost for `production` and `staging`; startup validation rejects localhost database URLs in those environments.
