# Testing and CI

## Local Gates

`Scripts/verify-backend.sh` creates or reuses `Backend/.venv`, installs backend requirements plus Ruff, runs Ruff, compiles Python modules, and runs backend pytest with coverage. Docker smoke is opt-in:

```sh
Scripts/verify-backend.sh
Scripts/verify-backend.sh --with-smoke
Scripts/verify-backend.sh smoke
```

`Scripts/verify-ios.sh` runs the static iOS layout guard, then `xcodebuild test` with coverage enabled, then the iOS coverage gate unless `IOS_SKIP_COVERAGE_GATE=1`.

The iOS verifier writes the xcodebuild log to `BuildArtifacts/Logs/xcodebuild-test.log` by default. If `xcodebuild` exits nonzero, the script checks the `.xcresult` test summary, build summary, and final XCTest log before deciding whether the test run is genuinely failed.

`Scripts/verify-all.sh` runs backend checks, iOS tests and coverage, screenshot comparison, and optional backend or production smoke checks:

```sh
Scripts/verify-all.sh
Scripts/verify-all.sh --with-backend-smoke
Scripts/verify-all.sh --with-production-smoke
```

`Scripts/secret_scan.py` scans committed files for high-confidence private keys, OpenAI-style keys, and non-placeholder backend secret assignments.

## iOS Visual and Layout Gates

`Scripts/screenshots/run-screenshot-tests.sh compare` runs the deterministic screenshot comparator. `update` refreshes the selected baseline cell.

`Scripts/run-dynamic-type-ui-smoke.sh` runs normal, Large, Accessibility Large, and Accessibility XXXL UI smoke tests.

`Scripts/run-adaptive-screen-validation.sh compare` runs the maintained iPhone/iPad screenshot matrix, Dynamic Type smoke matrix, compact/regular adaptive shell checks, and a smaller iPad portrait shell smoke when a configured simulator exists locally.

See [Screenshot baselines](screenshot-baselines.md) for the visual matrix and artifact paths.

## Backend CI/CD

`.github/workflows/backend-ci-cd.yml` runs on:

- Pushes to `main` that touch backend/deployment workflow paths.
- Pull requests to `main` that touch backend/deployment workflow paths.
- Manual workflow dispatch.

Pull request jobs:

- `backend / tests`: pytest with Postgres integration tests enabled.
- `backend / lint`: Ruff.
- `backend / security audit`: `pip-audit` plus committed-secret scan.
- `backend / compile`: Python bytecode compilation.
- `backend / coverage >= 80`: backend coverage gate.
- `backend / docker build`: Docker Compose smoke.

Deploy jobs:

- `backend / docker publish`
- `backend / deploy`
- `prod / healthz smoke`

Deploy jobs run on `main` pushes for backend paths or manual dispatch with `full_deploy=true`.

## iOS CI

`.github/workflows/ios-ci.yml` runs on:

- Pushes to `main`.
- Pull requests to `main` that touch app, test, asset, screenshot, Fastlane, iOS script, screenshot doc, or iOS workflow paths.
- Manual workflow dispatch.

Jobs:

- `ios / build`: unsigned simulator build.
- `ios / unit and ui tests`: `Scripts/verify-ios.sh`, with coverage gate skipped in this job so the result bundle can be uploaded.
- `ios / coverage >= 80`: downloads the result bundle and runs `Scripts/ios_coverage_gate.py`.
- `ios / screenshots`: required iPhone 17 Pro portrait light screenshot comparison.
- `ios / screenshots / iPad portrait`: manual workflow-dispatch screenshot job for `ipad_portrait` or `all_light`.

iOS CI does not sign, archive, upload, deploy to TestFlight, deploy to the App Store, or deploy iOS through GitHub Actions.

## Selected Image Deploy

`.github/workflows/deploy-recent-image.yml` manually deploys an existing backend image tag. It always refreshes the Caddy site block, pulls the selected image, optionally runs migrations when `run_migrations=true`, recreates Postgres/API services, waits for container health, and checks public `/healthz`.

Use this workflow for rollback-style image changes or selected image redeploys. Keep `run_migrations=false` unless schema compatibility has already been checked.

## Branch Protection

See [Branch protection checks](ops/branch-protection.md) for the required pull request check names. Branch protection should require only jobs emitted by pull request workflows.
