# ISSUE-002: Add canonical JSON scenario fixture library

**Priority**: high
**Labels**: phase-7, fixtures, scenario-testing
**Dependencies**: ISSUE-001
**Status**: implemented

## Description

Build the Tests/Fixtures/ scenario fixture library requested by BRAINDUMP. Findings show there is no JSON scenario directory and current scenarios are hand-built in tests. Use .aidlc/research/scenario-fixture-format.md to define versioned, export-shaped, diffable fixtures with stable UUIDs, clocks, chronology, source messages, review items, and entity links. Canonical export comparison is handled separately in ISSUE-016.

## Acceptance Criteria

- [ ] A Tests/Fixtures/ directory exists with bundled JSON fixtures and decoding types/tests that document the fixture schema in code.
- [ ] Fixture records mirror the current LedgerExportEnvelope/ExportRecords shape where practical and include fixtureSchemaVersion, ledgerSchemaVersion, id, title, description, clock, records, and expectations.
- [ ] Initial fixture files exist for car_maintenance, ambiguous_dog_grooming, work_continuity, heavy_history, timeline_search, and first_launch_empty or equivalent scenario ids.
- [ ] Fixture decoding rejects missing required fields, invalid timestamps, duplicate IDs within a model type, unresolved references, invalid enum values, and inconsistent source links with actionable failures.
- [ ] Fixture expectations can express required counts, required visible surfaces, relationship checks, search/replay expectations, and review queue expectations without embedding Swift test logic inside JSON.

## Implementation Notes


Attempt 1: Added canonical JSON scenario fixtures under LifeOrganizeTests/Fixtures plus test-target decoding and strict validation for schema versions, required fields, timestamps, duplicate IDs, references, enum values, source links, chronology, and data-driven expectations.