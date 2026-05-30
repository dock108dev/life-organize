import XCTest
@testable import LifeOrganize

final class LedgerFeedRowContentTests: XCTestCase {
    func testMessageRowsUseTimestampSourceAndPrimaryText() throws {
        let createdAt = try Self.date(2026, 5, 21, 8, 45)
        let message = ChatMessage(
            role: .user,
            text: "Changed furnace filter.",
            createdAt: createdAt,
            extractionStatus: .pending
        )

        let content = LedgerFeedRowContent(item: .message(message), timeFormatter: Self.timeFormatter)

        XCTAssertEqual(TestTextNormalization.normalizedTimeText(content.timestampText), "8:45 AM")
        XCTAssertEqual(content.source, .user)
        XCTAssertEqual(content.sourceLabel, "You")
        XCTAssertEqual(content.sourceBadge.role, .source)
        XCTAssertEqual(content.primaryText, "Changed furnace filter.")
        XCTAssertEqual(content.secondaryText, "Saving")
        XCTAssertEqual(content.secondaryTone, .muted)
        XCTAssertEqual(content.secondaryBadge?.semantic, .statusSaving)
        XCTAssertEqual(content.primaryBadge()?.semantic, .statusSaving)
        XCTAssertNil(content.detailText)
    }

    func testMessageStatusTextCoversLocalRetryPartialAndFailureStates() {
        let expectedStatuses: [(ExtractionStatus, String?, LedgerFeedRowContent.SecondaryTone, LedgerBadgeSemantic)] = [
            (.pendingToken, "Saved", .muted, .statusSavedLocal),
            (.pendingRetry, "Retry later", .info, .statusRetryPending),
            (.partiallySucceeded, "Review", .attention, .actionReview),
            (.failed, "Needs review", .danger, .statusFailed),
            (.failedNeedsReview, "Review", .attention, .actionReview),
            (.needsReview, "Review", .attention, .actionReview),
            (.succeeded, nil, .neutral, .sourceUser)
        ]

        for (status, expectedText, expectedTone, expectedPrimaryBadge) in expectedStatuses {
            let message = ChatMessage(role: .user, text: "Timeline entry", extractionStatus: status)
            let content = LedgerFeedRowContent(item: .message(message), timeFormatter: Self.timeFormatter)

            XCTAssertEqual(content.secondaryText, expectedText, "Unexpected text for \(status.rawValue)")
            XCTAssertEqual(content.secondaryTone, expectedTone, "Unexpected tone for \(status.rawValue)")
            XCTAssertEqual(
                content.primaryBadge()?.semantic,
                expectedPrimaryBadge,
                "Unexpected primary badge for \(status.rawValue)"
            )
        }
    }

    func testReviewBadgeRemainsPrimaryOverCategoryOrSourceBadges() {
        let event = LedgerEvent(title: "Changed filter", occurredAt: fixedTestNow, rawText: "Changed filter.")
        let content = LedgerFeedRowContent(item: .event(event), timeFormatter: Self.timeFormatter)
        let reviewBadge = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 85)

        XCTAssertEqual(content.primaryBadge()?.semantic, .categoryEvent)
        XCTAssertEqual(content.primaryBadge(reviewBadge: reviewBadge)?.semantic, .actionReview)
        XCTAssertEqual(content.primaryBadge(reviewBadge: reviewBadge)?.tone, .attention)
    }

    func testAppAndSystemMessagesUseSharedRowLanguage() {
        let assistant = LedgerFeedRowContent(
            item: .message(ChatMessage(role: .assistant, text: "Event saved:\nOil change on May 21, 2026.", extractionStatus: .notRequired)),
            timeFormatter: Self.timeFormatter
        )
        let recall = LedgerFeedRowContent(
            item: .message(ChatMessage(role: .assistant, text: "Last logged:\nOil change on May 21, 2026.", extractionStatus: .notRequired)),
            timeFormatter: Self.timeFormatter
        )
        let upcoming = LedgerFeedRowContent(
            item: .message(ChatMessage(role: .assistant, text: "Coming Up:\nRenew registration.", extractionStatus: .notRequired)),
            timeFormatter: Self.timeFormatter
        )
        let review = LedgerFeedRowContent(
            item: .message(ChatMessage(role: .assistant, text: "Review:\nOne item needs a decision.", extractionStatus: .notRequired)),
            timeFormatter: Self.timeFormatter
        )
        let system = LedgerFeedRowContent(
            item: .message(ChatMessage(role: .system, text: "Ready.", extractionStatus: .notRequired)),
            timeFormatter: Self.timeFormatter
        )

        XCTAssertEqual(assistant.source, .status)
        XCTAssertEqual(assistant.sourceLabel, "Saved")
        XCTAssertEqual(assistant.sourceBadge.semantic, .statusSaved)
        XCTAssertEqual(assistant.primaryText, "Event saved:\nOil change on May 21, 2026.")
        XCTAssertEqual(recall.sourceLabel, "Found")
        XCTAssertEqual(upcoming.sourceBadge.semantic, .collectionUpcoming)
        XCTAssertEqual(upcoming.sourceBadge.tone, .info)
        XCTAssertEqual(review.sourceBadge.semantic, .collectionReview)
        XCTAssertEqual(review.sourceBadge.tone, .muted)
        XCTAssertNil(assistant.secondaryText)
        XCTAssertEqual(system.sourceLabel, "App")
        XCTAssertEqual(system.primaryText, "Ready.")
        XCTAssertNil(system.secondaryText)
    }

    func testMessageRowsHideExtractionDebugInternals() {
        let message = ChatMessage(
            role: .user,
            text: "Changed oil at 40k miles.",
            rawLLMResponse: #"{"schemaVersion":"1.0","normalizedJSONText":"debug"}"#,
            extractionStatus: .failedNeedsReview,
            extractionError: "schema_validation_failed",
            extractionErrorCode: .invalidJSON,
            extractionAttemptCount: 3
        )

        let content = LedgerFeedRowContent(item: .message(message), timeFormatter: Self.timeFormatter)
        let visibleText = Self.visibleText(content)

        XCTAssertEqual(content.primaryText, "Changed oil at 40k miles.")
        XCTAssertEqual(content.secondaryText, "Review")
        XCTAssertFalse(visibleText.contains("deterministic-extractor"))
        XCTAssertFalse(visibleText.contains("requestJSON"))
        XCTAssertFalse(visibleText.contains("normalizedJSONText"))
        XCTAssertFalse(visibleText.contains("schemaVersion"))
        XCTAssertFalse(visibleText.contains("invalid_json"))
        XCTAssertFalse(visibleText.contains("schema_validation_failed"))
    }

    func testLedgerRecordRowsUseCleanNotesForSecondaryDetails() throws {
        let createdAt = try Self.date(2026, 5, 21, 9, 30)
        let thing = Thing(name: "Furnace")
        let event = LedgerEvent(
            title: "Changed filter",
            occurredAt: createdAt,
            rawText: "Changed filter and vacuumed cabinet.",
            note: "Vacuumed cabinet after replacing the filter.",
            eventType: .maintenance,
            thing: thing
        )

        let content = LedgerFeedRowContent(item: .event(event), timeFormatter: Self.timeFormatter)

        XCTAssertEqual(TestTextNormalization.normalizedTimeText(content.timestampText), "9:30 AM")
        XCTAssertEqual(content.sourceLabel, "Event")
        XCTAssertEqual(content.primaryText, "Changed filter")
        XCTAssertEqual(content.secondaryText, "Maintenance")
        XCTAssertEqual(content.detailText, "Vacuumed cabinet after replacing the filter.")
        XCTAssertEqual(content.linkedThingText, "Furnace")
        XCTAssertEqual(LedgerFeedTimelineLayout.rowChrome.rowVerticalPadding, LedgerFeedTimelineLayout.rowVerticalPadding)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowChrome.markerSize, LedgerFeedTimelineLayout.markerSize)
    }

    func testNoteRowsPromoteLinkedThingsToSharedMetadata() throws {
        let createdAt = try Self.date(2026, 5, 21, 9, 30)
        let note = LedgerNote(
            text: "Gate code changed.\nUse the side entrance.",
            createdAt: createdAt,
            linkedThings: [Thing(name: "Garage")]
        )

        let content = LedgerFeedRowContent(item: .note(note), timeFormatter: Self.timeFormatter)

        XCTAssertEqual(content.primaryText, "Gate code changed.")
        XCTAssertEqual(content.sourceBadge.semantic, .categoryNote)
        XCTAssertEqual(content.sourceBadge.tone, .note)
        XCTAssertNil(content.secondaryText)
        XCTAssertEqual(content.detailText, note.text)
        XCTAssertEqual(content.linkedThingText, "Garage")
    }

    func testLedgerRecordRowsDoNotFallbackToRawSourceText() throws {
        let createdAt = try Self.date(2026, 5, 21, 9, 30)
        let event = LedgerEvent(
            title: "Changed filter",
            occurredAt: createdAt,
            rawText: "Changed filter and vacuumed cabinet.",
            eventType: .maintenance
        )
        let reminder = LedgerRule(
            title: "Replace filter",
            rawText: "Replace filter in two months.",
            startsAt: createdAt,
            createdAt: createdAt
        )

        let eventContent = LedgerFeedRowContent(item: .event(event), timeFormatter: Self.timeFormatter)
        let reminderContent = LedgerFeedRowContent(item: .reminder(reminder), timeFormatter: Self.timeFormatter)

        XCTAssertNil(eventContent.detailText)
        XCTAssertNil(reminderContent.detailText)
    }

    func testReminderRowsUseDueDateAndCaptureCopy() throws {
        let createdAt = try Self.date(2026, 5, 18, 9, 30)
        let dueAt = try Self.date(2026, 7, 21, 12, 0)
        let reminder = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            rawText: "Replace filter in two months.",
            startsAt: dueAt,
            createdAt: createdAt
        )

        let content = LedgerFeedRowContent(
            item: .reminder(reminder),
            timeFormatter: Self.timeFormatter,
            dateFormatter: Self.dateFormatter
        )

        XCTAssertEqual(TestTextNormalization.normalizedTimeText(content.timestampText), "12:00 PM")
        XCTAssertEqual(content.secondaryText, "Due July 21, 2026")
        XCTAssertEqual(content.detailText, "Captured May 18, 2026")
    }

    func testLedgerSourcePresentationUsesProductLanguageOnly() throws {
        let manualDate = try Self.date(2026, 5, 21, 9, 30)
        let fromLog = LedgerSourcePresentation(hasSourceMessage: true, manualDate: manualDate)
        let importedFromLog = LedgerSourcePresentation(
            hasSourceMessage: false,
            manualDate: manualDate,
            extractedIDs: [UUID()]
        )
        let manual = LedgerSourcePresentation(hasSourceMessage: false, manualDate: manualDate)

        XCTAssertEqual(fromLog.title, "Added from your timeline")
        XCTAssertNil(fromLog.detail)
        XCTAssertEqual(importedFromLog.title, "Added from your timeline")
        XCTAssertNil(importedFromLog.detail)
        XCTAssertEqual(manual.title, "Added manually")
        XCTAssertNotNil(manual.detail)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private static func visibleText(_ content: LedgerFeedRowContent) -> String {
        [
            content.timestampText,
            content.sourceLabel,
            content.primaryText,
            content.secondaryText,
            content.detailText,
            content.linkedThingText
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }
}
