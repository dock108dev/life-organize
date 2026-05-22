# ISSUE-009: Add work continuity relationship scenario

**Priority**: high
**Labels**: phase-7, scenario, work-continuity, relationships
**Dependencies**: ISSUE-002, ISSUE-003, ISSUE-005
**Status**: implemented

## Description

Add the BRAINDUMP Scenario 4 for work continuity across cloud functions, scanner, vulnerabilities, monorepo, migrations, aliases, traversal, and recall. Findings show related unit tests exist but no named seeded scenario. Use .aidlc/research/work-continuity-scenario-shape.md to preserve current normalization rules where ambiguous acronym/abbreviation matches require review.

## Acceptance Criteria

- [ ] A named work_continuity fixture seeds Nimbus Web Services, Aster Cloud Functions, SignalScan, Vulnerabilities, Monorepo Migration, migration notes/events/reminders, aliases, and source provenance.
- [ ] Assertions verify relationship traversal from a work reminder surfaces linked Thing, same-message note, shared-source event, and related work Things in deterministic order.
- [ ] Normalization assertions verify NWS and vulns-style aliases create review candidates where current rules disallow silent automatic merge.
- [ ] Review correction flow can reassign records to a canonical work Thing and local recall/search reflects the corrected relationship.
- [ ] Exported JSON and relationship audit output prove source-message, entity-link, Thing, event, note, and reminder references stay intact.

## Implementation Notes


Attempt 1: Added the work_continuity seed fixture and regression coverage for work aliases, traversal, correction, recall, export integrity, and review retargeting after Thing merge.