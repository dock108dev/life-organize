# Large File Follow-Up List

Generated: 2026-06-03

This list tracks non-binary repository files still above roughly 500 lines after the documentation consolidation pass. Screenshot baseline PNGs are binary visual assets and are excluded from this source/documentation LOC review.

## Source Code

No production Swift or Python source file is currently above 500 lines.

## Tests

No Swift test source file is currently above 500 lines.

## Fixtures

| Lines | File | Disposition |
| ---: | --- | --- |
| 1101 | `LifeOrganize/Resources/SeedScenarios/operational_home.json` | Retain for now. Large seed fixture; split only if fixture loading gains composition support. |
| 1101 | `LifeOrganizeTests/Fixtures/operational_home.json` | Retain for now. Mirrors app seed fixture for test validation. |
| 647 | `LifeOrganize/Resources/SeedScenarios/work_continuity.json` | Retain for now. Large scenario fixture; split only with a shared fixture-composition design. |
| 647 | `LifeOrganizeTests/Fixtures/work_continuity.json` | Retain for now. Mirrors app seed fixture for test validation. |

## Documentation

No maintained Markdown file is currently above 500 lines.

## Generated Project Files

| Lines | File | Disposition |
| ---: | --- | --- |
| 539 | `LifeOrganize.xcodeproj/project.pbxproj` | Retain. Xcode project metadata; not hand-refactored for LOC. |
