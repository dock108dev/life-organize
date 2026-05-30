# Documentation Consolidation Audit

## Changes

- Rechecked `README.md` against `LifeOrganize.xcodeproj/project.pbxproj`, `.github/workflows/backend-ci-cd.yml`, `.github/workflows/ios-ci.yml`, `Scripts/verify-all.sh`, `Scripts/verify-backend.sh`, `Scripts/verify-ios.sh`, `Scripts/run-adaptive-screen-validation.sh`, `Scripts/run-dynamic-type-ui-smoke.sh`, `Scripts/screenshots/run-screenshot-tests.sh`, `Backend/infra/docker-compose.yml`, and `LifeOrganize/Utilities/AppRuntimeConfiguration.swift`; no wording changes were needed.
- Updated `docs/current-app-state.md` to include `-disable-developer-mode`, which is parsed by `AppRuntimeConfiguration`, and to list the current screenshot runner capture set, including Settings.
- Updated `docs/screenshot-baselines.md` to document the current screenshot PNG set from `Scripts/screenshots/run-screenshot-tests.sh`, including `settings.png`.
- Updated `docs/screenshot-baselines.md` to distinguish the screenshot runner/comparator baseline set from the narrower `REQUIRED_SCREENSHOT_SCENARIOS` list enforced by `Scripts/ios_static_layout_guard.py`.
- Rechecked `docs/backend.md` against `Backend/main.py`, `Backend/app/routers/ai.py`, `Backend/app/routers/admin.py`, `Backend/app/config.py`, `Backend/infra/docker-compose.yml`, `Backend/infra/api-entrypoint.sh`, and backend tests; no wording changes were needed.
- Rechecked `docs/ops/deployment.md` against `.github/workflows/backend-ci-cd.yml`, `.github/workflows/deploy-recent-image.yml`, `Backend/infra/docker-compose.yml`, `Backend/infra/Caddyfile`, and `Backend/infra/scripts/update_caddy_site_block.py`; no wording changes were needed.
- Rechecked `docs/ops/branch-protection.md` against `.github/workflows/backend-ci-cd.yml` and `.github/workflows/ios-ci.yml`; no wording changes were needed.
- Deleted `docs/audits/cleanup-report.md` because it was an untracked cleanup-pass record with source-code pass notes, not maintained project documentation.

## Statements Removed

- Removed the prior cleanup report's source-code cleanup claims from the maintained documentation set.
- Removed the implicit claim that the screenshot baseline set exactly matches the static guard's required scenario list. Current code has a runner/comparator baseline set that includes `settings.png`, while `Scripts/ios_static_layout_guard.py` still enforces nine named scenarios.

## Intentional Gaps

- `BRAINDUMP.md` was not edited because the pass rules identify it as customer voice.
- `.aidlc/**` markdown was not edited because it is ignored generated planning state, not tracked maintained project documentation. Bringing `.aidlc` into this documentation contract would mean a separate generated-state cleanup that either deletes those generated planning files or moves still-relevant records into `docs/`.
- `.pytest_cache/**` and `Backend/.venv/**` markdown files were not edited because they are ignored tool-cache or virtualenv files, not maintained project documentation.
- No code comments were added because this was a docs-only pass and every maintained-doc finding was handled by editing or deleting markdown.

## Escalations

None.
