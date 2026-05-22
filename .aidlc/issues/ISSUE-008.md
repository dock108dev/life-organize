# ISSUE-008: Add ambiguous human entry and review queue scenario

**Priority**: high
**Labels**: phase-7, scenario, review-queue, ambiguity
**Dependencies**: ISSUE-003, ISSUE-004, ISSUE-005
**Status**: implemented

## Description

Add the BRAINDUMP Scenario 3 for the input 'I think bogey needs a haircut in a week or two'. Findings show generic extraction review items exist, but no deterministic scenario proves ambiguous suggested interpretation, date-window review, and relationship linking. Use .aidlc/research/ambiguous-human-entry-review-flow.md and .aidlc/research/review-queue-scenario-contract.md.

## Acceptance Criteria

- [ ] Mock extraction for the Bogey haircut input preserves the raw message, likely Thing, intended action, and ambiguous 'in a week or two' date window without silently committing an arbitrary due date.
- [ ] The scenario produces a review item with a concrete suggested interpretation and target/source evidence rather than only generic 'Entry needs review' copy.
- [ ] If a Bogey Thing already exists in the seed, the candidate links to it; if not, the new Thing or match review follows current ThingResolver safety rules.
- [ ] Review queue assertions cover item kind, state, target, detail/action text, evidence, dedupe behavior, and no mutation on generation.
- [ ] The UI walkthrough opens Review queue, verifies the ambiguous entry is visible, and captures a review_queue screenshot checkpoint.

## Implementation Notes


Attempt 1 failed (sample):
OpenAI CLI timed out
Attempt 2: Strengthened deterministic Bogey grooming extraction coverage to assert raw source text, suggested haircut action, null date-window ownership, warning severity, and no finalized rule/note for the ambiguous reminder fixture.