# LifeOrganize

LifeOrganize is a local-first iOS SwiftUI app for maintaining a personal ledger through conversational input. The app stores ledger records in SwiftData, uses a private FastAPI backend for AI extraction and web-backed requests, and includes backend, iOS, screenshot, Dynamic Type, and adaptive-screen verification scripts.

## Run Locally

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run the app. The app can launch without the backend; entries are saved locally and AI work remains pending when the service is unavailable.

Command-line build and test:

```sh
xcodebuild -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' CODE_SIGNING_ALLOWED=NO
```

Repo verification:

```sh
Scripts/verify-all.sh
Scripts/verify-backend.sh
Scripts/verify-ios.sh
Scripts/run-adaptive-screen-validation.sh compare
Scripts/run-dynamic-type-ui-smoke.sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

By default the app calls `https://life.dock108.dev`. Use a local backend with:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build
```

Then launch the app with:

```text
-ai-service-base-url=http://127.0.0.1:8787
```

See [Local development](docs/local-development.md) for backend setup details, device-token enrollment, and verification commands.

## Deployment

The backend lives in `Backend/`, runs as a FastAPI service with Postgres, and owns provider credentials. Production deployment is backend-only: GitHub Actions builds and publishes the API image, runs Alembic migrations, recreates the API container, and verifies `https://life.dock108.dev/healthz`. The iOS workflow builds, tests, checks coverage, and compares screenshots; it does not sign, archive, upload, or deploy the app.

## Docs

- [Architecture](docs/architecture.md)
- [Data models](docs/data-models.md)
- [Backend](docs/backend.md)
- [Environment and runtime configuration](docs/env-and-config.md)
- [Local development](docs/local-development.md)
- [Testing and CI](docs/testing-and-ci.md)
- [Backend deployment](docs/ops/deployment.md)
- [Branch protection checks](docs/ops/branch-protection.md)
- [Screenshot baselines](docs/screenshot-baselines.md)
- [Large-file follow-up list](docs/maintenance/large-files.md)
