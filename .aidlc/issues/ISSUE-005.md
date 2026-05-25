# ISSUE-005: Test backend admin logs redaction and SSE

**Priority**: high
**Labels**: backend, tests, admin-logs, redaction
**Dependencies**: ISSUE-002, ISSUE-016
**Status**: implemented

## Description

Protect the admin diagnostic surface from leaking provider secrets, raw user text, request JSON, raw model responses, or raw device tokens. Use `.aidlc/discovery/findings.md` and `.aidlc/research/backend-admin-log-redaction-and-sse.md` for event shape, session-cookie, SSE, and retention contracts, and ISSUE-016 for deterministic admin route tests.

## Acceptance Criteria

- [ ] Admin REST log responses return `events` with stable `id`, `timestamp`, `level`, `category`, `message`, and `details` fields.
- [ ] SSE stream tests verify named `log` events and JSON `data:` payloads matching the REST event shape.
- [ ] Session-cookie flow is tested for EventSource-compatible access without requiring raw admin keys in browser stream requests.
- [ ] Redaction tests prove request events expose lengths, codes, latency, model/request IDs, and status metadata without raw user text, provider keys, raw provider bodies, request JSON, or device tokens.
- [ ] Retention and clear behavior are tested around the fixed in-memory event buffer without assuming durable cross-process IDs.

## Implementation Notes


Attempt 1: Added admin event detail sanitization in Backend/app/admin_events.py and expanded Backend/tests/test_admin_routes.py to cover REST shape, SSE log payloads, cookie stream auth, redaction metadata, retention, and clear behavior.