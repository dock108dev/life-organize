# ISSUE-013: Add search power-feature QA matrix

**Priority**: medium
**Labels**: phase-7, search, timeline-replay, qa
**Dependencies**: ISSUE-003, ISSUE-010
**Status**: pending

## Description

Build search QA for the BRAINDUMP power-feature expectations and lock the search-to-timeline-replay bridge. Findings show current search is strong local substring/date search but lacks explicit matrix coverage for fragments, aliases, fuzzy-ish expectations, date slices, Things, reminders, notes, timeline recall, and replay descriptor alignment. Use .aidlc/research/search-power-feature-coverage.md and .aidlc/research/timeline-replay-and-search-interaction.md.

## Acceptance Criteria

- [ ] A deterministic search QA suite runs against seeded data covering fragments, aliases, date slices, Things, reminders/rules, notes, chat messages, and timeline slice recall.
- [ ] Tests document and assert current localSubstring behavior where fuzzy matching is not implemented, so typo/near-match gaps are visible without pretending support exists.
- [ ] Alias tests prove linked Thing aliases influence Thing, event, reminder, and note retrieval with stable ranking.
- [ ] Date-slice tests cover supported relative day/week/month/year, upcoming, since/from month, month-year, and year queries.
- [ ] Cross-feature tests assert search query in, timeline slice descriptor out, and replay rows out stay semantically aligned for date ranges, text filters, linked Thing filters, inactive reminders, and destination routing.
- [ ] Search result navigation is validated from the UI walkthrough for event, Thing, reminder/rule, note, and timeline slice destinations.