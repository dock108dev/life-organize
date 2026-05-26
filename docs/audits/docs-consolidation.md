# Documentation Consolidation Audit

## Changes

- Updated `README.md` to include adaptive-screen validation in the top-level app summary, matching the committed adaptive validation scripts and UI tests.
- Updated `docs/current-app-state.md` to describe the current compact `TabView` and regular `NavigationSplitView` shells, Things and Carry Forward split-view behavior, Internal QA diagnostics, current developer-mode unlock paths, the full set of runtime launch arguments, simulated AI-service errors, and the static layout guard in `Scripts/verify-ios.sh`.
- Updated `docs/backend.md` to use the repo-local backend virtualenv for the local Uvicorn command and to describe the admin log panel session/header behavior and redacted log metadata.
- Updated `docs/ops/deployment.md` to document the current Caddy sudo precheck and exact Caddy update command shape used by the deploy workflows.
- Updated `docs/screenshot-baselines.md` to remove stale migration wording, distinguish default legacy-baseline fallback behavior from the maintained matrix, list the Dynamic Type smoke sizes, and clarify that `screenshot_profile=all_light` runs the two CI screenshot targets.
- Kept `docs/ops/branch-protection.md` after checking its required check names and promotion guidance against `.github/workflows/backend-ci-cd.yml`, `.github/workflows/ios-ci.yml`, and `Tests/verify_scripts/test_verify_scripts.py`.
- Deleted `docs/audits/cleanup-report.md` because it was an untracked cleanup-pass record, not maintained project documentation.

## Statements Removed

- Removed the compact-only wording that `AppRootView` owns only root tabs. Current code switches between tabs and a regular-width sidebar/split-view shell.
- Removed the incomplete diagnostics wording that mentioned only extraction attempt lists. Current Settings diagnostics also route to the Internal QA Lab.
- Removed the implication that the local backend run command can rely on a globally installed `uvicorn`. The documented command now uses `Backend/.venv`.
- Removed the broad statement that `screenshot_profile=all_light` runs all maintained baseline cells. The workflow runs the iPhone portrait and iPad portrait CI targets.
- Removed the stale note that the old iPhone baseline layout was still migrating. Current documentation states only the runner's default legacy fallback behavior.
- Removed the prior cleanup report's historical code-cleanup claims from the maintained documentation set.

## Intentional Gaps

- `BRAINDUMP.md` was not edited because the pass rules identify it as customer voice.
- `.aidlc/**` markdown was not edited because this pass's actionability contract limits docs-pass edits to `README.md` and markdown under `docs/`; `.aidlc` is generated planning state. Bringing `.aidlc` into this documentation contract would mean a separate generated-state cleanup that either deletes those generated planning files or moves the still-relevant records into `docs/`.
- `.pytest_cache/**` and `Backend/.pytest_cache/**` README files were not edited because they are tool cache files, not maintained project documentation.
- No code comments were added because this was a docs-only pass and every maintained-doc finding was handled by editing or deleting markdown.

## Escalations

None.
