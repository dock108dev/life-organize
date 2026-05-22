# ISSUE-016: Add canonical ledger export comparison for scenario baselines

**Priority**: high
**Labels**: phase-7, export, regression-baseline, scenario-testing
**Dependencies**: ISSUE-002, ISSUE-003
**Status**: implemented

## Description

Make LocalJSONExportService usable as a regression baseline instead of only a user portable-copy feature. Findings show export already captures the ledger graph but has volatile fields and incomplete comparison semantics. Use .aidlc/research/local-json-export-as-baseline.md to add canonical normalization and comparison policies for scenario fixtures and run artifacts.

## Acceptance Criteria

- [ ] A LedgerExportCompareService or equivalent compares expected and actual LedgerExportEnvelope values under explicit policies: exact export equality, canonical ledger equality, extraction provenance equality, and UI-facing scenario equality.
- [ ] Canonical comparison ignores or normalizes volatile envelope fields such as exportedAt and optionally appBuild/platform while still checking schemaVersion and scenario-relevant locale/time-zone semantics.
- [ ] All exported top-level and nested collections are sorted with stable tie breakers before comparison, including metadata and created entity lists.
- [ ] Comparison failures report precise JSON paths and expected/actual values rather than only byte-level file diffs.
- [ ] At least one seeded scenario test loads a fixture, exports the resulting store through LocalJSONExportService, and compares it with a canonical baseline.

## Implementation Notes


Attempt 1: Added ledger export comparison policies, canonical sorting/normalization, JSON-path diff reporting, and seeded fixture export baseline coverage in LedgerExportCompareService/JSONDiffer tests.