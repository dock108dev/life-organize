# ISSUE-011: Run relationship integrity and duplicate drift validation for every scenario

**Priority**: high
**Labels**: phase-7, integrity, relationships, scenario-testing
**Dependencies**: ISSUE-003, ISSUE-005
**Status**: implemented

## Description

Build the whole-store relationship integrity validation layer required by BRAINDUMP continuity trust. Findings show EntityLink uses raw UUID references and broken links can be silently dropped by traversal. Use .aidlc/research/relationship-integrity-validator.md to validate seeded scenarios for broken references, invalid link shapes, review references, and timeline continuity both immediately after seeding and after scenario actions such as review corrections, retries, merges, relaunches, and search/replay navigation.

## Acceptance Criteria

- [ ] A RelationshipIntegrityValidator fetches the whole SwiftData store and reports all failures in one structured result instead of failing on the first broken row.
- [ ] The validator checks unique IDs per relationship-bearing model, valid EntityLink raw enum values, EntityLink source/target existence, compatible relation shapes, and sourceMessageID consistency.
- [ ] Event, rule/reminder, note, chat message, extraction attempt, review item, and entity link references are validated against existing source records where persisted model fields allow it.
- [ ] Timeline continuity checks verify replay/search descriptors do not point to missing records and that relationship traversal does not silently drop seeded source links.
- [ ] Relationship audits run after initial seed load and after scenario mutations that can change links, including review queue actions, duplicate merges/reassignments, manual retry/reprocess, and relaunch persistence checks.
- [ ] The deterministic scenario runner fails any seeded scenario that has orphaned links, invalid references, broken review evidence, or relationship audit errors.

## Implementation Notes


Attempt 1: Added whole-store relationship integrity scenario validation, fixed seed relationship mapping and stale rule/alias drift, and preserved extraction attempt references across thing merge/delete maintenance.