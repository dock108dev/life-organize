# Testing and CI/CD Braindump

This is the working scope for getting LifeOrganize to complete front/backend testing and CI/CD coverage without adding iOS deployment to GitHub yet.

## Hard Rules

- Frontend means the iOS app. It is local-first, but every frontend environment should default to the production backend at `https://life.dock108.dev`.
- Local, CI, TestFlight, and eventual App Store builds should not require a developer to run a local backend.
- Local backend overrides stay available only as an explicit development/debug path, for example `-ai-service-base-url=http://127.0.0.1:8787`.
- The backend owns provider credentials. No frontend environment gets `OPENAI_API_KEY` or any other provider secret.
- GitHub should not deploy iOS yet. GitHub should build and test iOS.
- Backend deploy remains GitHub Actions to the Hetzner server.
- The quality target is 80% coverage across the normal test disciplines. Anything excluded from coverage needs to be deliberate: generated code, fixtures, UI-only shell code that cannot be sensibly unit tested, and migration boilerplate.

## Current Repo State

Already present:

- iOS app under `LifeOrganize/`.
- iOS unit tests under `LifeOrganizeTests/`.
- iOS UI tests under `LifeOrganizeUITests/`.
- Deterministic screenshot test tooling under `Scripts/screenshots/`.
- Screenshot baselines under `Tests/ScreenshotBaselines/`.
- Fastlane lanes for screenshot comparison and baseline refresh.
- Backend under `Backend/` with FastAPI, Alembic, Postgres, Docker Compose, and Caddy deployment files.
- Backend tests under `Backend/tests/`.
- Backend GitHub workflow at `.github/workflows/backend-ci-cd.yml`.
- Manual backend image deploy workflow at `.github/workflows/deploy-recent-image.yml`.

Current gaps:

- No iOS GitHub CI workflow yet.
- No explicit iOS code coverage gate yet.
- No explicit backend coverage dependency or 80% coverage gate yet.
- Backend CI uses Python `3.14` while `Backend/pyproject.toml` says `>=3.11`; decide whether to pin to a stable supported version or keep the forward version intentionally.
- Backend tests are still narrow for a production gateway: auth hashing and OpenAI payload shape are covered, but request auth, rate limits, admin event behavior, middleware, migrations, Docker health, and production smoke coverage need expansion.
- No single command/script represents the full local verification gate.

## Desired Local Full Gate

The local all-disciplines command should eventually be one script, likely `Scripts/verify-all.sh`, that runs these gates in order and exits nonzero on the first failure.

Backend:

```sh
cd Backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pytest-cov
ruff check app tests infra/scripts
python -m compileall app tests infra/scripts
python -m pytest tests --cov=app --cov=main --cov-report=term-missing --cov-fail-under=80
```

iOS build and unit/UI tests:

```sh
xcodebuild test \
  -project LifeOrganize.xcodeproj \
  -scheme LifeOrganize \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -resultBundlePath BuildArtifacts/LifeOrganizeTests.xcresult \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO
```

iOS coverage:

```sh
xcrun xccov view --report --json BuildArtifacts/LifeOrganizeTests.xcresult
```

The coverage parser should fail below 80% for the app target. It should not count test targets. It should either exclude generated/fixture-heavy files explicitly or report them separately so a low number is visible instead of hidden.

Screenshots:

```sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

Backend container smoke:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build -d postgres api
curl -fsS http://127.0.0.1:8787/healthz
docker compose -f Backend/infra/docker-compose.yml --profile dev down
```

Production smoke, after deploy:

```sh
curl -fsS https://life.dock108.dev/healthz
```

## Frontend Testing Scope

Unit and integration coverage should protect:

- Chat send flow: local save first, backend extraction request, backend failure fallback, retry, idempotency, and continuity state.
- AI service client: default production base URL, explicit local override only when launch args request it, auth headers, timeout, error mapping, and response decoding.
- SwiftData persistence: migrations, seed scenarios, relationship integrity, delete/reassignment behavior, ledger export, and local data clearing.
- Search and recall: local-first ranking, timeline slices, thing/event/rule visibility, recall continuity, empty states.
- Reminder/rule lifecycle: creation, updates, carry-forward, pause/resume language, ambiguity handling, operational intervals, stale reminders.
- Ledger review queue: item generation, safety actions, presentation, reconciliation, and consistency scenarios.
- UI copy/behavior contracts: no provider-secret surfaces, no duplicate objective/explanatory text, and deterministic display formatting.

UI coverage should protect:

- First launch.
- Chat input and ledger feed.
- Timeline.
- Things list/detail/edit/delete.
- Rules list/detail/actions.
- Search open/dismiss/result navigation.
- Review queue.
- Developer/internal QA surfaces that are still intentionally shipped in debug builds.
- Offline/local-first behavior when the backend is unavailable.

Screenshot coverage should protect:

- First launch empty state.
- Timeline empty and populated states.
- Heavy timeline.
- Things.
- Thing detail.
- Carry forward.
- Search.
- Review queue.

Frontend CI should always run against the production backend default in configuration tests, but routine CI tests should not make live OpenAI calls. They should mock/stub network at the client boundary and separately smoke `https://life.dock108.dev/healthz`.

## Backend Testing Scope

Required test groups:

- Config validation: fail fast when required production secrets are missing; development defaults are only development defaults.
- Auth: device token signing, hashing, missing token, malformed token, expired token if expirations are added, admin API key success/failure.
- Rate limiting: per-device limits, reset window, shared IP behavior if added, and no raw token logging.
- OpenAI gateway: extraction schema, web-answer mode, web-import mode, provider error mapping, timeout handling, malformed provider response handling, no raw user text in logs.
- Request contracts: DTO parity with iOS request/response shapes, strict JSON schema names, stable error response body.
- Middleware: security headers and request-size rejection.
- Database: Alembic upgrade from empty DB, request metadata persistence, admin event retention, connection failure behavior.
- Admin logs: SSE/event stream shape, redaction, auth, and no provider secrets or raw user content.
- Docker: image builds, container starts, `/healthz` passes, migrations run once and are idempotent.
- Deployment helpers: Caddy site block update script, compose env behavior, rollback workflow assumptions.

Backend coverage target:

- Add `pytest-cov` to backend dev/test dependencies.
- Gate `app` and `main` at 80%.
- Do not include Alembic generated boilerplate in the coverage denominator unless we intentionally test migration logic.

## CI/CD Shape

Backend workflow should remain responsible for:

- Backend test matrix.
- Ruff lint.
- Python compile.
- Coverage gate at 80%.
- Docker image build and push.
- Main-branch deploy to Hetzner.
- Post-deploy health check against the running container and public `https://life.dock108.dev/healthz`.

iOS workflow should be added but should not deploy:

- Trigger on PRs and pushes touching `LifeOrganize/**`, `LifeOrganizeTests/**`, `LifeOrganizeUITests/**`, `Scripts/screenshots/**`, `Tests/ScreenshotBaselines/**`, `fastlane/**`, and the Xcode project.
- Build the `LifeOrganize` scheme.
- Run unit tests and UI tests on the pinned simulator.
- Enable code coverage and fail under 80% for the app target.
- Run screenshot comparison on PRs that touch UI surfaces or always run it once the runtime cost is acceptable.
- Upload `.xcresult`, screenshot actuals, and diffs as artifacts on failure.
- Do not sign, archive, upload, notarize, TestFlight, or App Store deploy.

Repository-level status checks should eventually be:

- `backend / tests`
- `backend / lint`
- `backend / compile`
- `backend / coverage >= 80`
- `backend / docker build`
- `ios / build`
- `ios / unit and ui tests`
- `ios / coverage >= 80`
- `ios / screenshots`
- `prod / healthz smoke`

## Environment Model

Frontend:

- Default base URL: `https://life.dock108.dev`.
- Explicit local override: launch arg only.
- No provider secrets.
- Device token is app-owned and can be reset for UI tests.
- CI should prove the default is production so debug/test config does not accidentally drift to localhost.

Backend production on Hetzner:

- Checkout path should stay secret-configured through `DEPLOY_PATH`.
- `Backend/.env` stays server-local and uncommitted.
- Caddy owns `life.dock108.dev` for this app only.
- Postgres runs through the backend compose stack.
- Deploys run migrations before replacing the API container.
- Rollback deploys a previous image tag and only runs migrations after checking schema compatibility.

## Implementation Order

1. Add a backend coverage gate with `pytest-cov` and broaden backend tests around auth, middleware, config, gateway errors, and admin redaction.
2. Add `Scripts/verify-backend.sh` and `Scripts/verify-ios.sh`, then wrap them in `Scripts/verify-all.sh`.
3. Add iOS coverage extraction with `xccov` and an 80% app-target gate.
4. Add GitHub iOS CI for build/tests/coverage with no deployment steps.
5. Add screenshot artifacts and compare failures to iOS CI.
6. Add backend Docker smoke to CI after tests and before image push.
7. Add public production `/healthz` smoke after Hetzner deploy.
8. Make required branch protections match the final status check list.

## Open Decisions

- Simulator pin: keep `iPhone 16, OS=18.6` from existing scripts or move CI to the newest available GitHub macOS runner runtime and update screenshot baselines deliberately.
- Backend Python pin: keep GitHub Actions on `3.14` or move to a currently stable repo-wide pin such as `3.12`/`3.13` while preserving `>=3.11`.
- Coverage exclusions: decide the exact Swift files excluded from the app target denominator, if any.
- Screenshot cadence: run on every frontend PR or only when UI files change.
- Production smoke auth: keep `/healthz` unauthenticated and minimal, or add a private admin smoke endpoint checked only from deploy secrets.

## Definition of Done

- `Scripts/verify-all.sh` passes locally.
- Backend CI gates tests, lint, compile, Docker build, and 80% coverage.
- iOS CI gates build, unit/UI tests, screenshots, and 80% coverage.
- Frontend tests prove the default backend is `https://life.dock108.dev`.
- Backend deploy to Hetzner still works and verifies the live health endpoint.
- No GitHub iOS deployment exists yet.
