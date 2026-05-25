# Backend

The backend is a private FastAPI gateway for LifeOrganize AI features. The iOS app sends extraction and web requests with a per-device service token; the backend owns `OPENAI_API_KEY`, builds OpenAI Responses API requests, rate-limits device tokens, and records request metadata in Postgres.

The app routes to:

- `POST /api/v1/extractions`
- `POST /api/v1/web-requests`

Admin and operations surfaces are:

- `GET /healthz`
- `GET /api/admin/usage`
- `GET /api/admin/logs`
- `GET /api/admin/logs/stream`
- `POST /api/admin/logs/session`
- `POST /api/admin/logs/mark`
- `POST /api/admin/logs/clear`
- `GET /admin/logs`, the HTML log panel shell that connects to the authenticated admin API routes.

## Local Run

The backend supports Python `>=3.11`. Create the virtual environment from the repo root:

```sh
python3 -m venv Backend/.venv
Backend/.venv/bin/pip install -r Backend/requirements.txt
```

Run the API from `Backend/` with the environment required by `Backend/app/config.py`:

```sh
DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize \
DEVICE_TOKEN_SIGNING_SECRET=dev-secret \
OPENAI_API_KEY=sk-... \
uvicorn main:app --reload --port 8787
```

Or run the local Docker stack from the repo root:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build
```

The Compose stack binds Postgres to `127.0.0.1:5433` by default and the API to `127.0.0.1:8787`, proxying to Uvicorn on container port `8000`.

Point the iOS app at the local backend with:

```sh
-ai-service-base-url=http://127.0.0.1:8787
```

Open the local backend log/control panel at:

```text
http://127.0.0.1:8787/admin/logs
```

Use `LIFE_ORGANIZE_ADMIN_API_KEY` to connect the log panel to the admin API. The page streams request and OpenAI gateway events, including status, latency, model, and OpenAI request IDs. The logged event metadata includes request text length, not raw user text, API keys, or raw model response bodies.

## Production

- Store the OpenAI key only in backend environment/secrets.
- `OPENAI_MODEL` defaults to `gpt-5.5` in `Backend/app/config.py` and `Backend/infra/docker-compose.yml`.
- Set `DEVICE_TOKEN_SIGNING_SECRET` to a stable private value.
- Set `LIFE_ORGANIZE_ADMIN_API_KEY` to a stable private value for admin routes and the log panel.
- Run Alembic migrations before replacing the API container. The GitHub deploy workflow and manual runbook use the Compose `migrate` service; the API entrypoint also honors `RUN_MIGRATIONS=true` when that path is used.
- Route `life.dock108.dev` to the API container through the Caddy example in `Backend/infra/`.
- Keep `DATABASE_URL` off localhost for `production` and `staging`; startup validation rejects localhost database URLs in those environments.
