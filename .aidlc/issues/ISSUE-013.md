# ISSUE-013: Split backend CI gates and add Docker smoke

**Priority**: high
**Labels**: backend, github-actions, ci, docker, new-feature
**Dependencies**: ISSUE-001, ISSUE-006
**Status**: implemented

## Description

Update backend GitHub Actions so the new backend CI capabilities map cleanly to BRAINDUMP's desired status checks while preserving backend deploy ownership. Use `.aidlc/research/backend-ci-status-check-splitting.md`, `.aidlc/research/backend-docker-health-and-migrations.md`, and `.aidlc/research/backend-python-version-pin.md`. This issue should split lint, compile, tests, coverage, and Docker build/smoke into stable checks; image publishing and Hetzner deploy remain main-branch-only follow-on work.

## Acceptance Criteria

- [ ] Backend CI exposes stable checks corresponding to `backend / tests`, `backend / lint`, `backend / compile`, `backend / coverage >= 80`, and `backend / docker build`.
- [ ] Pull requests run lint, compile, tests, coverage, and Docker build/smoke without pushing images or deploying to Hetzner.
- [ ] Coverage gates `app` and `main` at 80% using the dependency/policy from ISSUE-001.
- [ ] Docker smoke builds the image, starts Postgres and API with the dev compose profile, verifies `/healthz`, and tears down containers on success and failure.
- [ ] Migration smoke verifies migrations run once and remain idempotent when the container starts again.
- [ ] Main-branch image push and Hetzner deploy remain in the backend workflow and depend on passing backend test/coverage/build gates.

## Implementation Notes


Attempt 1: Split backend CI into stable tests, lint, compile, coverage, and Docker build/smoke gates in .github/workflows/backend-ci-cd.yml; main-only Docker publish and deploy now depend on the PR-safe backend gates.