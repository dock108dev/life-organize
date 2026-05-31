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
export DATABASE_URL=postgresql+asyncpg://lifeorganize:lifeorganize@localhost:5433/lifeorganize
export DEVICE_TOKEN_SIGNING_SECRET=<dev-signing-secret>
export OPENAI_API_KEY=<provider-key>
export LIFE_ORGANIZE_ADMIN_API_KEY=<dev-admin-key>
.venv/bin/python -m uvicorn main:app --reload --port 8787
```

Production and staging reject missing required secrets and localhost database URLs. Development does not.

## Device Tokens

The app manages its device token silently in Keychain. The backend hashes that token, enrolls first-seen valid-length tokens as active devices, and stores only the HMAC hash. Users do not need to paste or manage a token in the app.

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
