# ISSUE-010: Define iOS coverage denominator and parser

**Priority**: high
**Labels**: ios, coverage, scripts, usability-flow, new-feature
**Dependencies**: none
**Status**: implemented

## Description

Add the new reusable iOS coverage gate requested by BRAINDUMP: a checked-in parser around `xcrun xccov view --report --json` that gates the `LifeOrganize` app target at 80%. Use `.aidlc/research/ios-xccov-app-target-parser.md` and `.aidlc/research/swiftdata-coverage-denominator.md` for target selection and denominator policy. This capability must be callable by both local verification scripts and GitHub iOS CI.

## Acceptance Criteria

- [ ] A checked-in script parses `BuildArtifacts/LifeOrganizeTests.xcresult` or a caller-supplied xcresult path and exits nonzero when app-target coverage is below 80%.
- [ ] The parser includes the `LifeOrganize` app target and excludes test targets from the denominator.
- [ ] Generated, fixture-heavy, or UI-only shell code exclusions are explicit in code/config and reported separately so hidden exclusions are visible.
- [ ] The parser output includes app-target coverage percent, threshold, included target names, excluded target/file names, and the xcresult path.
- [ ] The parser is covered by synthetic JSON fixture tests for pass, fail, missing app target, malformed JSON, and multiple target cases.
- [ ] Both `Scripts/verify-ios.sh` and the iOS CI workflow can call the same parser without duplicating coverage threshold logic.

## Implementation Notes


Attempt 1: Added reusable iOS xccov app-target coverage gate, synthetic parser tests, local verify script, and iOS CI workflow. The gate includes LifeOrganize.app, excludes test targets and explicit generated/schema/UI-shell files, and reports scope plus exclusions.