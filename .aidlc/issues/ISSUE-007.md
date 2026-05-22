# ISSUE-007: Add operational home continuity scenario

**Priority**: high
**Labels**: phase-7, scenario, continuity, home
**Dependencies**: ISSUE-002, ISSUE-003, ISSUE-005
**Status**: implemented

## Description

Add the BRAINDUMP Scenario 2 seeded operational-home scenario for household continuity, including the dog continuity example implied by the seed-mode examples. Findings show ContinuityScenarioRegressionTests has programmatic coverage but no named fixture or launched scenario. Use .aidlc/research/operational-home-scenario-shape.md to cover air filters, dog food cadence, oil changes, warehouse purchases, garage cleaning, recurring maintenance, Thing grouping, and reminder inference without overcreating reminders.

## Acceptance Criteria

- [ ] A named operational_home fixture and a dog_continuity-compatible seed id seed Home Air Filters, dog food cadence, car/oil maintenance, Harbor Warehouse purchases, garage cleaning, recurring maintenance records, and relevant reminders/review candidates.
- [ ] Scenario assertions verify continuity accumulation, Thing grouping, operational interval inference, and suppression when an explicit reminder already covers an inferred cadence.
- [ ] Dog food and air-filter cadence assertions verify recurring purchase/replacement history produces reviewable operational signals without silently mutating user reminders.
- [ ] Ordinary purchases and garage maintenance remain searchable/replayable without incorrectly producing interval reminders outside supported tracks.
- [ ] The simulator walkthrough captures Timeline, Things, Thing detail, Carry Forward, and Search checkpoints for this seeded state.

## Implementation Notes


Attempt 1 failed (sample):
OpenAI CLI timed out
Attempt 2: Added/verified operational_home seed coverage: bundled fixture, dog_continuity alias, continuity regression assertions, fixture validation, and simulator walkthrough checkpoints for Timeline, Things, Thing detail, Carry Forward, and Search.