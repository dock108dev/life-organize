# ISSUE-006: Lock first-launch fresh install scenario

**Priority**: high
**Labels**: phase-7, scenario, first-launch, ux-qa
**Dependencies**: ISSUE-001, ISSUE-005
**Status**: implemented

## Description

Add the BRAINDUMP Scenario 1 first-launch product scenario. Findings and .aidlc/research/first-launch-visual-state.md show current empty-state components and UI tests exist, but Phase 7 needs a deterministic scenario asserting the composed fresh-install behavior: empty Timeline, missing key notice, suggestions, composer, tabs, toolbar, entry flow, and no stale state.

## Acceptance Criteria

- [ ] The scenario launches from a true fresh-install reset with no SwiftData records, no API key, no extraction cache, no review queue, and cleared app-owned local state.
- [ ] Timeline is the selected initial tab and shows the missing-key notice, empty-state title/body, suggestions, composer, disabled send button, Settings, and root search controls.
- [ ] Whitespace-only composer input keeps send disabled and does not create messages, extraction attempts, review items, or seeded records.
- [ ] A valid first entry through mock extraction follows the expected local capture path and creates only the deterministic records for that message.
- [ ] Things and Carry Forward tabs are reachable and render empty or post-entry states without stale data from earlier runs.
- [ ] The scenario captures a named first_launch or timeline_empty screenshot checkpoint for visual regression.
- [ ] The scenario fails if developer mode, prior selected tab, stale review items, persisted seed data, or prior API key state leak into first launch.

## Implementation Notes


Attempt 1: Added a first-launch fresh-install UI scenario covering reset launch, empty Timeline, missing-key state, whitespace no-op, first_launch screenshot, deterministic first entry, and Things/Carry Forward stale-state checks.