# ISSUE-022: Add review queue consistency scenario matrix

**Priority**: high
**Labels**: phase-7, review-queue, scenario-testing, continuity
**Dependencies**: ISSUE-005, ISSUE-008, ISSUE-011, ISSUE-012, ISSUE-018
**Status**: implemented

## Description

Expand review QA beyond the single ambiguous Bogey scenario in ISSUE-008. BRAINDUMP calls out review queue inconsistency and trustworthy review systems as core risk areas. Use .aidlc/research/review-queue-scenario-contract.md to cover ambiguous extraction, duplicate Things, temporal conflicts, local recovery, partial extraction, and screenshot/artifact visibility for review states. Depend on ISSUE-008 and ISSUE-012 so ambiguous and temporal cases share canonical scenario behavior instead of drifting into parallel expectations.

## Acceptance Criteria

- [ ] Deterministic review scenarios cover ambiguous extraction, duplicate Things, temporal conflicts, local recovery, and partial extraction with fixed clocks and stable UUIDs.
- [ ] Each generated review item asserts kind, state, target type/id, confidence, title/detail/action, evidence, createdAt/updatedAt, and dedupe key behavior.
- [ ] Queue entries assert correction class, primary action title, blocked/unblocked state, ordering/focus behavior, and stable presentation in the Review queue UI.
- [ ] Blocked review actions show deterministic, specific explanations and leave the item open with a clear next step.
- [ ] Generation does not mutate source records, merge Things, change dates, create retry attempts, or silently delete stale generated items except through explicit supersede behavior.
- [ ] Retry, dismiss, mark reviewed, save as note, merge duplicate Things, reassign records, and adjust reminder timing actions either complete fully or fail without partial mutation and without closing the item.
- [ ] After any successful or failed review action, the user can return to the queue, source record, or related Thing without losing navigation context.
- [ ] At least one review queue screenshot checkpoint and one scenario artifact bundle include review queue state for regression triage.

## Implementation Notes


Attempt 1: Added deterministic review queue scenario coverage for ambiguous extraction, duplicate Things, temporal conflicts, local recovery, partial extraction, action atomicity, navigation context, and artifact screenshot/export state; partial extraction review evidence now includes created notes.