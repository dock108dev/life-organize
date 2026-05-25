# Documentation Consolidation Audit

## Changes

- Rewrote `README.md` into a lean root document covering repo purpose, local run commands, verification scripts, backend-only production deployment, iOS CI boundaries, and pointers to maintained docs.
- Rewrote `docs/current-app-state.md` against the current Swift app, backend boundary, runtime arguments, verification scripts, GitHub Actions, and repository surface.
- Tightened `docs/backend.md` around current FastAPI routes, Python support, local Docker binding, admin log behavior, production environment requirements, and the code-defined `OPENAI_MODEL` default.
- Updated `docs/ops/deployment.md` to describe the current backend deploy flow, backend coverage and Docker gates, Python 3.11 compatibility check, image tags, Caddy update helper, and the fact that iOS CI exists but does not deploy iOS.
- Updated `docs/ops/branch-protection.md` to include the current `Python 3.11 Compatibility` job and to keep deploy-only backend jobs out of PR required checks.
- Updated `docs/screenshot-baselines.md` to match the current device/appearance artifact directories and removed the unverified `.swiftlint.yml` exclusion claim.
- Deleted `docs/product-stabilization-notes.md` because it duplicated current-app and screenshot content while mixing product-risk guidance with statements that were not directly verifiable from code/config.
- Deleted `docs/audits/cleanup-report.md` because it was a prior pass record with stale command-output claims and was not current project documentation.

## Statements Removed

- Removed the claim that `gpt-5.5` matches current OpenAI frontier guidance. The repo verifies `gpt-5.5` only as the configured default, not as current external model guidance.
- Removed the claim that the repository has no visible GitHub Actions workflows. Current code contains backend and iOS workflows.
- Removed the claim that iOS CI/CD is entirely out of scope. Current code contains iOS CI; iOS deployment remains out of scope.
- Removed the product-stabilization guidance doc instead of preserving broad risk statements that were not precise code/config facts.
- Removed the previous cleanup report's historical verification counts from maintained docs.

## Intentional Gaps

- `BRAINDUMP.md` was not edited because the pass rules identify it as customer voice.
- `.aidlc/**` markdown was not edited because the pass scope and deliverable are `README.md` plus markdown under `docs/`; the `.aidlc` tree is generated planning/audit workspace state, not maintained project documentation.
- No code comments were added because this was a docs-only pass and every in-scope finding was handled by editing or deleting markdown.

## Escalations

None.
