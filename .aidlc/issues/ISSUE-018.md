# ISSUE-018: Prevent duplicate Thing drift in seeded scenarios

**Priority**: high
**Labels**: phase-7, thing-identity, duplicate-drift, scenario-testing
**Dependencies**: ISSUE-003, ISSUE-005, ISSUE-011
**Status**: implemented

## Description

Add a dedicated identity-drift QA layer for the BRAINDUMP risk of duplicate Things and relationship drift. ISSUE-011 owns raw relationship integrity; this issue uses .aidlc/research/thing-duplicate-drift-prevention.md to assert the ThingResolver/ThingNormalizer outcome classes across seeded scenarios.

## Acceptance Criteria

- [ ] Scenario tests classify identity outcomes as automaticMerge, newSeededThing, newDistinctThing, or reviewCandidate and assert the expected class per fixture input.
- [ ] Tests assert Thing count before/after, canonical name, normalizedKey, category, aliases, linked record IDs, and provenance for each identity-sensitive input.
- [ ] Seeded exact identities reuse existing Things when current rules allow it and do not create duplicate rows.
- [ ] Ambiguous acronym, abbreviation, category-conflict, and blocked-context cases create review candidates rather than silent automatic merges.
- [ ] LedgerReviewItemGenerationService duplicate and normalization candidate outputs are asserted after refresh so duplicate drift cannot remain hidden.

## Implementation Notes


Attempt 1: Added identity-drift scenario coverage in LifeOrganizeTests/ThingIdentityContinuityTests.swift and guarded generic filter matching in ThingNormalizationCandidate.swift so ambiguous saved filter identities create review candidates instead of silent merges.