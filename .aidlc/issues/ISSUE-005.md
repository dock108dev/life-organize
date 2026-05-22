# ISSUE-005: Build deterministic scenario runner and simulator walkthrough

**Priority**: high
**Labels**: phase-7, scenario-runner, xcuitest, walkthrough
**Dependencies**: ISSUE-001, ISSUE-003, ISSUE-004
**Status**: implemented

## Description

Create the Phase 7 deterministic simulator walkthrough instead of only unit tests. Findings show LifeOrganizeUITests has deterministic launch helpers but no full walkthrough across product surfaces. Use .aidlc/research/simulator-walkthrough-automation.md to add durable XCUITest traversal and the missing accessibility identifiers. Scenario artifact output is split into ISSUE-017.

## Acceptance Criteria

- [ ] A deterministic XCUITest walkthrough launches with fixed time, mock extraction, reset state, and a named seed scenario.
- [ ] The walkthrough covers Timeline, Things, Thing detail, Carry Forward, Search, Review queue, and Settings in one repeatable simulator journey.
- [ ] Stable accessibility identifiers are added for Timeline rows, Things list/rows/detail, Carry Forward rows/detail, Review queue rows/detail/actions, Search results, and sheet close controls where text fallback is currently required.
- [ ] The walkthrough validates search result navigation into at least one detail/replay destination and verifies returning to the previous surface.
- [ ] The walkthrough can be invoked from xcodebuild or a script suitable for CI without live network extraction.

## Implementation Notes


Attempt 1: Added stable accessibility identifiers across Timeline, Things/detail, Carry Forward/detail, Search results/close, Review queue/detail/actions, and Settings. Added a deterministic XCUITest simulator walkthrough covering seeded launch, mock extraction, navigation, search replay, review queue, and settings.