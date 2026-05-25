# ISSUE-012: Integrate screenshot comparison into iOS CI

**Priority**: medium
**Labels**: ios, screenshots, ci, usability-flow, design-visual
**Dependencies**: ISSUE-011
**Status**: implemented

## Description

Add screenshot comparison and failure artifacts to the iOS CI shape. Use `.aidlc/discovery/findings.md`, `.aidlc/research/screenshot-ci-cadence-and-artifacts.md`, and `.aidlc/research/ios-ci-runner-simulator-pin.md`; preserve the existing deterministic screenshot stack and baselines while making comparison failures easy to recover from and protecting visual coherence across the core app surfaces.

## Acceptance Criteria

- [ ] CI runs `Scripts/screenshots/run-screenshot-tests.sh compare` for UI-affecting PRs and on main pushes, or always if runtime cost is accepted by implementation.
- [ ] The workflow uses the existing screenshot defaults unless the simulator pin is deliberately changed with baseline implications handled explicitly.
- [ ] Screenshot coverage continues to protect first launch, timeline empty, populated timeline, heavy timeline, things, thing detail, carry forward, search, and review queue.
- [ ] On failure, CI uploads `BuildArtifacts/ScreenshotTests.xcresult`, actual screenshots, diff screenshots, and comparison logs.
- [ ] Path filters cover app rendering code, assets, localization, UI tests, screenshot scripts, baselines, fastlane screenshot lanes, and shared formatting/model code that changes visible text.
- [ ] Screenshot failure output distinguishes missing actuals, size mismatch, unexpected screenshots, and pixel-diff failures, and points to the relevant actual/diff/baseline paths.
- [ ] If simulator device or runtime changes, accepted baselines prove no text truncation, incoherent overlap, missing navigation titles, or hidden primary rows on the protected screens.
- [ ] The workflow does not refresh baselines automatically; baseline updates remain an explicit developer action with the local update/compare flow easy to discover from the failure output.

## Implementation Notes


Attempt 1: Added iOS screenshot comparison CI with default simulator/baseline pins, failure artifact uploads, compare logs, path filters, failure-mode output, docs, and tests. Stabilized screenshot capture timing to avoid mid-transition detail screenshots.