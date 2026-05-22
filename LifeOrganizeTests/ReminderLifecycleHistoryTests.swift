import SwiftData
import XCTest
@testable import LifeOrganize

final class ReminderLifecycleHistoryTests: XCTestCase {
    @MainActor
    func testLifecycleActionCopyStaysDistinctWhileUsingSharedHistoryState() throws {
        let now = try Self.date(2026, 5, 21)
        let future = try Self.date(2026, 6, 1)
        let past = try Self.date(2026, 5, 1)
        let dateReminder = LedgerRule(title: "Pay rent", ruleType: .reminder, continuityBehavior: .dateBasedReminder, startsAt: now)
        let ongoing = LedgerRule(title: "Keep registration handy", ruleType: .reminder, continuityBehavior: .ongoing, startsAt: past)
        let window = LedgerRule(title: "Use trial", ruleType: .reminder, continuityBehavior: .timeLimitedWindow, startsAt: past, expiresAt: future)
        let scheduledWindow = LedgerRule(title: "Use pass", ruleType: .reminder, continuityBehavior: .timeLimitedWindow, startsAt: future, expiresAt: future.addingTimeInterval(86_400))
        let recurring = LedgerRule(title: "Check weekly", ruleType: .reminder, continuityBehavior: .recurringText, rawText: "Check every week", startsAt: past)
        let expired = LedgerRule(title: "Review rebate", ruleType: .reminder, continuityBehavior: .dateBasedReminder, startsAt: past, expiresAt: past)

        let actions = [
            ReminderDetailActionPolicy.lifecycleAction(for: dateReminder, status: .active),
            ReminderDetailActionPolicy.lifecycleAction(for: ongoing, status: .active),
            ReminderDetailActionPolicy.lifecycleAction(for: window, status: .active),
            ReminderDetailActionPolicy.lifecycleAction(for: scheduledWindow, status: .scheduled),
            ReminderDetailActionPolicy.lifecycleAction(for: recurring, status: .active),
            ReminderDetailActionPolicy.lifecycleAction(for: expired, status: .expired)
        ].compactMap { $0 }

        XCTAssertEqual(actions.map(\.title), ["Mark Done", "Stop Carrying", "Close Window", "Cancel Window", "Pause Pattern", "Let It Rest"])
        XCTAssertGreaterThan(Set(actions.map(\.dialogTitle)).count, 4)

        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Rent", updatedAt: past)
        let rule = LedgerRule(title: "Pay rent", ruleType: .reminder, continuityBehavior: .dateBasedReminder, startsAt: past, thing: thing)
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })
        context.insert(thing)
        context.insert(rule)

        ReminderRuleLifecycleMutation.deactivate(rule, at: now, maintenance: service)

        XCTAssertEqual(rule.manuallyDeactivatedAt, now)
        XCTAssertEqual(rule.updatedAt, now)
        XCTAssertEqual(rule.lifecycleState, .deactivated)
        XCTAssertFalse(rule.isActive)
        XCTAssertEqual(thing.updatedAt, now)
    }

    @MainActor
    func testMoveDueDateReopensInactiveRemindersForPastTodayAndFutureDates() throws {
        let context = makeInMemoryModelContext()
        let now = try Self.date(2026, 5, 21)
        let oldDate = try Self.date(2026, 5, 1)
        let cases = [
            (selected: try Self.date(2026, 5, 20), status: RuleStatus.active, isActive: true),
            (selected: now, status: RuleStatus.active, isActive: true),
            (selected: try Self.date(2026, 5, 30), status: RuleStatus.scheduled, isActive: false)
        ]

        for item in cases {
            let thing = Thing(name: "Car", updatedAt: oldDate)
            let rule = LedgerRule(
                title: "Renew registration",
                ruleType: .reminder,
                continuityBehavior: .dateBasedReminder,
                startsAt: oldDate,
                expiresAt: now,
                updatedAt: oldDate,
                manuallyDeactivatedAt: oldDate,
                thing: thing
            )
            let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })
            context.insert(thing)
            context.insert(rule)

            try ReminderRuleLifecycleMutation.moveDueDate(rule, to: item.selected, at: now, maintenance: service, calendar: Self.calendar)

            XCTAssertEqual(rule.startsAt, DateFormatting.normalizedDateOnly(item.selected, calendar: Self.calendar))
            XCTAssertNil(rule.expiresAt)
            XCTAssertNil(rule.manuallyDeactivatedAt)
            XCTAssertEqual(rule.lifecycleState, .open)
            XCTAssertEqual(rule.updatedAt, now)
            XCTAssertEqual(RuleStatusService().status(for: rule, at: now), item.status)
            XCTAssertEqual(rule.isActive, item.isActive)
            XCTAssertEqual(thing.updatedAt, now)
        }
    }

    @MainActor
    func testSetEndDateClearsManualDeactivationAndPreservesStartDate() throws {
        let context = makeInMemoryModelContext()
        let now = try Self.date(2026, 5, 21)
        let start = try Self.date(2026, 5, 1)
        let previousEnd = try Self.date(2026, 5, 15)
        let newEnd = try Self.date(2026, 6, 1)
        let thing = Thing(name: "Trial", updatedAt: start)
        let rule = LedgerRule(
            title: "Use trial credit",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: start,
            expiresAt: previousEnd,
            updatedAt: previousEnd,
            manuallyDeactivatedAt: previousEnd,
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })
        context.insert(thing)
        context.insert(rule)

        try ReminderRuleLifecycleMutation.setEndDate(rule, to: newEnd, at: now, maintenance: service, calendar: Self.calendar)

        XCTAssertEqual(rule.startsAt, start)
        XCTAssertEqual(rule.expiresAt, DateFormatting.normalizedDateOnly(newEnd, calendar: Self.calendar))
        XCTAssertNil(rule.manuallyDeactivatedAt)
        XCTAssertEqual(rule.lifecycleState, .open)
        XCTAssertEqual(rule.updatedAt, now)
        XCTAssertTrue(rule.isActive)
        XCTAssertEqual(thing.updatedAt, now)
    }

    func testSearchFindsReminderHistoryByOriginalAndCompletionDates() throws {
        let due = try Self.date(2026, 4, 1)
        let completed = try Self.date(2026, 4, 2)
        let rule = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: due,
            updatedAt: completed,
            manuallyDeactivatedAt: completed
        )
        let search = SearchService()
        let records = [search.record(for: rule)]

        XCTAssertTrue(search.search("2026-04-01", in: records).contains { $0.stableID == rule.id })
        XCTAssertTrue(search.search("April 2, 2026", in: records).contains { $0.stableID == rule.id })
        XCTAssertTrue(search.search("completed", in: records).contains { $0.stableID == rule.id })
    }

    func testTimelineSlicesCanLocateOriginalDueAndCompletionDates() throws {
        let due = try Self.date(2026, 4, 1)
        let completed = try Self.date(2026, 4, 2)
        let rule = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: due,
            manuallyDeactivatedAt: completed
        )
        let projection = TimelineSliceProjection(calendar: Self.calendar, now: try Self.date(2026, 5, 1))
        let dueRows = projection.rows(query: TimelineSliceQuery(dateRange: Self.dayRange(containing: due)), reminders: [rule])
        let completionRows = projection.rows(query: TimelineSliceQuery(dateRange: Self.dayRange(containing: completed)), reminders: [rule])

        XCTAssertTrue(dueRows.contains { $0.sourceID == rule.id && $0.dateKind == .dueStart })
        XCTAssertFalse(dueRows.contains { $0.dateKind == .completedDeactivated })
        XCTAssertTrue(completionRows.contains { $0.sourceID == rule.id && $0.dateKind == .completedDeactivated })
    }

    func testThingReminderHistoryRowsIncludeOriginalAndCompletionDates() throws {
        let due = try Self.date(2026, 4, 1)
        let completed = try Self.date(2026, 4, 2)
        let rule = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            startsAt: due,
            manuallyDeactivatedAt: completed
        )
        let presentation = ReminderContinuityPresentationService().presentation(for: rule, at: try Self.date(2026, 5, 1))
        let rendered = LedgerReminderRowLines.lines(for: presentation, rule: rule)
            .map(\.text)
            .joined(separator: " ")

        XCTAssertTrue(rendered.contains("Original due date"))
        XCTAssertTrue(rendered.contains("Completed or stopped"))
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private static func dayRange(containing date: Date) -> TimelineSliceDateRange {
        let start = calendar.startOfDay(for: date)
        return TimelineSliceDateRange(start: start, endExclusive: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
}
