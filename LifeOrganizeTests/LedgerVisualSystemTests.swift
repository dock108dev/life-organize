import XCTest
@testable import LifeOrganize

final class LedgerVisualSystemTests: XCTestCase {
    func testContinuityLanesUseSharedLedgerTones() {
        XCTAssertEqual(ReminderContinuityLane.now.tone, .attention)
        XCTAssertEqual(ReminderContinuityLane.comingUp.tone, .info)
        XCTAssertEqual(ReminderContinuityLane.review.tone, .attention)
        XCTAssertEqual(ReminderContinuityLane.paused.tone, .muted)
    }

    func testFeedSourceToneMappingCoversLedgerKinds() {
        XCTAssertEqual(LedgerTone(feedSource: .user), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .status), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .system), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .event), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .reminder), .muted)
        XCTAssertEqual(LedgerTone(feedSource: .note), .note)
    }

    func testSemanticBadgesCarryRoleMeaningAndPriorityOrdering() {
        let saved = LedgerBadgePresentation(semantic: .statusSaved)
        let note = LedgerBadgePresentation(semantic: .categoryNote)
        let review = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 90)
        let visible = LedgerBadgePresentation.visibleBadges(from: [note, saved, review], maxCount: 2)

        XCTAssertEqual(saved.role, .status)
        XCTAssertEqual(saved.label, "Saved")
        XCTAssertEqual(saved.tone, .muted)
        XCTAssertEqual(note.role, .category)
        XCTAssertEqual(note.tone, .note)
        XCTAssertEqual(review.role, .action)
        XCTAssertEqual(visible.map(\.semantic), [.actionReview, .statusSaved])
    }

    func testRowDensityDefinesCompactAndStandardRhythm() {
        XCTAssertEqual(LedgerRowDensity.compact.verticalSpacing, 2)
        XCTAssertEqual(LedgerRowDensity.compact.verticalPadding, 6)
        XCTAssertEqual(LedgerRowDensity.standard.verticalSpacing, 4)
        XCTAssertEqual(LedgerRowDensity.standard.verticalPadding, 2)
        XCTAssertEqual(LedgerRowDensity.detail.verticalSpacing, 4)
        XCTAssertEqual(LedgerVisualSystem.Padding.rowHorizontal, 8)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowAccessoryGap, 10)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowBadgeGap, 5)
        XCTAssertEqual(LedgerPillSize.micro.horizontalPadding, 4)
        XCTAssertEqual(LedgerPillSize.micro.verticalPadding, 1)
    }

    func testNoticeRhythmExposesSharedSpacingTokens() {
        XCTAssertEqual(LedgerVisualSystem.Spacing.noticeContentGap, 8)
        XCTAssertEqual(LedgerVisualSystem.Spacing.noticeActionGap, 6)
        XCTAssertEqual(LedgerVisualSystem.Padding.noticeHorizontal, 12)
        XCTAssertEqual(LedgerVisualSystem.Padding.noticeVertical, 8)
    }

    func testSearchRowsUseQuietLedgerPresentation() {
        let ruleID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let record = LocalSearchRecord(
            id: ruleID,
            kind: .rule,
            title: "Renew registration",
            subtitle: "Due May 21, 2026",
            body: "For Honda Civic",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: UUID(),
            linkedThingName: "Honda Civic",
            isActiveRule: true,
            ruleBadge: "Now",
            ruleLane: .now,
            timelineDateRange: nil,
            navigationTarget: .ruleDetail(ruleID)
        )
        let result = LocalSearchResult(record: record, matchedFields: [.title], score: 1)
        let presentation = LocalSearchResultRowPresentation(result: result)

        XCTAssertEqual(presentation.primaryText, "Renew registration")
        XCTAssertEqual(presentation.kindPillText, "Reminder")
        XCTAssertEqual(presentation.kindPillTone, .muted)
        XCTAssertEqual(presentation.rulePillText, "Now")
        XCTAssertEqual(presentation.rulePillTone, .attention)
        XCTAssertEqual(presentation.badges.map(\.role), [.status, .category])
        XCTAssertEqual(presentation.badges.map(\.semantic), [.statusNow, .categoryReminder])
        XCTAssertEqual(presentation.footerText, "For Honda Civic")
        XCTAssertEqual(presentation.dateText, DateFormatting.shortDate.string(from: fixedTestNow))
        XCTAssertEqual(presentation.secondaryLines.first?.text, presentation.dateText)
        XCTAssertEqual(presentation.secondaryLines.map(\.lineLimit), [1, 1, 2])
        XCTAssertEqual(LedgerSurfaceDensity.searchResultRow.rowDensity, .compact)
    }

    func testRelatedContextRowsUseRecordTypePillsAndDateLines() {
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: fixedTestNow,
            rawText: "Changed oil."
        )
        let records = RelationshipTraversalRecords(events: [event])
        let result = RelationshipTraversalResult(
            target: .event(event.id),
            navigationTarget: .eventDetail(event.id),
            source: .linkedThing,
            sourceLabel: "Linked thing",
            sourceMessageID: nil,
            dedupeKey: "event-\(event.id.uuidString)",
            confidence: nil,
            createdBy: nil
        )
        let presentation = RelatedContextRowPresentation(result: result, records: records)

        XCTAssertEqual(presentation.primaryText, "Oil change")
        XCTAssertEqual(presentation.badgeText, "Event")
        XCTAssertEqual(presentation.badgeTone, .muted)
        XCTAssertEqual(presentation.secondaryLines.first?.text, "Linked thing")
        XCTAssertEqual(presentation.secondaryLines.count, 2)
    }
}
