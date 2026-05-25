# Findings

## Repository and AIDLC State

- The repo root contains the owner braindump at `BRAINDUMP.md`, iOS app code under `LifeOrganize/`, iOS unit tests under `LifeOrganizeTests/`, iOS UI tests under `LifeOrganizeUITests/`, backend code under `Backend/`, screenshot tooling under `Scripts/screenshots/`, screenshot baselines under `Tests/ScreenshotBaselines/`, docs under `docs/`, and Fastlane lanes under `fastlane/Fastfile`.
- `.aidlc/research/` does not exist in the current tree. Existing AIDLC files are run/config/archive state under `.aidlc/`, including `.aidlc/config.json`, `.aidlc/run.lock`, `.aidlc/runs/aidlc_20260524_153916/*`, and archived `planning_index.md` files.
- There are no local full-gate scripts at `Scripts/verify-backend.sh`, `Scripts/verify-ios.sh`, or `Scripts/verify-all.sh`; the only files under `Scripts/` are screenshot scripts.

## Frontend Environment Model and AI Service Boundary

- The iOS default backend URL is wired in both `LifeOrganize/Utilities/AppRuntimeConfiguration.swift` and `LifeOrganize/Services/AIServiceClient.swift` as `https://life.dock108.dev`.
- Explicit local override is wired through launch arguments `-ai-service-base-url=` and `--ai-service-base-url=` in `LifeOrganize/Utilities/AppRuntimeConfiguration.swift`. Invalid or absent override values fall back to the production URL.
- `AppRuntimeConfiguration.messageExtractionClient(deviceTokenStore:)` and `webRequestClient(deviceTokenStore:)` construct backend-facing clients unless deterministic extraction is enabled; deterministic extraction is enabled by `-use-fake-extractor` or screenshot mode.
- `LifeOrganize/Services/AIServiceClient.swift` posts to `/api/v1/extractions` and `/api/v1/web-requests`, sets `X-LifeOrganize-Device-Token`, uses JSON, applies a 30-second timeout, decodes backend responses, and maps HTTP/transport failures into `AppError`.
- The frontend no longer has direct OpenAI DTO files in the paths guarded by `LifeOrganizeTests/AIServiceClientTests.swift`; `LifeOrganizeTests/LegacyProviderGuardrailTests.swift` also scans for legacy provider terms.
- Device tokens are app-owned, not provider secrets. `LifeOrganize/Services/DeviceTokenStore.swift` persists a generated UUID-based token in Keychain for normal app runs and uses `InMemoryDeviceTokenStore` for automation.
- `LifeOrganize/AppRootView.swift` calls `deviceTokenStore.ensureDeviceToken()` on appear when reloading AI service state, so normal launches create a service token automatically. Settings can reset/prepare the service token through `LifeOrganize/Features/Settings/SettingsView.swift`.
- Unit tests cover request DTO shape, absent legacy direct-provider DTOs, missing token handling, retryable service failures, token rejection, HTTP failure mapping, timeout mapping, and debug request text not containing the token in `LifeOrganizeTests/AIServiceClientTests.swift`.
- Current tests do not include an explicit assertion that default frontend configuration equals `https://life.dock108.dev`; the production URL is present in implementation and docs but not directly asserted in the scanned tests.

## Chat Send, Retry, Idempotency, and Offline Behavior

- Chat send flow is implemented in `LifeOrganize/Services/ChatSendService.swift`. It trims input, classifies intent, persists the raw user `ChatMessage` locally before extraction, creates an `ExtractionAttempt`, transitions to extracting, calls the extraction or web client, then either completes, fails, or writes a recall answer.
- Web lookup/import paths are routed in `ChatSendService.sendWebRequest(...)`; `webLookup` creates a local user message and assistant answer, while `webImport` creates extraction attempts and records.
- Retry is implemented in `LifeOrganize/Services/ChatSendServiceRetry.swift`; it increments attempt count, creates a new `ExtractionAttempt`, and reuses the same completion/failure path.
- Idempotency helpers are implemented in `LifeOrganize/Services/ChatSendServiceIdempotency.swift`, checking existing events/rules/notes by source message and source client ID.
- Failure mapping is implemented in `LifeOrganize/Services/ChatSendServiceFailures.swift`. Missing or invalid service tokens become `pendingToken`; network, timeout, rate-limit, server, and unknown errors become retryable `pendingRetry` with exponential retry scheduling.
- `LifeOrganizeTests/ChatSendServiceTests.swift`, `LifeOrganizeTests/AIServiceClientTests.swift`, `LifeOrganizeTests/ChatSendServiceIdempotencyTests.swift`, `LifeOrganizeTests/ManualExtractionRetryServiceTests.swift`, `LifeOrganizeTests/ContinuityScenarioRegressionTests.swift`, and `LifeOrganizeTests/LocalDataClearServiceTests.swift` cover portions of local-save-first, failure fallback, retry, idempotency, and stale async completion behavior.
- UI tests use fake extraction by default via `LifeOrganizeUITests/UITestSupport.swift`, so routine UI coverage does not make live OpenAI calls.

## SwiftData Persistence, Migrations, Seeds, and Local Data Clearing

- The active SwiftData container is created by `LifeOrganize/Persistence/ModelContainerFactory.swift` with `LifeOrganizeSchemaV3` and `LifeOrganizeMigrationPlan`.
- Versioned schemas and migrations live in `LifeOrganize/Persistence/LifeOrganizeSchemas.swift`, `LifeOrganize/Persistence/LifeOrganizeSchemaV2.swift`, `LifeOrganize/Persistence/LifeOrganizeSchemaV3.swift`, and `LifeOrganize/Persistence/LifeOrganizeMigrationPlan.swift`.
- Seed loading is implemented through `LifeOrganize/Persistence/SeedScenarioLoader.swift`, `SeedScenario.swift`, `SeedScenarioRecordBuilder*.swift`, and JSON fixtures in `LifeOrganize/Resources/SeedScenarios/`.
- Test fixtures mirror seed JSON under `LifeOrganizeTests/Fixtures/`.
- Local clearing is implemented in `LifeOrganize/Services/LocalDataClearService.swift` and surfaced in `LifeOrganize/Features/Settings/SettingsClearDataFlow.swift` / `SettingsView.swift`. Tests in `LifeOrganizeTests/LocalDataClearServiceTests.swift` cover clearing ledger records while keeping the saved service token and blocking stale extraction completion from recreating records.
- Migration tests exist in `LifeOrganizeTests/SwiftDataMigrationTests.swift`, covering V1 and V2 store migration plus persisted model names.

## Search, Recall, Timeline, Things, Rules, Review Queue, and UI Contracts

- Search and recall services are implemented in `LifeOrganize/Services/SearchService.swift`, `SearchService+Ranking.swift`, `SearchService+TimelineSlices.swift`, `RecallService.swift`, `ChatRecallResponseService.swift`, and UI files under `LifeOrganize/Features/Search/`.
- Timeline projection is implemented by `LifeOrganize/Services/TimelineSliceProjection.swift`, `TimelineSliceTypes.swift`, `TimelineSliceRelationshipIndex.swift`, and UI files under `LifeOrganize/Features/Timeline/` and `LifeOrganize/Features/Chat/`.
- Things surfaces are implemented under `LifeOrganize/Features/Things/`, with identity/normalization support in `LifeOrganize/Services/ThingResolver.swift`, `LifeOrganize/Utilities/ThingNormalizer.swift`, and related services.
- Reminder/rule lifecycle is implemented under `LifeOrganize/Features/Rules/`, `LifeOrganize/Services/ReminderRuleLifecycleMutation.swift`, `RuleStatusService.swift`, `OperationalIntervalInferenceService.swift`, and related presentation services.
- Ledger review queue generation, actions, presentation, and reconciliation are implemented in `LifeOrganize/Services/LedgerReviewQueueService.swift`, `LedgerReviewQueueActions.swift`, `LedgerReviewItemGenerationService*.swift`, `LedgerReviewItemPresentation.swift`, `LedgerReviewQueuePresentation.swift`, and UI files under `LifeOrganize/Features/Shared/`.
- UI copy and guardrail contracts are covered by tests including `LifeOrganizeTests/LedgerCopyRestraintTests.swift`, `SettingsTrustSurfaceTests.swift`, `V1ScopeGuardrailTests.swift`, `LedgerDensityContractTests.swift`, `LedgerVisualSystemTests.swift`, and `LedgerBadgeSemanticsTests.swift`.

## iOS Project, Build, Unit Tests, and UI Tests

- The shared Xcode scheme is `LifeOrganize.xcodeproj/xcshareddata/xcschemes/LifeOrganize.xcscheme`. It builds the app target, `LifeOrganizeTests`, and `LifeOrganizeUITests`, and includes both test bundles in `TestAction`.
- `LifeOrganize.xcodeproj/project.pbxproj` sets iOS deployment target `17.0`, app bundle identifier `com.local.lifeorganize`, test bundle identifiers, marketing version `0.1`, build number `1`, automatic signing, and app entitlements at `LifeOrganize/LifeOrganize.entitlements`.
- The scheme does not declare code coverage in the checked-in `.xcscheme`; coverage can be enabled at command time with `-enableCodeCoverage YES`.
- Unit tests are broad across app logic in `LifeOrganizeTests/`, including chat send, AI service client, SwiftData migration, search/recall, rules, review queue, fixtures, export, visual-system contracts, and guardrails.
- UI tests exist under `LifeOrganizeUITests/`. They cover first launch, chat input and ledger feed, tab navigation, settings, search open/dismiss/result navigation, things/detail, carry-forward/rules, review queue, seeded scenarios, heavy history scrolling, and screenshot-mode launch aliases.
- UI tests are deterministic/local-first by launch arguments in `LifeOrganizeUITests/UITestSupport.swift`: `-ui-testing`, `-use-fake-extractor`, `-disable-animations`, reset flags, optional in-memory store, and seed scenario arguments.
- There is no `.github/workflows/ios*.yml` or other iOS GitHub Actions workflow in the current `.github/workflows/` directory.

## iOS Coverage

- The desired coverage command target path `BuildArtifacts/LifeOrganizeTests.xcresult` is not represented by a repo script today.
- There is no checked-in `xccov` parser script and no file matching coverage or verify naming in the current repo scan.
- No current workflow gates iOS coverage at 80%, excludes files, reports generated/fixture-heavy files separately, or distinguishes app target coverage from test target coverage.
- `.swiftlint.yml` excludes local build/artifact folders such as `.build`, `.derivedData`, `.deriveddata`, and `BuildArtifacts`, but it is not a coverage exclusion configuration.

## Screenshot Testing and Baselines

- Screenshot orchestration is implemented by `Scripts/screenshots/run-screenshot-tests.sh`. It defaults to project `LifeOrganize.xcodeproj`, scheme `LifeOrganize`, device `iPhone 16`, OS `18.6`, light appearance, result bundle `BuildArtifacts/ScreenshotTests.xcresult`, actuals under `BuildArtifacts/screenshots/actual/iPhone_16/light`, diffs under `BuildArtifacts/screenshots/diff/iPhone_16/light`, and baselines under `Tests/ScreenshotBaselines/iPhone_16/light`.
- The screenshot script boots/configures the simulator, runs only `LifeOrganizeUITests/LifeOrganizeScreenshotTests`, extracts `screenshot__*` PNG attachments, and either updates baselines or compares actuals.
- Screenshot extraction is implemented by `Scripts/screenshots/extract-xcresult-screenshots.sh`.
- Pixel comparison is implemented by `Scripts/screenshots/compare-screenshots.swift`, with default thresholds for changed pixels, changed ratio, and mean channel delta; failed comparisons write diff PNGs.
- Fastlane exposes two lanes in `fastlane/Fastfile`: `screenshots` calls compare mode, and `update_screenshots` calls update mode.
- Baselines exist for `carry_forward`, `first_launch`, `heavy_timeline`, `review_queue`, `search`, `thing_detail`, `things`, `timeline`, and `timeline_empty` under `Tests/ScreenshotBaselines/iPhone_16/light/`.
- Screenshot documentation is in `docs/screenshot-baselines.md`.

## Backend Application, Config, Auth, Rate Limiting, and Middleware

- The FastAPI app is defined in `Backend/main.py`; it disables docs/openapi in production/staging, installs `SecurityHeadersMiddleware` and `RequestSizeLimitMiddleware`, exposes unauthenticated `/healthz`, includes AI/admin routers, and emits a startup admin event.
- Runtime settings are defined in `Backend/app/config.py` via Pydantic settings. Production/staging require `OPENAI_API_KEY`, `LIFE_ORGANIZE_ADMIN_API_KEY`, `DEVICE_TOKEN_SIGNING_SECRET`, and non-localhost `DATABASE_URL`; development has defaults.
- `Backend/pyproject.toml` declares `requires-python = ">=3.11"` and Ruff target `py311`.
- Backend dependencies are pinned in `Backend/requirements.txt`; `pytest` and `pytest-asyncio` are present, but `pytest-cov` is not.
- Device token hashing, device-token dependency, admin-key validation, device-seen recording, and per-device rate limiting are in `Backend/app/auth.py`.
- Device rate limiting counts rows in `AIRequestLog` for a token hash and endpoint within the configured window. It does not currently include shared-IP behavior.
- Security headers are added in `Backend/app/middleware/security_headers.py`.
- Request size rejection in `Backend/app/middleware/request_size.py` checks `Content-Length` against `settings.max_request_bytes` and returns a 413 JSON response; it does not inspect streamed body size when `Content-Length` is missing or invalid.
- `Backend/app/schemas.py` defines Pydantic request/response DTOs for extraction, web request, web answer, and error bodies.

## Backend OpenAI Gateway and Request Contracts

- AI routes live in `Backend/app/routers/ai.py`. `/api/v1/extractions` and `/api/v1/web-requests` require a device token, record device metadata, enforce rate limits, emit admin events, call `OpenAIGateway`, persist request metadata, and map gateway errors into FastAPI `HTTPException`.
- Admin usage stats are also exposed from `Backend/app/routers/ai.py` at `/api/admin/usage` with admin-key dependency.
- The provider gateway is implemented in `Backend/app/services/openai_gateway.py`. It calls `https://api.openai.com/v1/responses`, builds strict JSON-schema extraction payloads, builds web-answer and web-import payloads with `web_search`, maps timeout/network/auth/rate-limit/server/invalid-response errors, parses `output_text`, and logs metadata without raw provider response bodies.
- The extraction schema is implemented in `Backend/app/services/openai_schema.py` with schema name `life_ledger_extraction_v1`.
- iOS backend DTOs live in `LifeOrganize/DTOs/BackendAIRequest.swift`. The Swift request/response shapes line up nominally with backend schemas for `text`, `currentDate`, `currentDateTime`, `timezone`, `schemaVersion`, `mode`, `rawResponseText`, `requestJSON`, `assistantText`, and `modelName`.
- Backend error response shape is not declared globally on the FastAPI routes; route errors currently use `HTTPException(detail={"code": ..., "detail": ...})`, which produces a nested `detail` object. The iOS `BackendErrorResponse` decoder can decode either flat string detail or nested `BackendErrorResponse`.

## Backend Admin Logs and Redaction

- Admin event buffering and SSE formatting are implemented in `Backend/app/admin_events.py` as an in-memory deque with max length 500 and async subscribers.
- Admin log routes and an embedded HTML log page are implemented in `Backend/app/routers/admin.py`: session creation, recent logs, SSE stream, marker, clear, and `/admin/logs`.
- Admin auth accepts either a session cookie created from a valid admin key or the `x-admin-api-key` header. The cookie is `httponly`, `samesite=strict`, `secure=False`, and kept in an in-memory `_admin_sessions` set.
- The admin log page text states raw user text, API keys, and OpenAI response bodies are not logged. The current event emissions log text lengths, endpoint, status, latency, model, request IDs, schema version, timezone, and error codes.
- Admin events are not persisted to Postgres; database persistence currently covers only `DeviceClient` and `AIRequestLog`.

## Backend Database and Alembic

- SQLAlchemy async setup is in `Backend/app/db.py`; it creates an async engine from `settings.database_url` with `pool_pre_ping=True` and provides `AsyncSessionLocal`.
- Database models are in `Backend/app/models.py`: `DeviceClient` and `AIRequestLog`.
- Alembic config is in `Backend/alembic.ini`; async migration setup is in `Backend/alembic/env.py`.
- The initial migration is `Backend/alembic/versions/20260522_000001_initial_backend.py`, creating `device_clients` and `ai_request_logs` plus indexes.
- There are no backend tests for Alembic upgrade from an empty database, migration idempotency, connection failure behavior, or request metadata persistence in the scanned backend test files.

## Backend Tests and Coverage

- Backend tests currently consist of `Backend/tests/test_auth.py` and `Backend/tests/test_openai_gateway.py`.
- `Backend/tests/test_auth.py` covers only stable device-token hashing and verifies the raw token does not appear in the hash.
- `Backend/tests/test_openai_gateway.py` covers extraction payload schema/date context, web-answer payload web-search behavior, web-import schema payload, and accepted OpenAI response output-text shapes.
- Backend tests do not currently cover request auth dependencies through FastAPI routes, missing/malformed token responses, admin API key success/failure through routes, rate-limit behavior, middleware headers/request-size rejection, provider error mapping through routes, timeout handling, malformed provider responses through route behavior, DB migrations, Docker health, Caddy helper behavior, or production smoke.
- Backend coverage is not configured in `Backend/pyproject.toml`, `Backend/requirements.txt`, or `.github/workflows/backend-ci-cd.yml`. No backend 80% coverage gate exists.

## Backend Docker, Caddy, and Local Smoke

- `Backend/infra/api.Dockerfile` uses `python:3.14.2-slim` in builder and runtime stages, installs `Backend/requirements.txt`, copies app/alembic/main/entrypoint, runs as non-root `appuser`, exposes port 8000, and starts uvicorn through `life-organize-api-entrypoint`.
- `Backend/infra/api-entrypoint.sh` fail-fast checks production/staging env vars and optionally runs Alembic when `RUN_MIGRATIONS=true`.
- `Backend/infra/docker-compose.yml` defines `postgres`, `api`, and `migrate` services for `dev` and `prod` profiles; `api` binds to `127.0.0.1:${API_PORT:-8787}:8000` and has a container healthcheck hitting `http://localhost:8000/healthz`.
- `Backend/infra/Caddyfile` owns a `life.dock108.dev` site block, sets security headers, enables gzip, and reverse proxies to `127.0.0.1:8787`.
- `Backend/infra/scripts/update_caddy_site_block.py` extracts and replaces/appends one Caddy site block in a target Caddyfile.
- There is no checked-in script for the braindump’s local backend container smoke sequence (`docker compose ... up -d postgres api`, `curl /healthz`, `down`).

## Backend GitHub CI/CD and Deployment

- Current workflows are `.github/workflows/backend-ci-cd.yml` and `.github/workflows/deploy-recent-image.yml`.
- `.github/workflows/backend-ci-cd.yml` triggers on pushes/PRs touching backend paths and on manual dispatch. It has jobs for backend tests, Ruff lint, Python compile, Docker build/push, and SSH deploy.
- Backend CI uses `actions/setup-python@v6` with `python-version: "3.14"` and `uv venv --python 3.14`, while `Backend/pyproject.toml` requires `>=3.11` and Ruff targets `py311`.
- Backend CI test job runs `python -m pytest tests`; lint runs `ruff check app tests infra/scripts`; compile runs `python -m compileall app tests infra/scripts`.
- Backend CI does not install `pytest-cov`, does not run a coverage command, does not run Docker smoke before image push, and does not curl public `https://life.dock108.dev/healthz` after deploy.
- The deploy job builds/pushes GHCR images on main push or manual full deploy, SSHes to the server, syncs repo to `DEPLOY_PATH`, optionally updates Caddy when `Backend/infra/Caddyfile` changed, requires server-local `Backend/.env`, pulls compose images, runs migrations, starts Postgres/API, waits for Docker health, verifies the running image SHA, and prunes Docker artifacts.
- `.github/workflows/deploy-recent-image.yml` manually deploys a selected existing image tag and always updates the Caddy site block before pulling, running migrations, recreating services, and checking Docker health.
- Neither workflow deploys iOS.

## Docs and Known Drift

- `README.md` documents local iOS build/test commands pinned to `iPhone 16, OS=18.6`, the default production backend, local backend override, backend deployment scope, and no iOS deployment.
- `docs/backend.md` documents local backend setup, Docker run, local override, admin logs, production secret ownership, and `life.dock108.dev`.
- `docs/ops/deployment.md` documents the Hetzner/GHCR/Caddy/Compose deployment and rollback expectations.
- `docs/current-app-state.md` documents app/runtime/screenshot state, but its statement that the repo “does not contain visible GitHub Actions workflows” is stale relative to the current `.github/workflows/backend-ci-cd.yml` and `.github/workflows/deploy-recent-image.yml`.
