# AIDLC Planning Index

## Intent Source (authoritative)
- BRAINDUMP.md

## Reference Docs (optional context — never expand scope)
- README.md

## Discovery (pre-built — current repo state)
- .aidlc/discovery/findings.md
- .aidlc/discovery/topics.json

## Research (pre-built — answers to discovery topics)
- .aidlc/research/ambiguous-human-entry-review-flow.md
- .aidlc/research/extraction-quality-dashboard-model.md
- .aidlc/research/first-launch-visual-state.md
- .aidlc/research/fresh-install-state-boundaries.md
- .aidlc/research/heavy-history-generation.md
- .aidlc/research/internal-qa-mode-surface.md
- .aidlc/research/launch-mode-contract.md
- .aidlc/research/local-json-export-as-baseline.md
- .aidlc/research/mock-extraction-fixture-library.md
- .aidlc/research/operational-home-scenario-shape.md
- .aidlc/research/relationship-integrity-validator.md
- .aidlc/research/review-queue-scenario-contract.md
- .aidlc/research/scenario-fixture-format.md
- .aidlc/research/scenario-test-runner-output.md
- .aidlc/research/screenshot-mode-determinism.md
- .aidlc/research/screenshot-regression-stack.md
- .aidlc/research/search-power-feature-coverage.md
- .aidlc/research/simulator-walkthrough-automation.md
- .aidlc/research/swiftdata-seed-loader-shape.md
- .aidlc/research/temporal-ambiguity-matrix.md
- .aidlc/research/thing-duplicate-drift-prevention.md
- .aidlc/research/timeline-density-visual-contracts.md
- .aidlc/research/timeline-replay-and-search-interaction.md
- .aidlc/research/work-continuity-scenario-shape.md

## Existing Issues (22 files in .aidlc/issues/)
Read individual issue files for full specs:
- .aidlc/issues/ISSUE-001.md
- .aidlc/issues/ISSUE-002.md
- .aidlc/issues/ISSUE-003.md
- .aidlc/issues/ISSUE-004.md
- .aidlc/issues/ISSUE-005.md
- .aidlc/issues/ISSUE-006.md
- .aidlc/issues/ISSUE-007.md
- .aidlc/issues/ISSUE-008.md
- .aidlc/issues/ISSUE-009.md
- .aidlc/issues/ISSUE-010.md
- .aidlc/issues/ISSUE-011.md
- .aidlc/issues/ISSUE-012.md
- .aidlc/issues/ISSUE-013.md
- .aidlc/issues/ISSUE-014.md
- .aidlc/issues/ISSUE-015.md
- .aidlc/issues/ISSUE-016.md
- .aidlc/issues/ISSUE-017.md
- .aidlc/issues/ISSUE-018.md
- .aidlc/issues/ISSUE-019.md
- .aidlc/issues/ISSUE-020.md
- .aidlc/issues/ISSUE-021.md
- .aidlc/issues/ISSUE-022.md

## Issue Backlog Summary
- Total issues: 22
- Completion: 0/22 (0.0%)
- Priority totals: high=18, medium=4, low=0
- Status totals: pending=22

### Category Rollup (Labels)
- phase-7: 22
- scenario: 5
- scenario-testing: 5
- ci: 2
- continuity: 2
- determinism: 2
- extraction-quality: 2
- fixtures: 2
- internal-qa: 2
- relationships: 2
- review-queue: 2
- scenario-runner: 2
- screenshots: 2
- visual-regression: 2
- ambiguity: 1
- artifacts: 1
- density: 1
- developer-tools: 1
- duplicate-drift: 1
- export: 1
- first-launch: 1
- heavy-history: 1
- home: 1
- infra: 1
- integrity: 1
- launch-modes: 1
- mock-extraction: 1
- performance: 1
- qa: 1
- quality-dashboard: 1
- regression-baseline: 1
- screenshot-mode: 1
- search: 1
- seeded-state: 1
- swiftdata: 1
- temporal-qa: 1
- thing-identity: 1
- timeline: 1
- timeline-replay: 1
- ux-qa: 1
- walkthrough: 1
- work-continuity: 1
- xcuitest: 1

### Active Issues
- ISSUE-001 [pending] [high] — Formalize deterministic launch and fresh-install reset modes labels: phase-7, infra, launch-modes, determinism
- ISSUE-002 [pending] [high] — Add canonical JSON scenario fixture library labels: phase-7, fixtures, scenario-testing
- ISSUE-003 [pending] [high] — Load named seed scenarios before first UI render labels: phase-7, seeded-state, swiftdata
- ISSUE-004 [pending] [high] — Convert deterministic extraction to fixture-backed mock mode labels: phase-7, mock-extraction, fixtures
- ISSUE-005 [pending] [high] — Build deterministic scenario runner and simulator walkthrough labels: phase-7, scenario-runner, xcuitest, walkthrough
- ISSUE-006 [pending] [high] — Lock first-launch fresh install scenario labels: phase-7, scenario, first-launch, ux-qa
- ISSUE-007 [pending] [high] — Add operational home continuity scenario labels: phase-7, scenario, continuity, home
- ISSUE-008 [pending] [high] — Add ambiguous human entry and review queue scenario labels: phase-7, scenario, review-queue, ambiguity
- ISSUE-009 [pending] [high] — Add work continuity relationship scenario labels: phase-7, scenario, work-continuity, relationships
- ISSUE-010 [pending] [high] — Generate and validate heavy-history scenario labels: phase-7, scenario, heavy-history, performance
- ISSUE-011 [pending] [high] — Run relationship integrity and duplicate drift validation for every scenario labels: phase-7, integrity, relationships, scenario-testing
- ISSUE-012 [pending] [high] — Add temporal ambiguity QA matrix labels: phase-7, temporal-qa, extraction-quality
- ISSUE-013 [pending] [medium] — Add search power-feature QA matrix labels: phase-7, search, timeline-replay, qa
- ISSUE-014 [pending] [high] — Add screenshot mode and visual regression gate labels: phase-7, screenshots, screenshot-mode, determinism
- ISSUE-015 [pending] [medium] — Build Internal QA Lab with extraction quality metrics labels: phase-7, internal-qa, developer-tools
- ISSUE-016 [pending] [high] — Add canonical ledger export comparison for scenario baselines labels: phase-7, export, regression-baseline, scenario-testing
- ISSUE-017 [pending] [high] — Emit deterministic scenario run artifact bundles labels: phase-7, artifacts, ci, scenario-runner
- ISSUE-018 [pending] [high] — Prevent duplicate Thing drift in seeded scenarios labels: phase-7, thing-identity, duplicate-drift, scenario-testing
- ISSUE-019 [pending] [high] — Add screenshot capture baselines and visual diff scripts labels: phase-7, screenshots, visual-regression, ci
- ISSUE-020 [pending] [medium] — Lock timeline density and visual rhythm screenshots labels: phase-7, visual-regression, timeline, density
- ISSUE-021 [pending] [medium] — Add internal extraction quality dashboard labels: phase-7, quality-dashboard, extraction-quality, internal-qa
- ISSUE-022 [pending] [high] — Add review queue consistency scenario matrix labels: phase-7, review-queue, scenario-testing, continuity

### Completed Issues
- none

## Other Project Docs
- docs/audits/docs-consolidation.md
- docs/current-app-state.md
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibInstallName-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibPath-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-ExecutorLinkFileList-normal-arm64.txt
- .build/DerivedData/Build/Intermediates.noindex/XCBuildData/59b0c2fd170e68abcda845916f2943f2.xcbuilddata/target-graph.txt
- .deriveddata/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibInstallName-normal-arm64.txt
- .deriveddata/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-DebugDylibPath-normal-arm64.txt
- .deriveddata/Build/Intermediates.noindex/LifeOrganize.build/Debug-iphonesimulator/LifeOrganize.build/LifeOrganize-ExecutorLinkFileList-normal-arm64.txt
- .deriveddata/Build/Intermediates.noindex/XCBuildData/358be672e6f2f11eb3173c2bb7b5c4fe.xcbuilddata/target-graph.txt
- .deriveddata/Build/Intermediates.noindex/XCBuildData/4bc9b5e735765d1d5ec0ea623971a087.xcbuilddata/target-graph.txt
- .deriveddata/Build/Intermediates.noindex/XCBuildData/bbe24457e9c07085fc377490007ff2c0.xcbuilddata/target-graph.txt
- .deriveddata/Build/Intermediates.noindex/XCBuildData/e9bb7d47c4949fda516a18a2c182adc6.xcbuilddata/target-graph.txt
- BRAINDUMP.md
