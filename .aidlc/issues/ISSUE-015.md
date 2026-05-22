# ISSUE-015: Build Internal QA Lab with extraction quality metrics

**Priority**: medium
**Labels**: phase-7, internal-qa, developer-tools
**Dependencies**: ISSUE-001, ISSUE-003, ISSUE-011
**Status**: implemented

## Description

Build the hidden Internal QA Lab surface requested by BRAINDUMP. Findings show developer diagnostics are extraction-attempt lists only, with no fixture loading, reset DB, fake dates, graph inspection, reprocess hub, or timeline jumping. Use .aidlc/research/internal-qa-mode-surface.md. The aggregate extraction quality dashboard is split into ISSUE-021 but should be routed from this lab.

## Acceptance Criteria

- [ ] Settings developer diagnostics exposes an Internal QA Lab only when developer mode is available and unlocked; normal user builds do not surface the route.
- [ ] QA Lab routes support fixture loading, QA-grade database reset, fake/effective date control, timeline jumping, selected entry reprocessing, relationship graph inspection, and links to existing extraction attempt diagnostics.
- [ ] Fixture loading uses the named scenario registry from ISSUE-003 and reports seed success/failure without duplicating records.
- [ ] Graph inspection surfaces relationship-integrity findings, orphaned links, extraction provenance, and affected source records using the validator from ISSUE-011.
- [ ] QA actions are implemented through explicit services rather than direct one-off SwiftUI mutations, so tests can exercise them without tapping the UI.

## Implementation Notes


Attempt 1: Added hidden Internal QA Lab route, QA fixture/reset/fake-date/reprocess/timeline/graph services and views, app relationship validator, seed-loader hooks, and service tests covering gating, idempotent fixture loads, reset, fake date, graph inspection, and timeline jumps.