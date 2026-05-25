# ISSUE-018: Expand iOS SwiftData persistence coverage

**Priority**: high
**Labels**: ios, tests, swiftdata, persistence, functionality
**Dependencies**: ISSUE-010
**Status**: implemented

## Description

Add or deepen iOS unit/integration tests for the SwiftData persistence scope BRAINDUMP names: migrations, seed scenarios, relationship integrity, delete/reassignment behavior, ledger export, and local data clearing. Use `.aidlc/discovery/findings.md` and `.aidlc/research/swiftdata-coverage-denominator.md` to target `ModelContainerFactory`, active schema, migration plan, seed loader, local clearing, export, and relationship validators without counting generated-heavy snapshots as ordinary app behavior.

## Acceptance Criteria

- [ ] Tests cover `ModelContainerFactory` standard, in-memory, and URL-backed store behavior where practical.
- [ ] Migration tests prove V1 and V2 stores open through the active V3 container and preserve chat messages, attempts, things, events, rules, notes, review items, and entity links as applicable.
- [ ] Seed scenario tests validate shipped JSON fixtures, seed loading fallback behavior, and scenario records used by screenshots/UI tests.
- [ ] Relationship integrity tests cover delete/reassignment behavior for things, events, rules, notes, source messages, extraction attempts, and review items.
- [ ] After deletes, reassignments, migrations, and local clears, dependent projections such as timeline slices, search results, review queue items, thing detail relationships, and rule relationships no longer show stale orphaned data.
- [ ] Ledger export and local data clearing tests prove exports omit service tokens/secrets and clearing removes local records while preserving or resetting the device token only according to the intended flow.

## Implementation Notes


Attempt 1: Expanded SwiftData persistence coverage in PersistenceCoverageTests and added review-reference cleanup for delete/reassign paths. Export, fixture, and audit validators now treat review type none as note-backed so note review evidence stays valid.