# Environment and Runtime Configuration

This document lists runtime inputs that are read by the current codebase. Removed or unsupported settings are intentionally omitted except where startup fails hard.

## Backend Environment

Backend settings are loaded by `Backend/app/config.py` from process environment and `Backend/.env`.

| Variable | Default | Used for |
| --- | --- | --- |
| `ENVIRONMENT` | `development` | Controls production/staging validation and disables FastAPI docs/OpenAPI in production and staging. |
| `DATABASE_URL` | local Postgres URL on port `5432` | Async SQLAlchemy database URL. Docker Compose injects an internal `postgres:5432` URL. |
| `OPENAI_API_KEY` | empty | Provider credential used only by the backend. Required in production/staging. |
| `OPENAI_MODEL` | `gpt-5.5` | Provider model name. |
| `LIFE_ORGANIZE_ADMIN_API_KEY` | empty | Admin API/log panel credential. Required in production/staging. |
| `DEVICE_TOKEN_SIGNING_SECRET` | empty | Secret used to HMAC device tokens. Required in production/staging. |
| `REQUEST_TIMEOUT_SECONDS` | `30` | Provider request timeout. |
| `MAX_REQUEST_BYTES` | `16384` | Request body limit enforced by middleware. |
| `DEVICE_RATE_LIMIT_REQUESTS` | `60` | Per-device, per-endpoint request limit. |
| `DEVICE_RATE_LIMIT_WINDOW_SECONDS` | `3600` | Rate-limit window in seconds. |

Device tokens are app-managed and enrolled by the backend on first use. `AUTO_ENROLL_DEVICE_TOKENS` is ignored.

## Docker Compose Environment

`Backend/infra/docker-compose.yml` also reads:

| Variable | Default | Used for |
| --- | --- | --- |
| `POSTGRES_DB` | `lifeorganize` | Database name for the Postgres container. |
| `POSTGRES_USER` | `lifeorganize` | Database user. |
| `POSTGRES_PASSWORD` | `lifeorganize` | Database password. |
| `POSTGRES_PORT` | `5433` | Host port bound to Postgres on `127.0.0.1`. |
| `API_PORT` | `8787` | Host port bound to the API on `127.0.0.1`. |
| `RUN_MIGRATIONS` | `false` | When true, the API entrypoint runs Alembic before starting Uvicorn. |
| `IMAGE_TAG` | `latest` | Backend image tag for Compose pull/build. |

`Backend/.env.example` is the local template. `Backend/.env` is intentionally ignored.

## iOS Runtime Arguments

`AppRuntimeConfiguration` reads launch arguments from `ProcessInfo.processInfo.arguments`.

| Argument | Effect |
| --- | --- |
| `-ui-testing` | Enables automation runtime. |
| `-screenshot-mode` | Enables screenshot runtime, deterministic defaults, isolated store, fixed default screenshot date, fake extractor, and disabled animations. |
| `-use-fake-extractor` | Uses `DeterministicMessageExtractionClient`. |
| `-reset-store` | Removes the isolated automation store. |
| `-reset-device-token` | Resets automation defaults and deletes the automation device token. |
| `-skip-launch-maintenance` | Skips launch maintenance in automation runtime. |
| `-use-in-memory-store` | Uses an in-memory model container in automation. |
| `-enable-developer-mode` | Allows developer mode in UI testing where required. |
| `-disable-developer-mode` | Forces developer mode unavailable in automation. |
| `-unlock-developer-mode` | Unlocks developer mode in automation unless disabled. |
| `-simulate-ai-service-error=<value>` | Simulates service errors in automation only. Supported values are `missing-token`, `network-unavailable`, `timeout`, `rate-limited`, and `server-error`. |
| `-fixed-now=<iso8601>` | Uses a fixed date provider when parsing succeeds. |
| `-ai-service-base-url=<url>` | Overrides the backend base URL. Non-loopback HTTP URLs are accepted only in automation. |
| `-seed-scenario=<id>` | Loads a seed scenario in automation. Can be repeated. |
| `-initial-tab=<tab>` | Selects the initial app tab. |
| `-screenshot-seed=<seed>` | Selects screenshot seed data. |
| `-screenshot-start=<route>` | Selects the screenshot start route. |
| `-screenshot-search-query=<text>` | Preloads search text for screenshot mode. |
| `-screenshot-locale=<identifier>` | Overrides locale for screenshots. |
| `-screenshot-time-zone=<identifier>` | Overrides time zone and process default time zone for screenshots. |
| `-screenshot-calendar=<identifier>` | Overrides calendar for screenshots. |
| `-screenshot-appearance=<light\|dark>` | Forces color scheme for screenshots. |
| `-disable-animations` | Disables animations. Screenshot mode also disables animations. |

Legacy double-dash aliases are not supported.

## UI Test Environment

`LifeOrganizeUITests` can read:

- `LIFE_ORGANIZE_SCENARIO_ARTIFACTS_DIR`: passed into the app as the scenario artifacts directory.
- `LIFE_ORGANIZE_SCENARIO_SCREENSHOTS_DIR`: used by UI tests to copy attached screenshots to a caller-provided directory.

## Verification Script Environment

The verification scripts expose focused overrides:

- `IOS_PROJECT`, `IOS_SCHEME`, `IOS_DEVICE_NAME`, `IOS_DEVICE_OS`, `IOS_DESTINATION`, `IOS_RESULT_BUNDLE`, `IOS_DERIVED_DATA`, `IOS_TEST_LOG`, `IOS_COVERAGE_THRESHOLD`, `IOS_SKIP_COVERAGE_GATE`.
- `BACKEND_PYTHON`, `BACKEND_VENV`, `BACKEND_RUFF_VERSION`, `BACKEND_SMOKE_URL`, `API_PORT`.
- `SCREENSHOT_PROJECT`, `SCREENSHOT_SCHEME`, `SCREENSHOT_TARGET_KEY`, `SCREENSHOT_DEVICE_NAME`, `SCREENSHOT_DEVICE_OS`, `SCREENSHOT_ORIENTATION`, `SCREENSHOT_APPEARANCE`, `SCREENSHOT_RESULT_BUNDLE`, `SCREENSHOT_ACTUAL_DIR`, `SCREENSHOT_DIFF_DIR`, `SCREENSHOT_BASELINE_DIR`.
- `ADAPTIVE_SCREEN_*` and `DYNAMIC_TYPE_*` variables documented by the corresponding shell scripts.
