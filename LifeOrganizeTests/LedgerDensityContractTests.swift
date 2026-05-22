import XCTest
@testable import LifeOrganize

final class LedgerDensityContractTests: XCTestCase {
    func testDensityTiersKeepRelativeLedgerRhythm() {
        XCTAssertLessThan(LedgerRowDensity.compact.verticalSpacing, LedgerRowDensity.standard.verticalSpacing)
        XCTAssertEqual(LedgerRowDensity.standard.verticalSpacing, LedgerRowDensity.detail.verticalSpacing)
        XCTAssertGreaterThan(LedgerRowDensity.compact.verticalPadding, LedgerRowDensity.standard.verticalPadding)
        XCTAssertEqual(LedgerRowDensity.standard.verticalPadding, LedgerRowDensity.detail.verticalPadding)
        XCTAssertEqual(LedgerVisualSystem.Padding.rowHorizontal, 8)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowAccessoryGap, 10)
        XCTAssertEqual(LedgerVisualSystem.Spacing.rowBadgeGap, 5)
    }

    func testPrimarySurfacesDeclareIntendedDensityAssignments() {
        XCTAssertEqual(LedgerSurfaceDensity.feedRow.rowDensity, .compact)
        XCTAssertEqual(LedgerSurfaceDensity.thingsRow.rowDensity, .compact)
        XCTAssertEqual(LedgerSurfaceDensity.searchResultRow.rowDensity, .compact)
        XCTAssertEqual(LedgerSurfaceDensity.reminderRow.rowDensity, .standard)
        XCTAssertEqual(LedgerSurfaceDensity.detailSummary.rowDensity, .detail)
    }

    func testReminderListUsesLighterEditorialRowChrome() {
        XCTAssertLessThan(ReminderListLayout.rowVerticalInset, LedgerVisualSystem.Padding.rowCompactVertical)
        XCTAssertLessThan(ReminderListLayout.rowHorizontalInset, LedgerVisualSystem.Padding.rowHorizontal)
        XCTAssertLessThan(ReminderListLayout.sectionSpacing, LedgerVisualSystem.Spacing.section)
    }

    func testFeedRowsStayDenseWithShortStatusAndMetadataLines() {
        let message = ChatMessage(
            role: .user,
            text: "Changed furnace filter.",
            extractionStatus: .pendingRetry
        )
        let content = LedgerFeedRowContent(item: .message(message))
        let visibleLines = [
            content.sourceLabel,
            content.primaryText,
            content.secondaryText,
            content.detailText,
            content.linkedThingText,
        ].compactMap(\.self)

        XCTAssertEqual(LedgerSurfaceDensity.feedRow.rowDensity, .compact)
        XCTAssertLessThanOrEqual(visibleLines.count, 3)
        XCTAssertEqual(content.secondaryText, "Retry later")
    }

    func testFeedTimelineUsesDenseEditorialRowGeometry() {
        XCTAssertEqual(LedgerFeedTimelineLayout.sectionSpacing, 16)
        XCTAssertEqual(LedgerFeedTimelineLayout.feedHorizontalPadding, 14)
        XCTAssertEqual(LedgerFeedTimelineLayout.feedTopPadding, 4)
        XCTAssertEqual(LedgerFeedTimelineLayout.feedBottomPadding, 10)
        XCTAssertEqual(LedgerFeedTimelineLayout.sectionContentSpacing, 8)

        XCTAssertEqual(LedgerFeedTimelineLayout.rowHorizontalPadding, 6)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowVerticalPadding, 5)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowContentSpacing, 2)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowColumnSpacing, 8)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowBadgeGap, 4)

        XCTAssertEqual(LedgerFeedTimelineLayout.timestampWidth, 56)
        XCTAssertEqual(LedgerFeedTimelineLayout.markerSize, 4)
        XCTAssertEqual(LedgerFeedTimelineLayout.dividerLeadingPadding, 82)
    }

    func testFeedTimelineGeometryTightensSharedRowChromeWithoutChangingProjectionDensity() {
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowHorizontalPadding, LedgerVisualSystem.Padding.rowHorizontal)
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowVerticalPadding, LedgerSurfaceDensity.feedRow.rowDensity.verticalPadding)
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowColumnSpacing, LedgerVisualSystem.Spacing.rowAccessoryGap)
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowBadgeGap, LedgerVisualSystem.Spacing.rowBadgeGap)
        XCTAssertLessThan(LedgerFeedTimelineLayout.markerSize, 6)
        XCTAssertEqual(LedgerSurfaceDensity.feedRow.rowDensity, .compact)
    }

    func testTimelineDividersRemainContentAlignedAndSubtle() {
        XCTAssertEqual(
            LedgerFeedTimelineLayout.dividerLeadingPadding,
            LedgerFeedTimelineLayout.rowHorizontalPadding
                + LedgerFeedTimelineLayout.timestampWidth
                + LedgerFeedTimelineLayout.rowColumnSpacing
                + LedgerFeedTimelineLayout.markerSize
                + LedgerFeedTimelineLayout.rowColumnSpacing
        )
        XCTAssertEqual(
            TimelineSliceReplayLayout.dividerLeadingPadding,
            LedgerVisualSystem.Padding.rowHorizontal
                + TimelineSliceReplayLayout.timestampWidth
                + LedgerVisualSystem.Spacing.rowAccessoryGap
                + TimelineSliceReplayLayout.markerSize
                + LedgerVisualSystem.Spacing.rowAccessoryGap
        )
        XCTAssertLessThan(TimelineSectionRowDividerStyle.opacity, 0.25)
        XCTAssertLessThanOrEqual(TimelineSectionRowDividerStyle.height, 0.5)
    }

    func testSearchThingsReminderAndDetailRowsBoundSecondaryLineCounts() throws {
        let search = LocalSearchResultRowPresentation(result: searchResult())
        let thing = thingWithContinuity()
        let preview = ThingPreviewSnapshot(thing: thing, now: fixedTestNow, calendar: testCalendar)
        let detail = ThingDetailSnapshot(thing: thing, now: fixedTestNow, calendar: testCalendar)
        let reminder = try XCTUnwrap(thing.rules.first)
        let reminderLines = LedgerReminderRowLines.lines(
            for: ReminderContinuityPresentationService().presentation(for: reminder, at: fixedTestNow),
            rule: reminder,
            reason: reminder.reason
        )

        XCTAssertEqual(LedgerSurfaceDensity.searchResultRow.rowDensity, .compact)
        XCTAssertLessThanOrEqual(search.secondaryLines.count, 3)
        XCTAssertEqual(search.secondaryLines.map(\.lineLimit), [1, 1, 2])
        XCTAssertEqual(LedgerSurfaceDensity.thingsRow.rowDensity, .compact)
        XCTAssertLessThanOrEqual(preview.continuityLines.count, 5)
        XCTAssertEqual(LedgerSurfaceDensity.reminderRow.rowDensity, .standard)
        XCTAssertLessThanOrEqual(reminderLines.count, 3)
        XCTAssertEqual(LedgerSurfaceDensity.detailSummary.rowDensity, .detail)
        XCTAssertNotNil(detail.primaryOperationalSummary)
        XCTAssertTrue(detail.timelineEntryPoints.count <= 3)
    }

    private func searchResult() -> LocalSearchResult {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let record = LocalSearchRecord(
            id: recordID,
            kind: .event,
            title: "Changed furnace filter",
            subtitle: "Maintenance",
            body: "Filter size is 16x20.",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: fixedTestNow,
            updatedAt: nil,
            linkedThingId: UUID(),
            linkedThingName: "Furnace",
            isActiveRule: false,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: nil,
            navigationTarget: .eventDetail(recordID)
        )
        return LocalSearchResult(record: record, matchedFields: [.title], score: 1)
    }

    private func thingWithContinuity() -> Thing {
        let thing = Thing(name: "Furnace", category: .maintenance)
        let event = LedgerEvent(
            title: "Changed filter",
            occurredAt: fixedTestNow,
            rawText: "Changed filter.",
            eventType: .maintenance,
            thing: thing
        )
        let rule = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            rawText: "Replace filter in two months.",
            startsAt: fixedTestNow.addingTimeInterval(60 * day),
            createdAt: fixedTestNow,
            thing: thing
        )
        let note = LedgerNote(
            text: "Filter size is 16x20.",
            createdAt: fixedTestNow.addingTimeInterval(-day),
            updatedAt: fixedTestNow.addingTimeInterval(-day),
            linkedThings: [thing]
        )
        thing.events = [event]
        thing.rules = [rule]
        thing.notes = [note]
        return thing
    }

    private let day: TimeInterval = 86_400
    private let testCalendar = Calendar(identifier: .gregorian)
}
