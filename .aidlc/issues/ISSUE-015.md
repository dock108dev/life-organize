# ISSUE-015: Document final branch protection check set

**Priority**: medium
**Labels**: github-actions, branch-protection, ci, new-feature
**Dependencies**: ISSUE-011, ISSUE-012, ISSUE-013, ISSUE-014, ISSUE-022, ISSUE-023
**Status**: implemented

## Description

Make the final branch-protection/status-check contract explicit for the new CI/CD capabilities in this cycle. Use `.aidlc/research/branch-protection-check-names.md` and `.aidlc/research/backend-ci-status-check-splitting.md`. This issue is not a docs-only task; it should ensure workflow job names and repository protection guidance converge on the BRAINDUMP list without requiring skipped deploy jobs or introducing iOS deployment.

## Acceptance Criteria

- [ ] Workflow job names are stable, ASCII-only, and map to the required checks: `backend / tests`, `backend / lint`, `backend / compile`, `backend / coverage >= 80`, `backend / docker build`, `ios / build`, `ios / unit and ui tests`, `ios / coverage >= 80`, `ios / screenshots`, and `prod / healthz smoke`.
- [ ] Branch protection guidance requires only checks that run for the relevant event; skipped deploy-only jobs are not required on pull requests.
- [ ] The final status-check list confirms GitHub builds and tests iOS but does not sign, archive, upload, TestFlight, App Store deploy, or otherwise deploy iOS.
- [ ] Backend deploy remains GitHub Actions to Hetzner and depends on passing backend gates before image push/deploy.
- [ ] Any renamed workflow jobs are coordinated with branch protection so required checks do not get stranded under obsolete names.
- [ ] The repo contains a durable reference for maintainers showing which workflow job owns each required status check.

## Implementation Notes


Attempt 1: Added the missing iOS unit/UI status check in .github/workflows/ios-ci.yml, split coverage onto the saved xcresult, documented the branch-protection contract in docs/ops/branch-protection.md, and updated contract tests plus doc links.