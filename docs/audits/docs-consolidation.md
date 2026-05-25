# Documentation Consolidation Audit

## Changes

- Updated `README.md` to include `Scripts/verify-all.sh` in the local verification commands and to link directly to `docs/ops/deployment.md`.
- Updated `docs/backend.md` to distinguish the public `/admin/logs` HTML shell from the authenticated admin API routes, describe the admin key as the log panel connection credential, and align migration wording with the Compose `migrate` service used by deploy.
- Updated `docs/ops/deployment.md` to say the deploy job resets the server checkout in `DEPLOY_PATH`, matching `.github/workflows/backend-ci-cd.yml`.
- Left `docs/current-app-state.md`, `docs/ops/branch-protection.md`, and `docs/screenshot-baselines.md` in place after verifying their claims against the current Swift code, shell scripts, Xcode project, backend code, and GitHub workflows.
- Deleted `docs/audits/cleanup-report.md` because it was an untracked prior cleanup-pass record, not maintained project documentation.

## Statements Removed

- Removed the implication that `/admin/logs` itself is authenticated. The route serves the HTML shell; the shell uses `LIFE_ORGANIZE_ADMIN_API_KEY` to open an authenticated admin API session.
- Removed the instruction to set `RUN_MIGRATIONS=true` as the normal production deploy path. Current deploy runs Alembic through the one-shot Compose `migrate` service.
- Removed the vague statement that deployment "syncs" the repo into `DEPLOY_PATH`; the workflow performs a branch checkout and hard reset.
- Removed the prior cleanup report's historical cleanup claims from the maintained documentation set.

## Intentional Gaps

- `BRAINDUMP.md` was not edited because the pass rules identify it as customer voice.
- `.aidlc/**` markdown was not edited because the requested deliverable is maintained project documentation in `README.md` and `docs/`; `.aidlc` is generated planning state. Bringing `.aidlc` into this documentation contract would mean a separate generated-state cleanup that either deletes the tracked `.aidlc` planning files or moves the still-relevant records into `docs/`.
- No code comments were added because this was a docs-only pass and every maintained-doc finding was handled by editing or deleting markdown.

## Escalations

None.
