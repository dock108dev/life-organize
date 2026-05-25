# ISSUE-004: Stabilize backend gateway and DTO error contracts

**Priority**: high
**Labels**: backend, frontend-contract, tests, openai-gateway
**Dependencies**: ISSUE-001, ISSUE-016
**Status**: implemented

## Description

Make backend OpenAI gateway failures and iOS-facing request/error shapes explicit and test-covered without live OpenAI calls. Use `.aidlc/research/backend-openai-gateway-error-mapping.md`, `.aidlc/research/backend-request-contract-parity.md`, and `.aidlc/research/ai-client-error-shape-parity.md`; rely on ISSUE-016 for route/gateway stubbing.

## Acceptance Criteria

- [ ] Mocked gateway tests cover missing key, timeout, transport failure, 429, 5xx, 401/403, other non-2xx status, malformed JSON body, and missing output text.
- [ ] Route-level tests assert backend status codes and machine-readable error codes for extraction and web-request failures.
- [ ] Backend request/response schema tests catch drift against iOS DTO names for extraction, web answer, and web import modes.
- [ ] The strict OpenAI extraction schema name remains locked to the intended versioned name.
- [ ] iOS decoding expectations are reconciled with backend error response shapes, including nested FastAPI `detail` responses or a flattened backend error envelope.

## Implementation Notes


Attempt 1: Stabilized backend/iOS gateway contracts with mocked OpenAI error mapping tests, route error-code assertions, shared DTO/schema fixtures, schema-version lock tests, and iOS backend error envelope mapping in AIServiceClient.