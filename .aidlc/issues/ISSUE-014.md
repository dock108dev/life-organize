# ISSUE-014: Add screenshot mode and visual regression gate

**Priority**: high
**Labels**: phase-7, screenshots, screenshot-mode, determinism
**Dependencies**: ISSUE-001, ISSUE-003, ISSUE-005
**Status**: implemented

## Description

Implement app-level screenshot mode determinism for the mandatory visual regression system. Findings show -fixed-now exists but no explicit screenshot mode. Use .aidlc/research/screenshot-mode-determinism.md to freeze app-owned state and presentation inputs. Baseline capture/diff scripts are split into ISSUE-019, and timeline visual contracts are split into ISSUE-020.

## Acceptance Criteria

- [ ] -screenshot-mode is parsed and activates deterministic UI-test-safe storage, deterministic extractor behavior, fixed local state, and no production keychain/network dependency.
- [ ] Screenshot mode can choose or derive a seed scenario, fixed current date, API key state, starting surface, locale/time-zone/calendar inputs, and animation/loading behavior where app-controlled.
- [ ] Screenshot mode avoids focused inputs, keyboard drift, first-run prompts, and async loading states at capture checkpoints.
- [ ] Screenshot mode is compatible with seeded scenarios for empty, default, review, search, carry-forward, and heavy states.
- [ ] Unit and UI launch tests prove screenshot mode produces repeatable first visible state with the same fixed arguments across repeated launches.

## Implementation Notes


Attempt 1: Added screenshot mode parsing and deterministic launch behavior in runtime/app root, including seeded scenario routing, fixed date/locale/time zone/calendar, key state, animation suppression, unfocused capture state, and repeatable UI launch coverage.