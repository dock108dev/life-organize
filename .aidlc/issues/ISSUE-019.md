# ISSUE-019: Expand iOS search recall timeline and things tests

**Priority**: high
**Labels**: ios, tests, search, timeline, things, functionality, design-visual
**Dependencies**: ISSUE-018
**Status**: implemented

## Description

Cover the frontend testing scope for local-first search/recall, timeline slices, thing/event/rule visibility, recall continuity, empty states, and things list/detail/edit/delete. Use `.aidlc/discovery/findings.md` sections for search, recall, timeline, things, and existing tests under `LifeOrganizeTests/` as the implementation surface, including presentation-level consistency for rows, snapshots, empty states, and deterministic formatting.

## Acceptance Criteria

- [ ] Search tests cover local-first ranking, empty states, result grouping, timeline slices, and visibility of things, events, rules, and notes.
- [ ] Recall tests cover continuity answers, prior note lookup, last-time lookup, rule lookup, and behavior when no local records match.
- [ ] Timeline projection tests cover empty, populated, heavy, filtered/sliced, and stale-data-after-delete states with deterministic ordering and formatting.
- [ ] Things tests cover list, detail, edit, delete/reassignment, alias/normalization behavior, and relationship traversal back to events/rules/notes.
- [ ] Search, recall, timeline, and things behavior reflects record edits, retries, review reconciliation, local clears, and migration results without requiring app restart.
- [ ] Presentation/snapshot tests keep timeline rows, search result rows, thing previews, thing detail summaries, badges, dates, and empty-state formatting visually consistent with the shared ledger visual system.
- [ ] No search/recall/timeline tests require a live backend or OpenAI call; any backend-shaped behavior is stubbed at the client/service boundary.

## Implementation Notes


Attempt 1: Expanded local-first iOS coverage across search/recall, timeline projections, thing snapshots, reassignment, local clear, and migrated-record projections in six existing XCTest files.