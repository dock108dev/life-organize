# LifeOrganize

LifeOrganize is a local-first iOS SwiftUI app for maintaining a personal ledger through conversational input. The app stores records in SwiftData and uses a private FastAPI backend for AI extraction and web-backed requests.

## Run Locally

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run the app. The app can launch without the backend; entries are saved locally and AI work remains pending when the service is unavailable.

Command-line build and test:

```sh
xcodebuild -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build CODE_SIGNING_ALLOWED=NO
xcodebuild test -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' CODE_SIGNING_ALLOWED=NO
```

Main verification:

```sh
Scripts/verify-all.sh
```

By default the app calls `https://life.dock108.dev`. Use a local backend with:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up -d postgres
docker compose -f Backend/infra/docker-compose.yml --profile dev run --rm migrate
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build api
```

Then launch the app with:

```text
-ai-service-base-url=http://127.0.0.1:8787
```

See [Local development](docs/local-development.md) for backend setup, device-token behavior, and focused verification commands.

## Deployment

The backend lives in `Backend/`, runs as a FastAPI service with Postgres, and owns provider credentials. Production deployment is backend-only: GitHub Actions builds and publishes the API image, runs Alembic migrations, recreates the API container, and verifies `https://life.dock108.dev/healthz`. The iOS workflow builds, tests, checks coverage, and compares screenshots; it does not sign, archive, upload, or deploy the app.

## Deeper Docs

- [Architecture](docs/architecture.md)
- [Data models](docs/data-models.md)
- [Backend](docs/backend.md)
- [Environment and runtime configuration](docs/env-and-config.md)
- [Local development](docs/local-development.md)
- [Testing and CI](docs/testing-and-ci.md)
- [Backend deployment](docs/ops/deployment.md)
- [Branch protection checks](docs/ops/branch-protection.md)
- [Screenshot baselines](docs/screenshot-baselines.md)
- [Known limitations and unsupported paths](docs/known-limitations.md)
- [Large-file follow-up list](docs/maintenance/large-files.md)
