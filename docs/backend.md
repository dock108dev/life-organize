# Backend

The backend is a small private FastAPI gateway for LifeOrganize AI features. The iOS app sends requests with a per-device service token; the backend owns `OPENAI_API_KEY`, builds provider requests, calls the OpenAI Responses API, rate-limits device tokens, and records request metadata in Postgres.

## Local Run

Create the backend virtual environment from the repo root:

```sh
python3 -m venv Backend/.venv
Backend/.venv/bin/pip install -r Backend/requirements.txt
```

Run the API from `Backend/`:

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

Point the iOS app at the local backend with:

```sh
-ai-service-base-url=http://127.0.0.1:8787
```

Open the local backend log/control panel at:

```text
http://127.0.0.1:8787/admin/logs
```

Use `LIFE_ORGANIZE_ADMIN_API_KEY` from `Backend/.env` to connect. The page streams request and OpenAI gateway events, including status, latency, model, and OpenAI request IDs. It does not log raw user text, API keys, or raw model responses.

## Production

- Store the OpenAI key only in backend environment/secrets.
- The local/default model is `gpt-5.5`, matching OpenAI's current frontier model guidance for complex work.
- Set `DEVICE_TOKEN_SIGNING_SECRET` to a stable private value.
- Set `RUN_MIGRATIONS=true` during deploy or run Alembic manually.
- Route `life.dock108.dev` to the API container through the Caddy example in `Backend/infra/`.
- Do not log raw user text or raw OpenAI responses by default.
