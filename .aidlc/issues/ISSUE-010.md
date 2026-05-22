# ISSUE-010: Generate and validate heavy-history scenario

**Priority**: high
**Labels**: phase-7, scenario, heavy-history, performance
**Dependencies**: ISSUE-002, ISSUE-003, ISSUE-005
**Status**: failed

## Description

Add the BRAINDUMP Scenario 5 heavy-history state with 500+ entries. Findings show no heavy-history fixture generator or scroll/performance scenario. Use .aidlc/research/heavy-history-generation.md and .aidlc/research/timeline-density-visual-contracts.md to generate deterministic multi-month records and validate chronology, density, scrolling, search, reminders, notes, reviews, and repeatable performance behavior.

## Acceptance Criteria

- [ ] A heavy_history generator or fixture creates at least 500 feed-visible entries across events, notes, reminders/rules, review messages, and hidden succeeded messages using stable UUID and date formulas.
- [ ] Generated data spans multiple months and includes future reminders, historical notes, review-needed messages, repeated searchable keywords, and linked Things.
- [ ] Scenario assertions verify Timeline section ordering, newest-first tie breakers, timeline slice replay ordering, and search ranking determinism.
- [ ] A UI walkthrough scrolls the heavy Timeline enough to catch rendering/performance regressions and records a heavy_timeline screenshot checkpoint.
- [ ] Heavy-history launch, initial projection, search, and scrolling complete within explicit test timeouts without XCTest idle hangs or unbounded async retries.
- [ ] The generator uses fixed clock/calendar/time zone and never Date(), UUID(), random shuffling, or nondeterministic collection ordering.

## Implementation Notes


Attempt 1 failed (sample):
Used heavy-history-generation.md and timeline-density-visual-contracts.md. Git status unavailable because this directory is not a git repository.
Attempt 2 failed (sample):
Used .aidlc/research/heavy-history-generation.md and .aidlc/research/timeline-density-visual-contracts.md. Required xcodebuild test command passed.
Attempt 3 failed (sample):
Used .aidlc/research/heavy-history-generation.md and .aidlc/research/timeline-density-visual-contracts.md. Required xcodebuild test command passed. Directory is not a Git repository.