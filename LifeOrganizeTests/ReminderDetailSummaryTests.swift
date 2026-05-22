import XCTest
@testable import LifeOrganize

final class ReminderDetailSummaryTests: XCTestCase {
    func testDateBasedSummaryPromotesDueDateContextAndActions() {
        let now = fixedTestNow
        let thing = Thing(name: "Honda Civic")
        let sourceMessage = ChatMessage(role: .user, text: "Renew registration today.", createdAt: now)
        let rule = LedgerRule(
            title: "Renew registration",
            reason: "Keep the car legal",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now,
            createdAt: now,
            thing: thing,
            sourceMessage: sourceMessage
        )

        let summary = ReminderDetailSummaryService().presentation(for: rule, at: now)

        XCTAssertEqual(summary.title, "Renew registration")
        XCTAssertEqual(summary.stateSentence, "Due today. Set for \(RuleStatusService.date(now)).")
        XCTAssertEqual(summary.scheduleSentence, "Planned for \(RuleStatusService.date(now)).")
        XCTAssertEqual(summary.contextSentence, "Connected to Honda Civic.")
        XCTAssertEqual(summary.reasonSentence, "Keep the car legal.")
        XCTAssertEqual(summary.sourceSentence, "Added from your timeline.")
        XCTAssertEqual(summary.actionSentence, "Available next actions: Move Due Date and Mark Done.")
        XCTAssertEqual(summary.actionTitles, ["Move Due Date", "Mark Done"])
    }

    func testTimeWindowSummaryIncludesRangeAndReviewActionsWhenExpired() {
        let now = fixedTestNow
        let start = now.addingTimeInterval(-10 * day)
        let end = now.addingTimeInterval(-day)
        let rule = LedgerRule(
            title: "Use trial credit",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: start,
            expiresAt: end,
            createdAt: start
        )

        let summary = ReminderDetailSummaryService().presentation(for: rule, at: now)

        XCTAssertEqual(summary.stateSentence, "Ended \(RuleStatusService.date(end)). Review whether to extend or let it rest.")
        XCTAssertEqual(
            summary.scheduleSentence,
            "Planned from \(RuleStatusService.date(start)) through \(RuleStatusService.date(end))."
        )
        XCTAssertEqual(summary.contextSentence, "Not connected to a thing yet.")
        XCTAssertEqual(summary.actionSentence, "Available next actions: Extend Window and Let Window Rest.")
        XCTAssertFalse(summary.actionTitles.contains("Mark Done"))
    }

    func testOngoingSummaryUsesNoPlannedEndFallbacks() {
        let now = fixedTestNow
        let start = now.addingTimeInterval(-4 * day)
        let rule = LedgerRule(
            title: "Keep passport ready",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: start,
            createdAt: start
        )

        let summary = ReminderDetailSummaryService().presentation(for: rule, at: now)

        XCTAssertEqual(summary.stateSentence, "Carried forward. No planned end.")
        XCTAssertEqual(summary.scheduleSentence, "Carried from \(RuleStatusService.date(start)) with no planned end.")
        XCTAssertEqual(summary.reasonSentence, "No reason was saved with this reminder.")
        XCTAssertTrue(summary.sourceSentence.hasPrefix("Added manually on "))
        XCTAssertEqual(summary.actionSentence, "Available next actions: Stop Carrying.")
    }

    func testRecurringAndScheduledSummariesStayHumanReadable() {
        let now = fixedTestNow
        let start = now.addingTimeInterval(5 * day)
        let rule = LedgerRule(
            title: "Check furnace filter monthly",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Check furnace filter every month",
            startsAt: start,
            createdAt: now
        )

        let summary = ReminderDetailSummaryService().presentation(for: rule, at: now)

        XCTAssertEqual(
            summary.stateSentence,
            "Recurring intention starts \(RuleStatusService.date(start)). Use the original wording as the repeat cue."
        )
        XCTAssertEqual(summary.scheduleSentence, "Pattern starts \(RuleStatusService.date(start)) with no planned end.")
        XCTAssertEqual(summary.actionSentence, "Available next actions: Pause Pattern.")
    }

    func testInactiveSummarySuppressesUnavailableActions() {
        let now = fixedTestNow
        let stoppedAt = now.addingTimeInterval(-day)
        let rule = LedgerRule(
            title: "Check weekly",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Check every week",
            startsAt: now.addingTimeInterval(-8 * day),
            createdAt: now.addingTimeInterval(-8 * day),
            manuallyDeactivatedAt: stoppedAt
        )

        let summary = ReminderDetailSummaryService().presentation(for: rule, at: now)

        XCTAssertEqual(summary.stateSentence, "Recurring intention paused. Original wording remains saved.")
        XCTAssertNil(summary.actionSentence)
        XCTAssertEqual(summary.actionTitles, [])
    }
}

private let day: TimeInterval = 86_400
