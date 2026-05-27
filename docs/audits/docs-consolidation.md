# Documentation Consolidation Audit

## Changes

- Updated `README.md` to distinguish app surfaces from repository verification scripts. Adaptive-screen validation is documented as a script-backed repo capability, not as an in-app surface.
- Updated `docs/current-app-state.md` to make the regular-width Review sidebar condition match `LedgerReviewItem.state.isAmbientlyVisible` through `reviewItems.ambientlyVisibleCount`.
- Updated `docs/ops/branch-protection.md` to remove rollout-era wording and state that the iPad portrait screenshot check must not be required while `.github/workflows/ios-ci.yml` emits it only from manual dispatch.
- Updated `docs/screenshot-baselines.md` to account for the legacy `Tests/ScreenshotBaselines/iPhone_16/light/` directory while keeping the required matrix limited to the cells enforced by `Scripts/ios_static_layout_guard.py` and `.github/workflows/ios-ci.yml`.
- Rechecked `docs/backend.md` and `docs/ops/deployment.md` against the current FastAPI routers, backend config, Compose file, Caddy helper, and GitHub deploy workflows; no wording changes were needed in those files.
- Rechecked `docs/ops/branch-protection.md` against `.github/workflows/backend-ci-cd.yml`, `.github/workflows/ios-ci.yml`, and `Tests/verify_scripts/test_verify_scripts.py`.
- Deleted `docs/audits/cleanup-report.md` because it was an untracked cleanup-pass record, not maintained project documentation.

## Statements Removed

- Removed the implication that adaptive-screen validation is an app feature exposed in the UI. Current evidence is script and test coverage, not an in-app surface.
- Removed the vague phrase "ambient review item" and replaced it with the code-backed `LedgerReviewItem` ambient-visibility condition.
- Removed the rollout-era phrase that the iPhone screenshot check should remain the only required check during an initial iPad rollout. Current docs now describe the existing required check and the workflow condition for promoting another required check.
- Removed the prior cleanup report's historical code-cleanup claims from the maintained documentation set.

## Intentional Gaps

- `BRAINDUMP.md` was not edited because the pass rules identify it as customer voice.
- `.aidlc/**` markdown was not edited because it is ignored generated planning state, not tracked maintained project documentation. Bringing `.aidlc` into this documentation contract would mean a separate generated-state cleanup that either deletes those generated planning files or moves the still-relevant records into `docs/`.
- `.pytest_cache/**` and `Backend/.venv/**` markdown files were not edited because they are ignored tool-cache or virtualenv files, not maintained project documentation.
- No code comments were added because this was a docs-only pass and every maintained-doc finding was handled by editing or deleting markdown.

## Escalations

None.
