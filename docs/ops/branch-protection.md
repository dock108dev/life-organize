# Branch Protection Checks

This is the maintainer contract for GitHub branch protection and status checks.
Keep these check names stable because GitHub branch protection matches the job
display name exactly.

## Pull Request Checks

Require only checks that run on pull requests for the protected branch. Do not require deploy-only jobs on pull requests because skipped checks can strand a merge behind a status that will not be produced for that event.

| Required check | Workflow | Job id | Owner |
| --- | --- | --- | --- |
| `backend / tests` | `Backend CI/CD` | `test-backend` | Backend pytest suite with Postgres-enabled integration tests. |
| `backend / lint` | `Backend CI/CD` | `lint-ruff` | Ruff lint gate for backend app, tests, and deploy helpers. |
| `backend / compile` | `Backend CI/CD` | `compile` | Python bytecode compilation after backend test and lint gates. |
| `backend / coverage >= 80` | `Backend CI/CD` | `coverage` | Backend pytest coverage gate. |
| `backend / docker build` | `Backend CI/CD` | `docker-build` | Backend Docker Compose smoke before image publish. |
| `Python 3.11 Compatibility` | `Backend CI/CD` | `python-lower-bound` | Lower-bound Python compile and pytest check. |
| `ios / build` | `iOS CI` | `build-ios` | Unsigned simulator build for testing. |
| `ios / unit and ui tests` | `iOS CI` | `test-ios` | Simulator unit and UI tests with code coverage collection. |
| `ios / coverage >= 80` | `iOS CI` | `coverage-ios` | App-target coverage gate from the test result bundle. |
| `ios / screenshots` | `iOS CI` | `screenshot-comparison` | Deterministic screenshot comparison against committed baselines. |

The iOS checks build and test the app only. They must not sign, archive, upload, notarize, deploy to TestFlight, deploy to the App Store, or deploy iOS through GitHub Actions.

## Main And Deploy Checks

`backend / docker publish`, `backend / deploy`, and `prod / healthz smoke` are deploy-path checks from `Backend CI/CD`. They run on `main` pushes for backend paths and manual full-deploy dispatches. The production smoke check is deploy-only. Keep it out of pull request required checks.

Backend deploy remains GitHub Actions to Hetzner through the configured SSH host. The image publish job depends on `backend / docker build` and `Python 3.11 Compatibility`; `backend / docker build` depends on the backend test, lint, compile, and coverage gates. The deploy job depends on image publish, and `prod / healthz smoke` depends on deploy.

## Renaming Checks

If a workflow job display name changes, update branch protection in the same
maintenance window. Remove obsolete required check names after the replacement
jobs have produced successful statuses on the protected branch.
