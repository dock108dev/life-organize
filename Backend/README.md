# LifeOrganize Backend

Small private AI gateway for the iOS app. The iOS app sends requests to this service with a per-device token; this service owns `OPENAI_API_KEY` and calls the OpenAI Responses API.

## Local Run

```bash
cd /Users/michaelfuscoletti/Desktop/life_organize
python3 -m venv Backend/.venv
Backend/.venv/bin/pip install -r Backend/requirements.txt
cd Backend
DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize \
DEVICE_TOKEN_SIGNING_SECRET=dev-secret \
OPENAI_API_KEY=sk-... \
uvicorn main:app --reload --port 8787
```

Or use Docker Compose from the repo root:

```bash
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build
```

## Production Notes

- Put the OpenAI key only in backend environment/secrets.
- Set `RUN_MIGRATIONS=true` on deploy or run Alembic manually.
- Route `life.dock108.dev` to the API container through Caddy.
- Do not log raw user text or raw OpenAI responses by default.
