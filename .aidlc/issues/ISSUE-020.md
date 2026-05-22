# ISSUE-020: Lock timeline density and visual rhythm screenshots

**Priority**: medium
**Labels**: phase-7, visual-regression, timeline, density
**Dependencies**: ISSUE-010, ISSUE-019
**Status**: pending

## Description

Add focused rendered visual contracts for the BRAINDUMP risks of density drift, visual hierarchy decay, and timeline quality loss. Unit tests protect constants, but .aidlc/research/timeline-density-visual-contracts.md explains where SwiftUI rendering needs screenshot coverage.

## Acceptance Criteria

- [ ] Screenshot coverage includes a populated ChatView ledger feed with timestamp, marker, divider, row content, badges, and day sections visible.
- [ ] Screenshots prove divider alignment begins at the content column and remains aligned with timestamp and marker chrome.
- [ ] Narrow-width screenshots cover LedgerFeedRow fallback behavior, long text wrapping, and badge/pill compression without overlap.
- [ ] Cross-surface screenshots compare shared LedgerRow density on search results, Things rows, reminders, and detail summaries.
- [ ] Heavy-history screenshots verify dense scrolling rhythm and visual continuity after many records, not only the first screen.