# ISSUE-020: Expand iOS reminder and rule lifecycle tests

**Priority**: high
**Labels**: ios, tests, reminders, rules, functionality
**Dependencies**: ISSUE-018
**Status**: implemented

## Description

Cover BRAINDUMP's reminder/rule lifecycle scope: creation, updates, carry-forward, pause/resume language, ambiguity handling, operational intervals, stale reminders, and rules list/detail/actions. Use `.aidlc/discovery/findings.md` surfaces under `LifeOrganize/Features/Rules/`, `ReminderRuleLifecycleMutation`, `RuleStatusService`, `OperationalIntervalInferenceService`, and related presentation services.

## Acceptance Criteria

- [ ] Tests cover creating and updating reminder/rule records from extraction and manual mutation paths.
- [ ] Carry-forward tests cover due, stale, completed, paused, resumed, and deactivated lifecycle states.
- [ ] Pause/resume and ambiguity handling tests assert the correct persisted lifecycle state, next action availability, and downstream queue/search/timeline visibility.
- [ ] Operational interval inference tests cover recurring, date-based, ongoing, ambiguous, timezone-sensitive, and stale intervals with deterministic dates.
- [ ] Rules UI contract tests cover list/detail/action state transitions and navigation-relevant identifiers needed by UI tests.
- [ ] Rule lifecycle mutations propagate consistently to ledger review queue generation, thing detail relationships, timeline visibility, and recall answers.

## Implementation Notes


Attempt 1: Expanded reminder/rule lifecycle coverage across extraction and manual mutation paths, pause visibility, stale/timezone interval inference, Carry Forward UI contracts, and downstream queue/search/timeline/thing-detail/recall behavior. Centralized Carry Forward accessibility identifiers.