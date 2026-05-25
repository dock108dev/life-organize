# ISSUE-002: Expand backend config auth and rate-limit tests

**Priority**: high
**Labels**: backend, tests, auth, rate-limit
**Dependencies**: ISSUE-001, ISSUE-016
**Status**: implemented

## Description

Broaden backend tests around production config validation, route auth, admin auth, device token hashing/signing, optional expiration behavior, and per-device rate limiting. Use `.aidlc/discovery/findings.md`, `.aidlc/research/backend-route-auth-test-matrix.md`, and `.aidlc/research/backend-rate-limit-contract.md`. This turns existing narrow auth helper coverage into route-level production gateway protection using the shared backend test harness from ISSUE-016.

## Acceptance Criteria

- [ ] Production/staging settings fail fast when required secrets or a non-production database URL are missing, while development defaults remain development-only.
- [ ] `POST /api/v1/extractions` and `POST /api/v1/web-requests` reject missing, blank, whitespace, and too-short device tokens with the stable backend error contract.
- [ ] Valid device-token route tests use mocked gateway behavior and never call OpenAI.
- [ ] Admin routes cover missing, wrong, exact, and padded admin API keys, including session-cookie behavior for log streaming where applicable.
- [ ] Rate-limit tests prove per-device and per-endpoint counting, rolling-window reset behavior, retry status/header behavior if implemented, shared-IP behavior if added, and no raw token logging or persistence.
- [ ] If token expiration is added during implementation, expired-token behavior is covered at the route level; if not added, tests document that current device tokens are length/hash validated only.

## Implementation Notes


Attempt 1: Expanded backend auth/config/rate-limit coverage in tests: shared SQLite route harness, production/staging config checks, device/admin route auth matrices, admin session/SSE checks, token redaction, and per-device/per-endpoint/window rate-limit contracts.