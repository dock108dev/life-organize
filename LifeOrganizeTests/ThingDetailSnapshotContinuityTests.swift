import XCTest
@testable import LifeOrganize

final class ThingDetailSnapshotContinuityTests: XCTestCase {
    @MainActor
    func testVehicleServiceSummariesInferMileageAndNextService() {
        let now = fixedTestNow
        let thing = Thing(name: "Car", category: .maintenance)
        let olderService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now.addingTimeInterval(-90 * day),
            rawText: "Changed oil at 46,000 mi.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 46_000, unit: "mi")
            ],
            thing: thing
        )
        let latestService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil at 52,000 mi.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 52_000, unit: "mi"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Northline Auto")
            ],
            thing: thing
        )
        thing.events = [olderService, latestService]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.primaryOperationalSummary?.label, "Latest service")
        XCTAssertEqual(snapshot.primaryOperationalSummary?.value, "Changed oil")
        XCTAssertTrue(snapshot.primaryOperationalSummary?.detail?.contains("Mileage: 52,000 mi") == true)
        XCTAssertEqual(snapshot.continuitySummary?.label, "Service continuity")
        XCTAssertEqual(snapshot.continuitySummary?.value, "About every 6,000 mi")
        XCTAssertTrue(snapshot.continuitySummary?.detail?.contains("Next mileage to review: 58,000 mi") == true)
        XCTAssertTrue(snapshot.continuitySummary?.detail?.contains("around") == true)
    }

    @MainActor
    func testReplacementHistoryShowsIntervalAndSuppressesExpectedCheckWhenReminderExists() {
        let now = fixedTestNow
        let thing = Thing(name: "Home Air Filters")
        let olderReplacement = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now.addingTimeInterval(-90 * day),
            rawText: "Replaced HVAC filters.",
            eventType: .replacement,
            thing: thing
        )
        let latestReplacement = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now.addingTimeInterval(-30 * day),
            rawText: "Replaced HVAC filters again.",
            eventType: .replacement,
            thing: thing
        )
        let reminder = LedgerRule(
            title: "Replace filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace filters next month.",
            startsAt: now.addingTimeInterval(30 * day),
            createdAt: now,
            updatedAt: now,
            thing: thing
        )
        thing.events = [olderReplacement, latestReplacement]
        thing.rules = [reminder]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.primaryOperationalSummary?.label, "Last replacement")
        XCTAssertEqual(snapshot.continuitySummary?.label, "Replacement rhythm")
        XCTAssertEqual(snapshot.continuitySummary?.value, "About every 60 days")
        XCTAssertEqual(snapshot.continuitySummary?.detail, "Reminder already saved: Replace filters")
        XCTAssertFalse(snapshot.continuitySummary?.detail?.contains("Expected next check") == true)
    }

    @MainActor
    func testPurchaseConsumableHistoryShowsExpectedNextCheckWithoutReminder() {
        let now = fixedTestNow
        let thing = Thing(name: "Dog Food")
        let olderPurchase = LedgerEvent(
            title: "Bought dog food",
            occurredAt: now.addingTimeInterval(-56 * day),
            rawText: "Bought dog food.",
            eventType: .purchase,
            thing: thing
        )
        let latestPurchase = LedgerEvent(
            title: "Bought dog food",
            occurredAt: now.addingTimeInterval(-28 * day),
            rawText: "Bought dog food again.",
            eventType: .purchase,
            thing: thing
        )
        thing.events = [olderPurchase, latestPurchase]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.primaryOperationalSummary?.label, "Last purchase")
        XCTAssertEqual(snapshot.continuitySummary?.label, "Purchase rhythm")
        XCTAssertEqual(snapshot.continuitySummary?.value, "About every 28 days")
        XCTAssertTrue(snapshot.continuitySummary?.detail?.contains("Next check to review") == true)
    }

    @MainActor
    func testCompletedRemindersRemainAvailableAsReminderHistory() {
        let now = fixedTestNow
        let thing = Thing(name: "License Renewal")
        let completed = LedgerRule(
            title: "Renew license",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Renew license.",
            startsAt: now.addingTimeInterval(-10 * day),
            createdAt: now.addingTimeInterval(-20 * day),
            updatedAt: now.addingTimeInterval(-day),
            manuallyDeactivatedAt: now.addingTimeInterval(-day),
            thing: thing
        )
        thing.rules = [completed]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.status, .quiet)
        XCTAssertTrue(snapshot.upcomingReminders.isEmpty)
        XCTAssertEqual(snapshot.inactiveReminders.map(\.title), ["Renew license"])
        XCTAssertEqual(snapshot.reminderHistorySummary?.label, "Reminder history")
        XCTAssertEqual(snapshot.reminderHistorySummary?.value, "1 completed reminder")
        XCTAssertTrue(snapshot.reminderHistorySummary?.detail?.contains("Renew license") == true)
        XCTAssertEqual(snapshot.timelineEntryPoints.map(\.label), ["Reminder"])
    }

    private var day: TimeInterval {
        86_400
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
