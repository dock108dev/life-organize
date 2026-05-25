# ISSUE-021: Expand iOS ledger review queue tests

**Priority**: high
**Labels**: ios, tests, review-queue, functionality, design-visual
**Dependencies**: ISSUE-018
**Status**: implemented

## Description

Cover BRAINDUMP's ledger review queue testing scope: item generation, safety actions, presentation, reconciliation, and consistency scenarios. Use `.aidlc/discovery/findings.md` surfaces around `LedgerReviewQueueService`, `LedgerReviewQueueActions`, `LedgerReviewItemGenerationService*`, `LedgerReviewItemPresentation`, and existing scenario fixtures, including cross-surface visual consistency for review state.

## Acceptance Criteria

- [ ] Review item generation tests cover ambiguous, failed, partial, stale, retryable, and consistency-warning inputs.
- [ ] Safety action tests cover approve, dismiss, reconcile, retry-related actions, and destructive/no-op boundaries.
- [ ] Queue items are generated from chat failures, partial extraction warnings, stale reminders, relationship inconsistencies, and imported web records when those states require review.
- [ ] Review item presentation tests assert deterministic labels, badge semantics, action priority, grouping, and hierarchy without duplicate objective/explanatory text.
- [ ] Review queue visual language stays consistent with ledger rows, search results, timeline rows, and rule/thing detail states for comparable statuses.
- [ ] Reconciliation tests prove queue state stays consistent after record edits, deletes, retries, local clears, migrations, and scenario reloads.
- [ ] Review actions update the underlying message, attempt, record, and queue state atomically enough that search, timeline, rules, and things do not show contradictory state.
- [ ] Scenario tests include at least one populated review queue fixture used consistently by unit, UI, and screenshot coverage.

## Implementation Notes


Attempt 1: Added LedgerReviewQueueExpandedCoverageTests covering generation for failed/retryable/partial/stale/imported records, action consistency across queue/search/timeline/thing/rule projections, shared review badge language, and scenario reload after local clear.