# LifeOrganize

LifeOrganize is a local-first iOS SwiftUI app for maintaining a personal ledger through conversational input. The app stores ledger records in SwiftData, uses a private FastAPI backend for AI extraction and web-backed requests, and exposes Timeline, Things, Carry Forward, local search, review, export, and developer diagnostics surfaces.

## Run Locally

Open `LifeOrganize.xcodeproj` in Xcode, select the shared `LifeOrganize` scheme, choose an iOS 17.0 or newer simulator, and run the app. The app can launch without the backend; entries are saved locally and AI work is left pending when the service is unavailable.

Build from the command line:

```sh
xcodebuild -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build CODE_SIGNING_ALLOWED=NO
```

Run tests:

```sh
xcodebuild test -project LifeOrganize.xcodeproj -scheme LifeOrganize -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

Run the repository verification scripts:

```sh
Scripts/verify-all.sh
Scripts/verify-backend.sh
Scripts/verify-ios.sh
Scripts/screenshots/run-screenshot-tests.sh compare
```

By default the app calls `https://life.dock108.dev`. Pass `-ai-service-base-url=http://127.0.0.1:8787` to use a local backend. Run the local backend with Docker:

```sh
docker compose -f Backend/infra/docker-compose.yml --profile dev up --build
```

## Deployment

The iOS project has Debug and Release configurations, automatic signing, deployment target `17.0`, marketing version `0.1`, build number `1`, and bundle identifier `com.local.lifeorganize`.

The backend lives in `Backend/`, runs as a small FastAPI service with Postgres, and owns the shared OpenAI key. Keep provider credentials in backend secrets only.

Production deployment is backend-only. GitHub Actions builds and publishes the backend image, SSHes to the deploy host, runs Alembic migrations, recreates the API container, and refreshes the Caddy site block when needed. The iOS workflow builds, tests, checks coverage, and compares screenshots; it does not sign, archive, upload, or deploy the app. See [Backend deployment](docs/ops/deployment.md) and [Branch protection checks](docs/ops/branch-protection.md).

## Docs

- [Current app state](docs/current-app-state.md)
- [Backend](docs/backend.md)
- [Backend deployment](docs/ops/deployment.md)
- [Screenshot baselines](docs/screenshot-baselines.md)
- [Branch protection checks](docs/ops/branch-protection.md)
- [Testing and CI/CD braindump](BRAINDUMP.md)
