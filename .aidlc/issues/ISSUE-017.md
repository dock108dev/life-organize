# ISSUE-017: Emit deterministic scenario run artifact bundles

**Priority**: high
**Labels**: phase-7, artifacts, ci, scenario-runner
**Dependencies**: ISSUE-005, ISSUE-011, ISSUE-016, ISSUE-019
**Status**: implemented

## Description

Add planner/CI-readable outputs for deterministic scenario runs. ISSUE-005 owns walkthrough execution; this issue owns the artifact contract from .aidlc/research/scenario-test-runner-output.md: xcresult, summaries, ledger exports, relationship audits, and screenshot references in a stable bundle layout. It depends on ISSUE-019 because screenshot artifacts must be collected using the same deterministic capture path as the visual regression gate.

## Acceptance Criteria

- [ ] Each deterministic run creates artifacts/scenario-runs/<run-id>/ with a scenario-run-summary.json containing run id, git info, xcode destination, determinism flags, status, counts, and artifact paths.
- [ ] Each scenario emits scenario.json with id, name, kind, source test identifier, launch arguments, inputs, expected signals, status, and artifact paths.
- [ ] Each scenario emits ledger-export.json through LocalJSONExportService and validates it against the required top-level record collections.
- [ ] Each scenario emits relationship-audit.json and relationship-audit.md using the validator from ISSUE-011.
- [ ] Scenario screenshots or screenshot directory references are included when checkpoints are captured, and missing expected screenshots are reported as artifact failures.
- [ ] Failed, errored, timed-out, or skipped runs still emit whatever summary, logs, exports, audits, and screenshots are available for triage.
- [ ] CI fails when the run status is not passed, relationship audit failures are present, a required artifact is missing, or a required artifact cannot be parsed.

## Implementation Notes


Attempt 1: Added deterministic scenario artifact bundle models/writer, ledger export validation, relationship audit JSON/Markdown generation, semantic checks, screenshot artifact failure reporting, and unit coverage. UI test support now forwards artifact dirs and can mirror screenshot PNGs.