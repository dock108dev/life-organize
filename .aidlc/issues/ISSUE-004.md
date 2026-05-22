# ISSUE-004: Convert deterministic extraction to fixture-backed mock mode

**Priority**: high
**Labels**: phase-7, mock-extraction, fixtures
**Dependencies**: ISSUE-001, ISSUE-002
**Status**: implemented

## Description

Replace the fragile hard-coded mock extractor shape with a deterministic message-to-payload fixture registry while preserving existing behavior. Findings show -use-fake-extractor exists but DeterministicMessageExtractionClient is an ordered substring chain, not the BRAINDUMP fixture mapping. Use .aidlc/research/mock-extraction-fixture-library.md to migrate safely with parity tests, deterministic fallback behavior, collision handling, and scenario fixture integration.

## Acceptance Criteria

- [ ] DeterministicMessageExtractionClient keeps the existing MessageExtractionClient contract, requestJSON mode, and modelName while delegating response selection to an ordered fixture registry.
- [ ] Existing deterministic extraction outputs remain behaviorally identical for current tests before new fixture coverage is added.
- [ ] Fixture entries map message patterns or exact test messages to deterministic payload builders and preserve relative-date behavior from the supplied fixed now.
- [ ] Fixture matching order is explicit and tested so overlapping patterns cannot change behavior accidentally.
- [ ] Unmatched messages use a deterministic fallback response or deterministic failure path that is stable across runs and never calls OpenAI.
- [ ] The BRAINDUMP example Replace air filter in 2 months is covered by a deterministic fixture payload that resolves to Home Air Filters with a stable two-month reminder window.
- [ ] Mock extraction fixtures cover at least the first launch no-op path, operational home inputs, Bogey ambiguous grooming, work continuity inputs, temporal matrix examples, and review queue partial/failure cases without calling OpenAI.

## Implementation Notes


Attempt 1: Converted DeterministicMessageExtractionClient to delegate to an ordered fixture registry, split event/rule-note fixtures, added deterministic no-op, fallback, ordering, metadata, and ambiguous grooming coverage.