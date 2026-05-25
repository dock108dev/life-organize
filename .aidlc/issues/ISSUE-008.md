# ISSUE-008: Lock frontend backend-default and secret guardrails

**Priority**: high
**Labels**: ios, tests, configuration, security, copy-contracts
**Dependencies**: none
**Status**: implemented

## Description

Add iOS unit/static tests proving every frontend environment defaults to `https://life.dock108.dev`, local backend is explicit launch-arg-only, provider secrets remain backend-owned, and primary UI copy/formatting stays product-facing. Use `.aidlc/discovery/findings.md`, `.aidlc/research/frontend-default-backend-contract.md`, `.aidlc/research/frontend-secret-surface-guardrails.md`, and `.aidlc/research/ios-ui-test-live-network-boundary.md`.

## Acceptance Criteria

- [ ] Tests assert `AppRuntimeConfiguration.defaultAIServiceBaseURL` is exactly `https://life.dock108.dev` and does not drift by UI testing, screenshot, seed, reset, in-memory, deterministic extraction, debug, or developer-mode flags.
- [ ] Tests assert only valid `-ai-service-base-url=` or `--ai-service-base-url=` launch args can override the backend URL, and invalid/empty schemes fall back to production.
- [ ] `AIServiceClient` and runtime configuration share one production default or have drift-catching tests that observe the actual request URL.
- [ ] Routine UI tests are guarded to use deterministic extraction and avoid live backend/OpenAI calls unless a specific smoke test is explicitly scoped.
- [ ] Static/copy/export guardrail tests prove no frontend provider API key, OpenAI secret, authorization header, bearer token, or raw device token is exposed in primary UI or local exports.
- [ ] Primary settings/search/ledger/review copy tests cover duplicate objective/explanatory text and deterministic display formatting, including inline Settings literals that are not currently centralized.

## Implementation Notes


Attempt 1: Centralized the iOS backend default, added runtime/network/copy/export guardrails, redacted secret-like export strings, aligned AIServiceClient default URL, and stabilized stale review/seeded UI expectations.