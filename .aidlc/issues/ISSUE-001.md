# ISSUE-001: Formalize deterministic launch and fresh-install reset modes

**Priority**: high
**Labels**: phase-7, infra, launch-modes, determinism
**Dependencies**: none
**Status**: implemented

## Description

Create the Phase 7 launch contract in LifeOrganize/Utilities/AppRuntimeConfiguration.swift and the app bootstrap path. Findings show current support for -ui-testing, -reset-store, -reset-api-key, -use-fake-extractor, and -fixed-now, but no BRAINDUMP --reset-db alias, no seeded scenario/screenshot flags, and no full local-state reset beyond the UI-testing SQLite store. Use .aidlc/research/launch-mode-contract.md and .aidlc/research/fresh-install-state-boundaries.md to keep existing single-dash UI test flags compatible while adding owner-facing double-dash aliases where BRAINDUMP names them and preventing unsafe reset behavior outside deterministic modes.

## Acceptance Criteria

- [ ] AppRuntimeConfiguration parses -screenshot-mode, -seed-scenario=<id>, --seed-scenario=<id>, --reset-db, and the existing -ui-testing/-reset-store/-reset-api-key/-use-fake-extractor/-fixed-now flags without breaking current UI tests.
- [ ] --reset-db is a documented compatibility alias for deterministic fresh-install startup and composes safely with the existing -reset-store UI-test behavior.
- [ ] Fresh-install launch mode resets or isolates SwiftData test store files, API key state, app-owned UserDefaults including DeveloperMode.isUnlocked, cache/temp state owned by the app, and scene restoration before first UI render.
- [ ] Reset behavior is scoped so deterministic test/screenshot modes cannot accidentally delete production user data or production keychain state.
- [ ] Flag precedence is deterministic when reset, seed, screenshot, fake extractor, fixed time, and API-key reset flags are combined in one launch.
- [ ] The supported launch argument contract is covered by unit tests for parsing and at least one UI launch smoke test that proves existing single-dash flags and BRAINDUMP double-dash aliases both work.

## Implementation Notes


Attempt 1 failed (sample):
OpenAI CLI timed out
Attempt 2: Added automation-only seed scenario loading before first UI render, wired it into LifeOrganizeApp startup after reset/container creation, and added unit coverage for idempotent seeding and production isolation.