# ISSUE-019: Add screenshot capture baselines and visual diff scripts

**Priority**: high
**Labels**: phase-7, screenshots, visual-regression, ci
**Dependencies**: ISSUE-014
**Status**: implemented

## Description

Build the actual screenshot regression gate around ISSUE-014 screenshot mode. Findings show no Fastlane directory, snapshot configuration, screenshot artifacts, or visual diff system. Use .aidlc/research/screenshot-regression-stack.md while honoring BRAINDUMP's desired toolchain: XCUITest captures, simulator launch scripts, and a Fastlane Snapshot/lane entry point or compatible wrapper for recurring capture runs.

## Acceptance Criteria

- [ ] A LifeOrganizeScreenshotTests UI test class captures stable named screenshots for Timeline, Things, Thing detail, Carry Forward, Search, Review queue, empty states, heavy states, and first launch.
- [ ] Scripts run screenshot tests into a known xcresult, extract PNG attachments with stable names, and place generated actual/diff artifacts outside checked-in baselines.
- [ ] Checked-in baselines are organized by simulator/device and appearance, with generated artifacts ignored by source control.
- [ ] A deterministic diff script compares actual screenshots against baselines with documented thresholds and fails CI when thresholds are exceeded.
- [ ] A Fastlane Snapshot/lane entry point or documented compatible wrapper can invoke the same deterministic screenshot capture set without creating a second source of screenshot truth.
- [ ] One repeatable command or CI target runs the full screenshot capture and comparison path end-to-end.
- [ ] Simulator launch scripts or test wrappers set device destination and OS-level screenshot variables where possible, including status bar/battery/network chrome, appearance, text size, orientation, notifications, and reduced motion.

## Implementation Notes


Attempt 1: Added LifeOrganizeScreenshotTests, iPhone_16/light PNG baselines, screenshot run/extract/Swift diff tooling, BuildArtifacts ignore, and Fastlane lanes delegating to the same runner.