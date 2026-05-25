# ISSUE-017: Test backend deployment helper and rollback contracts

**Priority**: high
**Labels**: backend, deployment, tests, caddy
**Dependencies**: ISSUE-001
**Status**: implemented

## Description

Cover the deployment-helper portion of BRAINDUMP's backend testing scope: Caddy site block update script behavior, Compose env assumptions, manual recent-image deployment, and rollback migration constraints. Use `.aidlc/research/backend-caddy-helper-contract.md`, `.aidlc/research/deployment-rollback-migration-constraint.md`, and `.aidlc/research/docs-state-drift.md`.

## Acceptance Criteria

- [ ] `Backend/infra/scripts/update_caddy_site_block.py` has tests for extracting, replacing, appending, malformed source, malformed target, and nested block behavior for the `life.dock108.dev` site block.
- [ ] Tests document and protect the helper's narrow textual matching assumptions, including the standalone `life.dock108.dev {` safe target shape.
- [ ] Backend workflow changes keep Caddy validation/reload before deploy continuation when Caddy changes are applied.
- [ ] Manual recent-image deployment behavior is reconciled with rollback expectations so image rollback does not automatically run migrations unless schema compatibility has been checked or explicitly requested.
- [ ] Compose env behavior remains compatible with server-local `Backend/.env`, `DEPLOY_PATH`, `IMAGE_TAG`, `RUN_MIGRATIONS=false` on API, and separate `migrate` service ownership.

## Implementation Notes


Attempt 1: Hardened Caddy block matching in Backend/infra/scripts/update_caddy_site_block.py, added deployment contract tests, made selected-image migrations opt-in, reconciled docs/env defaults, and ensured manual full deploy reapplies Caddy before Docker deploy.