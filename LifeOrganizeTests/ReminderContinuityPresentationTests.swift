import XCTest
@testable import LifeOrganize

final class ReminderContinuityPresentationTests: XCTestCase {
    func testContinuityPresentationMapsInternalStatusesToUserLanes() {
        let now = fixedTestNow
        let service = ReminderContinuityPresentationService()
        let activeDue = LedgerRule(
            title: "Pay registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now,
            createdAt: now
        )
        let scheduledDue = LedgerRule(
            title: "Renew lease",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(3 * day),
            createdAt: now
        )
        let endedWindow = LedgerRule(
            title: "Use trial credit",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: now.addingTimeInterval(-10 * day),
            expiresAt: now.addingTimeInterval(-day),
            createdAt: now.addingTimeInterval(-10 * day)
        )
        let paused = LedgerRule(
            title: "Check weekly",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Check every week",
            startsAt: now.addingTimeInterval(-5 * day),
            createdAt: now.addingTimeInterval(-5 * day),
            manuallyDeactivatedAt: now
        )

        XCTAssertEqual(service.presentation(for: activeDue, at: now).lane, .now)
        XCTAssertEqual(service.presentation(for: activeDue, at: now).badge, "Now")
        XCTAssertEqual(service.presentation(for: activeDue, at: now).statusBadge.semantic, .statusNow)
        XCTAssertEqual(service.presentation(for: activeDue, at: now).typeBadge.semantic, .reminderDueDate)
        XCTAssertEqual(service.presentation(for: activeDue, at: now).primaryLine, "Due today")
        XCTAssertEqual(service.presentation(for: scheduledDue, at: now).lane, .comingUp)
        XCTAssertEqual(service.presentation(for: endedWindow, at: now).lane, .review)
        XCTAssertEqual(service.presentation(for: endedWindow, at: now).badge, "Review")
        XCTAssertEqual(service.presentation(for: endedWindow, at: now).badges.map(\.label), ["Review", "Window"])
        XCTAssertEqual(service.presentation(for: paused, at: now).lane, .paused)
        XCTAssertEqual(service.presentation(for: paused, at: now).badge, "Paused")
    }

    func testContinuityPresentationSeparatesStatusAndReminderTypeBadges() {
        let now = fixedTestNow
        let service = ReminderContinuityPresentationService()
        let scenarios: [(LedgerContinuityBehavior, TimeInterval, TimeInterval?, LedgerBadgeSemantic, String)] = [
            (.dateBasedReminder, 0, nil, .reminderDueDate, "Now"),
            (.timeLimitedWindow, 2 * day, 4 * day, .reminderWindow, "Upcoming"),
            (.ongoing, -4 * day, -day, .reminderOngoing, "Review"),
            (.recurringText, 3 * day, nil, .reminderRepeating, "Upcoming"),
        ]

        for (behavior, startOffset, endOffset, typeSemantic, statusLabel) in scenarios {
            let rule = LedgerRule(
                title: "Reminder",
                ruleType: .reminder,
                continuityBehavior: behavior,
                rawText: "Check this",
                startsAt: now.addingTimeInterval(startOffset),
                expiresAt: endOffset.map { now.addingTimeInterval($0) },
                createdAt: now.addingTimeInterval(-day)
            )
            let presentation = service.presentation(for: rule, at: now)

            XCTAssertEqual(presentation.statusBadge.label, statusLabel)
            XCTAssertEqual(presentation.typeBadge.semantic, typeSemantic)
            XCTAssertEqual(presentation.badges.count, 2)
        }
    }

    func testDateBasedReminderCopySeparatesDueTodayFromOverdueCarryForward() {
        let now = fixedTestNow
        let service = ReminderContinuityPresentationService()
        let dueToday = LedgerRule(
            title: "Pay registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now,
            createdAt: now
        )
        let overdue = LedgerRule(
            title: "Pay insurance",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(-2 * day),
            createdAt: now.addingTimeInterval(-2 * day)
        )

        let dueTodayPresentation = service.presentation(for: dueToday, at: now)
        let overduePresentation = service.presentation(for: overdue, at: now)

        XCTAssertEqual(dueTodayPresentation.lane, .now)
        XCTAssertEqual(dueTodayPresentation.primaryLine, "Due today")
        XCTAssertEqual(dueTodayPresentation.dateLine, "Set for \(RuleStatusService.date(now))")
        XCTAssertFalse(dueTodayPresentation.primaryLine.localizedCaseInsensitiveContains("carried forward"))
        XCTAssertFalse((dueTodayPresentation.dateLine ?? "").localizedCaseInsensitiveContains("carried forward"))
        XCTAssertEqual(overduePresentation.lane, .now)
        XCTAssertEqual(overduePresentation.primaryLine, "Due since \(RuleStatusService.date(overdue.startsAt))")
        XCTAssertEqual(overduePresentation.dateLine, "Carried forward until completed or rescheduled")
    }

    func testReminderRowLinesExposeContinuityFieldsUsedByListRows() {
        let now = fixedTestNow
        let rule = LedgerRule(
            title: "Pay insurance",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(-2 * day),
            createdAt: now.addingTimeInterval(-2 * day)
        )
        let presentation = ReminderContinuityPresentationService().presentation(for: rule, at: now)

        let rowLines = LedgerReminderRowLines.lines(for: presentation, rule: rule, reason: "Keep policy active.")

        XCTAssertEqual(rowLines.map(\.text), [
            "Due since \(RuleStatusService.date(rule.startsAt))",
            "Carried forward until completed or rescheduled",
            "Keep policy active.",
        ])
    }

    func testActiveOngoingReminderKeepsCarryForwardAsPrimaryConcept() {
        let now = fixedTestNow
        let ongoing = LedgerRule(
            title: "Keep passport ready",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: now.addingTimeInterval(-8 * day),
            createdAt: now.addingTimeInterval(-8 * day)
        )

        let presentation = ReminderContinuityPresentationService().presentation(for: ongoing, at: now)

        XCTAssertEqual(presentation.lane, .now)
        XCTAssertEqual(presentation.primaryLine, "Carried forward")
        XCTAssertEqual(presentation.dateLine, "No planned end")
        XCTAssertEqual(presentation.typeBadge.semantic, .reminderOngoing)
    }

    func testScheduledPausedAndReviewLaneReminderCopyStaysDistinct() {
        let now = fixedTestNow
        let service = ReminderContinuityPresentationService()
        let scheduled = LedgerRule(
            title: "Renew lease",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(3 * day),
            createdAt: now
        )
        let paused = LedgerRule(
            title: "Check weekly",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: now.addingTimeInterval(-5 * day),
            createdAt: now.addingTimeInterval(-5 * day),
            manuallyDeactivatedAt: now
        )
        let review = LedgerRule(
            title: "Use trial credit",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: now.addingTimeInterval(-10 * day),
            expiresAt: now.addingTimeInterval(-day),
            createdAt: now.addingTimeInterval(-10 * day)
        )

        let scheduledPresentation = service.presentation(for: scheduled, at: now)
        let pausedPresentation = service.presentation(for: paused, at: now)
        let reviewPresentation = service.presentation(for: review, at: now)

        XCTAssertEqual(scheduledPresentation.lane, .comingUp)
        XCTAssertEqual(scheduledPresentation.primaryLine, "Due \(RuleStatusService.date(scheduled.startsAt))")
        XCTAssertEqual(scheduledPresentation.dateLine, "Will move to Now on that date")
        XCTAssertEqual(pausedPresentation.lane, .paused)
        XCTAssertEqual(pausedPresentation.statusBadge.semantic, .statusPaused)
        XCTAssertEqual(pausedPresentation.primaryLine, "No longer carried forward")
        XCTAssertEqual(reviewPresentation.lane, .review)
        XCTAssertEqual(reviewPresentation.statusBadge.semantic, .actionReview)
        XCTAssertEqual(reviewPresentation.statusBadge.tone, .attention)
        XCTAssertEqual(reviewPresentation.primaryLine, "Ended \(RuleStatusService.date(review.expiresAt!))")
        XCTAssertEqual(reviewPresentation.dateLine, "Review whether to extend or let it rest")
    }

    func testContinuityLanesUseSectionSpecificSorting() {
        let now = fixedTestNow
        let service = ReminderContinuityPresentationService()
        let ongoing = LedgerRule(
            title: "Keep passport ready",
            ruleType: .reminder,
            continuityBehavior: .ongoing,
            startsAt: now.addingTimeInterval(-8 * day),
            updatedAt: now.addingTimeInterval(-8 * day)
        )
        let window = LedgerRule(
            title: "Use parking pass",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: now.addingTimeInterval(-2 * day),
            expiresAt: now.addingTimeInterval(2 * day),
            updatedAt: now.addingTimeInterval(-2 * day)
        )
        let due = LedgerRule(
            title: "Pay insurance",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(-day),
            updatedAt: now.addingTimeInterval(-day)
        )
        let later = LedgerRule(
            title: "Later",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(7 * day),
            updatedAt: now
        )
        let sooner = LedgerRule(
            title: "Sooner",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: now.addingTimeInterval(3 * day),
            updatedAt: now.addingTimeInterval(-day)
        )

        XCTAssertEqual(service.rules([ongoing, window, due], in: .now, at: now).map(\.title), [
            "Pay insurance",
            "Use parking pass",
            "Keep passport ready",
        ])
        XCTAssertEqual(service.rules([later, sooner], in: .comingUp, at: now).map(\.title), [
            "Sooner",
            "Later",
        ])
    }
}

private let day: TimeInterval = 86_400
