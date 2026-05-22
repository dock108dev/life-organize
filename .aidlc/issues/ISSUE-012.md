# ISSUE-012: Add temporal ambiguity QA matrix

**Priority**: high
**Labels**: phase-7, temporal-qa, extraction-quality
**Dependencies**: ISSUE-004
**Status**: implemented

## Description

Create dedicated deterministic tests for temporal coherence, one of the BRAINDUMP's highest-risk systems. Findings show TemporalPriorityResolver covers numeric durations but not the full BRAINDUMP phrase matrix. Use .aidlc/research/temporal-ambiguity-matrix.md to distinguish deterministic app behavior, mock fixture coverage, review-preserved ambiguity, and model-dependent phrasing.

## Acceptance Criteria

- [ ] Tests cover the BRAINDUMP examples: in 90 days, next year, later this month, revisit next season, and replace in 2 months against a fixed now/time zone.
- [ ] The matrix explicitly asserts which phrases resolve deterministically, which preserve ambiguity for review, which are model-dependent, and which must not be guessed into committed reminders.
- [ ] Standing restrictions with review durations preserve ongoing restriction semantics while creating a separate review reminder where appropriate.
- [ ] Explicit window language such as until/through/between is tested so restriction windows are not erased by review-date logic.
- [ ] Failed or ambiguous temporal interpretations produce review/quality signals consumable by ISSUE-021 rather than disappearing as parser-only failures.

## Implementation Notes


Attempt 1: Added TemporalAmbiguityMatrixTests covering fixed-clock numeric review resolution, fixture-owned replace-in-2-months behavior, vague/seasonal ambiguity preservation, standing restriction review reminders, explicit windows, and review signals without committed reminders.