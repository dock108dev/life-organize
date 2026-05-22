# ISSUE-021: Add internal extraction quality dashboard

**Priority**: medium
**Labels**: phase-7, quality-dashboard, extraction-quality, internal-qa
**Dependencies**: ISSUE-012, ISSUE-015, ISSUE-018, ISSUE-022
**Status**: implemented

## Description

Implement the BRAINDUMP internal-only quality telemetry dashboard as a separate tool from the QA Lab shell. Findings show per-record quality signals exist in ChatMessage, ExtractionAttempt, LedgerReviewItem, and EntityLink, but no aggregate counters. Use .aidlc/research/extraction-quality-dashboard-model.md and feed it with deterministic seeded scenarios, temporal QA, duplicate-drift QA, and review queue scenarios so extraction quality can be tracked without user analytics.

## Acceptance Criteria

- [ ] The dashboard is available only through developer/internal QA gating and is not exposed as a user analytics surface.
- [ ] Metrics include deterministic vs AI attempts, extraction candidate volume, attempt coverage, strict and operational success rates, status distribution, retry backlog, attention burden, and extraction latency.
- [ ] Review metrics include review rate, open/resolved review counts by kind, duplicate Thing review creation, normalization candidate volume, temporal/conflicting-date review volume, and failed review action counts where derivable.
- [ ] Failed temporal interpretation is represented explicitly through available error codes, review kinds, or deterministic temporal QA fixture outcomes rather than inferred from generic failures only.
- [ ] Entity/link metrics include graph density, link confidence distribution, extraction-created link coverage, and orphan-like patterns from the relationship validator where available.
- [ ] Dashboard test data can be produced from deterministic fixtures/scenarios so metric counts are stable in CI.
- [ ] Dashboard copy labels derived review/quality values as proxy metrics and does not imply ground-truth precision or recall where the stored data cannot prove it.

## Implementation Notes


Attempt 1: Added a developer-gated extraction quality metrics route under Internal QA Lab, with SwiftData aggregation for extraction, review, temporal, retry, latency, and entity-link proxy health metrics plus deterministic fixture coverage tests.