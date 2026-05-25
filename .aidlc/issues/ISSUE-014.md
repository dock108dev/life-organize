# ISSUE-014: Add production health smoke after backend deploy

**Priority**: high
**Labels**: backend, deployment, smoke, new-feature
**Dependencies**: ISSUE-013, ISSUE-017
**Status**: implemented

## Description

Add the new post-deploy production health smoke requested by BRAINDUMP after backend deployment to Hetzner. Use `.aidlc/research/backend-post-deploy-public-smoke.md` and `.aidlc/research/deployment-rollback-migration-constraint.md`. The smoke should verify the running container first, then public routing through Caddy at `https://life.dock108.dev/healthz`, and should apply to the normal main deploy path and any manual recent-image deploy path where practical.

## Acceptance Criteria

- [ ] The backend deploy workflow checks the replacement container health before public smoke runs.
- [ ] After a successful deploy, GitHub Actions runs `curl -fsS https://life.dock108.dev/healthz` and fails the deploy job if the public endpoint is not healthy.
- [ ] The public smoke check is exposed as the stable `prod / healthz smoke` status for protected branches where applicable.
- [ ] The manual recent-image deploy workflow performs the same public smoke check or documents an equivalent explicit manual gate in the workflow output.
- [ ] `/healthz` remains unauthenticated, minimal, and free of provider secrets or user content.
- [ ] Rollback deploy behavior respects the migration compatibility constraints from ISSUE-017 before running migrations or replacing the API container.

## Implementation Notes


Attempt 1: Added post-deploy public /healthz smoke to backend deploy and recent-image workflows, exposed prod / healthz smoke job, documented manual/rollback smoke, and added deployment contract coverage.