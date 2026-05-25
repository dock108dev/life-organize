# ISSUE-003: Cover backend middleware and health contracts

**Priority**: high
**Labels**: backend, tests, middleware
**Dependencies**: ISSUE-001, ISSUE-016
**Status**: implemented

## Description

Add backend request-level tests for `Backend/main.py`, `SecurityHeadersMiddleware`, `RequestSizeLimitMiddleware`, and `/healthz`. Use `.aidlc/discovery/findings.md`, `.aidlc/research/backend-middleware-test-surface.md`, and `.aidlc/research/backend-coverage-gate-shape.md` to capture current behavior, including OPTIONS and Content-Length edge cases, through the shared test harness from ISSUE-016.

## Acceptance Criteria

- [ ] `GET /healthz` is tested as unauthenticated and returns the stable minimal liveness body.
- [ ] Tests prove security headers are added to ordinary HTTP responses and are not overwritten when already present.
- [ ] Tests explicitly cover OPTIONS behavior for security headers.
- [ ] Request-size tests cover allowed boundary, oversized declared Content-Length, missing Content-Length, and invalid Content-Length according to the current middleware contract.
- [ ] Tests cover production/staging docs and OpenAPI suppression versus development visibility if that behavior is retained in `Backend/main.py`.

## Implementation Notes


Attempt 1: Expanded Backend/tests/test_app_entrypoint.py with request-level coverage for unauthenticated /healthz, security header injection/preservation/OPTIONS behavior, request-size Content-Length edge cases, docs/OpenAPI environment visibility, and startup metadata.