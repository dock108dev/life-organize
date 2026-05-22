# ISSUE-003: Load named seed scenarios before first UI render

**Priority**: high
**Labels**: phase-7, seeded-state, swiftdata
**Dependencies**: ISSUE-001, ISSUE-002
**Status**: implemented

## Description

Implement the seeded scenario mode requested by BRAINDUMP. Findings show no seed scenario launch argument, no named scenario registry, and no seeding path before SwiftUI renders. Use .aidlc/research/swiftdata-seed-loader-shape.md with the fixture format from ISSUE-002: load synchronously after ModelContainer creation and before .modelContainer is injected into the UI, with atomic behavior for invalid or partially loadable fixtures.

## Acceptance Criteria

- [ ] -seed-scenario=<id> and --seed-scenario=<id> both resolve a bundled fixture id through a named scenario registry and fail clearly for unknown ids in test/debug contexts.
- [ ] Seeding runs synchronously after ModelContainerFactory creates the container and before the root app UI can query SwiftData.
- [ ] The loader is idempotent: launching the same scenario twice against the same store does not duplicate Things, events, reminders/rules, notes, review items, messages, or entity links.
- [ ] The loader uses deterministic UUIDs, fixture clocks, explicit timestamps, and fixture time zones rather than Date(), UUID(), random ordering, or dictionary iteration order.
- [ ] Seed loading is atomic: malformed fixtures, unresolved references, invalid enum values, or failed inserts do not leave partially seeded app state behind.
- [ ] Seeded launch mode composes with fresh-install reset so every major scenario can run from an empty store and then seed before first render.

## Implementation Notes


Attempt 1: Added bundled JSON-backed seed scenario loading with registry aliases, validation, deterministic fixture dates, idempotent SwiftData upserts, rollback-on-failure behavior, and launch/runtime tests.