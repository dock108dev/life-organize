# ISSUE-022: Expand iOS UI journey and offline coverage

**Priority**: high
**Labels**: ios, ui-tests, offline, local-first, functionality, usability-flow, design-visual
**Dependencies**: ISSUE-008, ISSUE-018, ISSUE-019, ISSUE-020, ISSUE-021
**Status**: implemented

## Description

Add UI test coverage for the visible frontend flows BRAINDUMP lists beyond screenshot comparison: first launch, chat input and ledger feed, timeline, things, rules, search, review queue, debug/internal QA surfaces intentionally shipped in debug builds, and offline/local-first behavior when the backend is unavailable. Use `.aidlc/discovery/findings.md` and `.aidlc/research/ios-ui-test-live-network-boundary.md`, with visual coherence checks kept to already scoped screens and states.

## Acceptance Criteria

- [ ] UI tests cover first launch, chat input, ledger feed, timeline navigation, things list/detail/edit/delete, rules list/detail/actions, search open/dismiss/result navigation, and review queue.
- [ ] First-launch UI coverage proves a new user can reach the primary local-first workflow without needing to configure a local backend.
- [ ] UI tests cover debug/internal QA surfaces that remain intentionally available in debug builds without exposing provider secrets.
- [ ] Offline/local-first UI tests simulate backend unavailability through deterministic or stubbed boundaries and prove local data remains usable.
- [ ] At least one UI flow sends a chat entry while the backend boundary is unavailable, verifies the local message remains visible, then navigates to related ledger/review state without a live network call.
- [ ] Recovery flows for pending token, retryable backend failure, and review-needed states have reachable next actions and do not strand the user on a dead end.
- [ ] Primary states across first launch, ledger feed, timeline, things, rules, search, review queue, and debug surfaces use consistent hierarchy for titles, status badges, actions, and empty states.
- [ ] A guard test or static UI-test lint prevents routine UI tests from bypassing `launchUITestApp(...)` and launching without deterministic extraction.
- [ ] UI tests remain deterministic with fixed time, locale, animations disabled, reset/seed flags, and no live OpenAI calls.

## Implementation Notes


Attempt 1 failed (sample):
OpenAI CLI timed out
Attempt 2: Added deterministic offline AI-service simulation, expanded UI journey/offline/debug coverage, strengthened UI launch determinism, and added runtime/network guard tests.