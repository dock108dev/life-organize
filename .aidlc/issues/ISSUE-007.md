# ISSUE-007: Create local full verification scripts

**Priority**: high
**Labels**: scripts, verification, infra, usability-flow, new-feature
**Dependencies**: ISSUE-001, ISSUE-006, ISSUE-010
**Status**: implemented

## Description

Create the new repo-level local verification entrypoints requested by BRAINDUMP: `Scripts/verify-backend.sh`, `Scripts/verify-ios.sh`, and `Scripts/verify-all.sh`. Discovery and `.aidlc/research/local-verify-script-composition.md` show no single command currently represents the full gate; this issue should deliver checked-in executable wrappers that compose backend lint/compile/coverage, iOS build/tests/coverage, screenshots, and optional backend smoke without requiring a local backend by default. If implementation uses helper scripts under `Scripts/verify/`, keep the top-level script names as the user-facing commands.

## Acceptance Criteria

- [ ] `Scripts/verify-backend.sh`, `Scripts/verify-ios.sh`, and `Scripts/verify-all.sh` are executable, checked in, and can be run from the repo root.
- [ ] `Scripts/verify-backend.sh` creates or reuses the backend virtualenv, installs test dependencies including coverage tooling, runs Ruff, compileall, and pytest coverage with the configured 80% fail-under gate.
- [ ] `Scripts/verify-ios.sh` runs the LifeOrganize scheme tests with code coverage enabled, writes the expected xcresult bundle path, invokes the app-target coverage parser from ISSUE-010, and does not require a developer-run local backend.
- [ ] `Scripts/verify-all.sh` runs backend, iOS, screenshot comparison, and optional smoke gates in the BRAINDUMP order and exits nonzero on the first failing discipline.
- [ ] Backend container smoke is available through an explicit flag or subcommand and cleans up Docker Compose resources on success and failure.
- [ ] All scripts print the command being run, the artifact path to inspect on failure, and the explicit override variables for simulator destination or local backend smoke URL.

## Implementation Notes


Attempt 1: Added executable local verification wrappers for backend, iOS, and full gates; wired backend smoke URL handling, coverage thresholds, and screenshot comparison to current screenshot test methods; refreshed screenshot baselines and documented the updated target.