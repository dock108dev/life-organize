# Large File Follow-Up List

Generated: 2026-05-30

This list tracks non-binary repository files still above roughly 500 lines after the cleanup pass. Screenshot baseline PNGs are binary visual assets and are excluded from this source/documentation LOC review.

## Source Code

No Swift or Python source file is currently above 500 lines.

## Fixtures

| Lines | File | Disposition |
| ---: | --- | --- |
| 1101 | `LifeOrganize/Resources/SeedScenarios/operational_home.json` | Retain for now. Large seed fixture; split only if fixture loading gains composition support. |
| 1101 | `LifeOrganizeTests/Fixtures/operational_home.json` | Retain for now. Mirrors app seed fixture for test validation. |
| 647 | `LifeOrganize/Resources/SeedScenarios/work_continuity.json` | Retain for now. Large scenario fixture; split only with a shared fixture-composition design. |
| 647 | `LifeOrganizeTests/Fixtures/work_continuity.json` | Retain for now. Mirrors app seed fixture for test validation. |

## Documentation

| Lines | File | Disposition |
| ---: | --- | --- |
| 589 | `docs/audits/abend-handling-audit.md` | Retain as a detailed audit artifact. Summarize or archive when the abend remediation work is closed. |
| 583 | `docs/audits/abend-hardening-implementation-plan.md` | Retain as a detailed implementation plan. Collapse into a short status doc when complete. |
| 517 | `docs/planning/production-visual-polish.md` | Retain as owner intent/planning context. Convert into smaller issue docs if this planning thread becomes active again. |
