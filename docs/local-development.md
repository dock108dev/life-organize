# Local Development

## iOS App

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run.

The app can launch without the backend. In that state, user messages are saved locally and backend-dependent extraction stays pending service setup.

Command-line build:

```sh
xcodebuild -project LifeOrganize.xcodeproj \
  -scheme LifeOrganize \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  build CODE_SIGNING_ALLOWED=NO
```

Command-line test:

```sh
xcodebuild test -project LifeOrganize.xcodeproj \
  -scheme LifeOrganize \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO
```

## Backend with Docker

Start the local backend and Postgres from the repo root:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build
```

Default local bindings:

- API: `http://127.0.0.1:8787`
- Postgres: `127.0.0.1:5433`

The API container proxies Uvicorn on container port `8000`. Health check:

```sh
curl -fsS http://127.0.0.1:8787/healthz
```

Point the app at the local backend with:

```text
-ai-service-base-url=http://127.0.0.1:8787
```

## Backend without Docker

The backend supports Python `>=3.13`.

```sh
python3 -m venv Backend/.venv
Backend/.venv/bin/pip install -r Backend/requirements.txt
```

Run from `Backend/`:

```sh
cd Backend
DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize \
DEVICE_TOKEN_SIGNING_SECRET=dev-secret \
OPENAI_API_KEY=sk-... \
LIFE_ORGANIZE_ADMIN_API_KEY=dev-admin \
.venv/bin/python -m uvicorn main:app --reload --port 8787
```

Production and staging reject missing required secrets and localhost database URLs. Development does not.

## Device Tokens

Backend device-token auto-enrollment is not supported. The backend accepts only tokens whose HMAC hash already exists in `device_clients` with `status='active'`.

For local manual testing with Docker, choose a raw token with at least 16 characters, compute the hash with the same signing secret used by the backend, then insert it:

```sh
DEVICE_TOKEN_SIGNING_SECRET=development-device-token-secret \
DEVICE_TOKEN=local-device-token-0001 \
python3 - <<'PY'
import hashlib
import hmac
import os

secret = os.environ["DEVICE_TOKEN_SIGNING_SECRET"]
token = os.environ["DEVICE_TOKEN"]
print(hmac.new(secret.encode(), token.encode(), hashlib.sha256).hexdigest())
PY
```

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev exec postgres \
  psql -U lifeorganize -d lifeorganize \
  -c "insert into device_clients (token_hash, status) values ('<hash>', 'active') on conflict (token_hash) do update set status = 'active', revoked_at = null;"
```

Use the raw token in the app's AI service token setting. The backend stores only the HMAC hash.

## Admin Log Panel

Open the local log panel at:

```text
http://127.0.0.1:8787/admin/logs
```

Use `LIFE_ORGANIZE_ADMIN_API_KEY` to open a session. The page keeps the admin key in page state only, then uses an HTTP-only session cookie for subsequent log reads and streaming.

## Local Verification

Common local gates:

```sh
Scripts/verify-backend.sh
Scripts/verify-ios.sh
Scripts/screenshots/run-screenshot-tests.sh compare
Scripts/run-dynamic-type-ui-smoke.sh
Scripts/run-adaptive-screen-validation.sh compare
Scripts/verify-all.sh
```

`Scripts/verify-all.sh` runs backend checks, iOS tests and coverage, screenshot comparison, and optional smoke checks. Backend Docker smoke and production smoke are opt-in.
