# ISSUE-009: Expand iOS chat send reliability tests

**Priority**: high
**Labels**: ios, tests, chat, local-first, functionality
**Dependencies**: ISSUE-008
**Status**: implemented

## Description

Broaden iOS unit/integration coverage for the local-first chat send path named in BRAINDUMP: local save before backend, backend extraction request, fallback, retry, idempotency, stale completion, web import edge cases, and continuity state. Use `.aidlc/research/chat-send-local-first-failure-matrix.md` and `.aidlc/research/chat-send-idempotency-contract.md`.

## Acceptance Criteria

- [ ] Tests prove user messages and extraction attempts are persisted before extraction or web import awaits backend work.
- [ ] Backend failure, timeout, token failure, rate limit, invalid response, and network failure map to local retry/review/token states without losing the raw message.
- [ ] Retry tests prove attempt counts, retry scheduling, retry delay caps, and stale completion handling do not duplicate or resurrect cleared data.
- [ ] Idempotency tests cover event, rule, note, and thing creation keyed by source message plus extractor client ID across retry and repeated extraction, including idempotent entity-link creation.
- [ ] Stale normal extraction success/failure, stale retry, stale web answer, and stale web import cases are covered so old async results cannot write into a newer data generation.
- [ ] Web lookup and web import modes are covered with stubbed clients, including no-client behavior and the web-import no-payload edge case so import attempts cannot remain silently incomplete.

## Implementation Notes


Attempt 1: Added chat send reliability coverage for local-first persistence, failure mapping, retry backoff/stale guards, web lookup/import modes, and repeated idempotent retries. Web import responses without payload now fail the saved attempt instead of leaving it incomplete.