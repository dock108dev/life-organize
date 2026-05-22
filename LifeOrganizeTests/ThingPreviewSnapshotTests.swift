import XCTest
@testable import LifeOrganize

final class ThingPreviewSnapshotTests: XCTestCase {
    @MainActor
    func testCarPreviewSurfacesLatestEventUpcomingReminderAndRecentNote() {
        let now = fixedTestNow
        let oilChangeDate = now.addingTimeInterval(-2 * 86_400)
        let tireRotationDate = now.addingTimeInterval(24 * 86_400)
        let car = Thing(
            name: "Car",
            aliases: ["Honda"],
            category: .maintenance,
            eventCount: 2,
            lastEventAt: oilChangeDate
        )
        let oilChange = LedgerEvent(
            title: "Oil change",
            occurredAt: oilChangeDate,
            rawText: "Changed oil at 52,000 mi.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .amount,
                    valueKind: .number,
                    numberValue: 84.2,
                    unit: "USD"
                ),
                LedgerEventMetadataEntry(
                    key: .vendor,
                    valueKind: .string,
                    stringValue: "Northline Auto"
                ),
                LedgerEventMetadataEntry(
                    key: .mileage,
                    valueKind: .number,
                    numberValue: 52_000,
                    unit: "mi"
                )
            ],
            thing: car
        )
        let tireRotation = LedgerRule(
            title: "Rotate tires",
            ruleType: .reminder,
            rawText: "Rotate tires in 24 days.",
            startsAt: tireRotationDate,
            createdAt: now,
            updatedAt: now,
            thing: car
        )
        let insuranceRenewal = LedgerNote(
            text: "Insurance renewed with annual premium.",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            linkedThings: [car]
        )
        car.events = [oilChange]
        car.rules = [tireRotation]
        car.notes = [insuranceRenewal]

        let snapshot = ThingPreviewSnapshot(thing: car, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.title, "Car")
        XCTAssertEqual(snapshot.eventCount, 1)
        XCTAssertEqual(snapshot.latestEventTitle, "Oil change")
        XCTAssertEqual(snapshot.latestEventDate, oilChangeDate)
        XCTAssertEqual(snapshot.latestEventMetadataSummary, "Mileage: 52,000 mi · Vendor: Northline Auto")
        XCTAssertEqual(snapshot.upcomingReminderTitle, "Rotate tires")
        XCTAssertEqual(snapshot.upcomingReminderRelativeDueText, "in 24 days")
        XCTAssertEqual(snapshot.upcomingReminderKind, .starts)
        XCTAssertEqual(snapshot.latestNoteSnippet, "Insurance renewed with annual premium.")
        XCTAssertEqual(snapshot.continuityLines.map(\.label), ["Last event", "Upcoming", "Recent note"])
        XCTAssertEqual(snapshot.continuityLines.map(\.value), [
            "Oil change",
            "Rotate tires",
            "Insurance renewed with annual premium."
        ])
        XCTAssertEqual(snapshot.continuityLines[0].detail, "Jan 13 · Mileage: 52,000 mi · Vendor: Northline Auto")
        XCTAssertEqual(snapshot.continuityLines[1].detail, "in 24 days")
        XCTAssertEqual(snapshot.footerItems, ["1 event", "1 note"])
        XCTAssertFalse(snapshot.footerItems.joined(separator: " ").contains("Alias"))
    }

    @MainActor
    func testPreviewDegradesWithOnlyReminderOnlyNoteAndNoHistory() {
        let now = fixedTestNow
        let activeReminderThing = Thing(name: "Passport")
        let activeReminder = LedgerRule(
            title: "Keep passport in fire safe",
            ruleType: .reminder,
            rawText: "Keep passport in fire safe.",
            startsAt: now.addingTimeInterval(-86_400),
            createdAt: now,
            thing: activeReminderThing
        )
        activeReminderThing.rules = [activeReminder]

        let reminderSnapshot = ThingPreviewSnapshot(thing: activeReminderThing, now: now, calendar: utcCalendar)
        XCTAssertNil(reminderSnapshot.latestEventTitle)
        XCTAssertEqual(reminderSnapshot.activeReminderCount, 1)
        XCTAssertEqual(reminderSnapshot.primaryActiveReminderTitle, "Keep passport in fire safe")
        XCTAssertTrue(reminderSnapshot.hasPreviewContent)

        let noteOnlyThing = Thing(name: "HVAC")
        let note = LedgerNote(text: "Filter size is 16x20.", createdAt: now, updatedAt: now, linkedThings: [noteOnlyThing])
        noteOnlyThing.notes = [note]

        let noteSnapshot = ThingPreviewSnapshot(thing: noteOnlyThing, now: now, calendar: utcCalendar)
        XCTAssertEqual(noteSnapshot.latestNoteSnippet, "Filter size is 16x20.")
        XCTAssertEqual(noteSnapshot.footerItems, ["1 note"])
        XCTAssertTrue(noteSnapshot.hasPreviewContent)

        let emptySnapshot = ThingPreviewSnapshot(thing: Thing(name: "Storage Unit"), now: now, calendar: utcCalendar)
        XCTAssertFalse(emptySnapshot.hasPreviewContent)
        XCTAssertEqual(emptySnapshot.continuityLines.first?.label, "History")
        XCTAssertEqual(emptySnapshot.continuityLines.first?.value, "No records yet")
        XCTAssertEqual(emptySnapshot.footerItems, [])
    }

    @MainActor
    func testAliasesStaySecondaryToOperationalContinuity() {
        let now = fixedTestNow
        let thing = Thing(
            name: "Honda Civic",
            aliases: ["daily driver"],
            category: .vehicle,
            eventCount: 1,
            lastEventAt: now
        )
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: now,
            rawText: "Changed oil.",
            eventType: .maintenance,
            thing: thing
        )
        thing.events = [event]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.continuityLines.first?.label, "Last event")
        XCTAssertFalse(snapshot.footerItems.contains { $0.localizedCaseInsensitiveContains("alias") })
        XCTAssertNotEqual(snapshot.continuityLines.first?.label, "Also known as")
    }

    @MainActor
    func testAliasOnlyPreviewDoesNotCrowdContinuityRows() {
        let snapshot = ThingPreviewSnapshot(
            thing: Thing(name: "Honda Civic", aliases: ["daily driver"]),
            now: fixedTestNow,
            calendar: utcCalendar
        )

        XCTAssertEqual(snapshot.aliasSummary, "daily driver")
        XCTAssertEqual(snapshot.continuityLines.map(\.label), ["History"])
        XCTAssertEqual(snapshot.continuityLines.map(\.value), ["No records yet"])
        XCTAssertFalse(snapshot.hasPreviewContent)
        XCTAssertEqual(snapshot.footerItems, [])
    }

    @MainActor
    func testCategoryFooterSuppressionKeepsCountsTertiary() {
        let thing = Thing(name: "Air Filters", category: .homeMaintenance)
        let event = LedgerEvent(
            title: "Bought filters",
            occurredAt: fixedTestNow,
            rawText: "Bought filters.",
            eventType: .purchase,
            thing: thing
        )
        let note = LedgerNote(
            text: "Six pack stored in garage.",
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow,
            linkedThings: [thing]
        )
        thing.events = [event]
        thing.notes = [note]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: fixedTestNow, calendar: utcCalendar)

        XCTAssertEqual(snapshot.categoryTitle, "Home Maintenance")
        XCTAssertEqual(snapshot.footerItems, ["1 event", "1 note"])
        XCTAssertFalse(snapshot.footerItems.contains("Home Maintenance"))
    }

    @MainActor
    func testPreviewUsesEventTypeMetadataPriorityAndReadableValues() throws {
        let now = fixedTestNow
        let dueDate = "2027-03-15"
        let filters = Thing(name: "Home Air Filters", eventCount: 99, lastEventAt: now)
        let purchase = LedgerEvent(
            title: "Bought filter kit",
            occurredAt: now,
            rawText: "Bought filters.",
            eventType: .purchase,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: 42.18, unit: "USD"),
                LedgerEventMetadataEntry(key: .dueDate, valueKind: .date, dateValue: dueDate),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Hearth & Bolt"),
                LedgerEventMetadataEntry(key: .location, valueKind: .string, stringValue: "Aisle 12")
            ],
            thing: filters
        )
        filters.events = [purchase]

        let snapshot = ThingPreviewSnapshot(thing: filters, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.eventCount, 1)
        XCTAssertEqual(snapshot.latestEventMetadataSummary, "Vendor: Hearth & Bolt · Amount: $42.18")
        XCTAssertFalse(snapshot.footerItems.contains("99 events"))
    }

    @MainActor
    func testPreviewFiltersLowValueMetadataFromLatestEventSummary() {
        let thing = Thing(name: "Receipt")
        let event = LedgerEvent(
            title: "",
            occurredAt: fixedTestNow,
            rawText: "Imported receipt.",
            eventType: .purchase,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .identifier, valueKind: .string, stringValue: "INV-412"),
                LedgerEventMetadataEntry(key: .sourceText, valueKind: .string, stringValue: "receipt line"),
                LedgerEventMetadataEntry(key: .location, valueKind: .string, stringValue: "Aisle 12")
            ],
            thing: thing
        )
        thing.events = [event]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: fixedTestNow, calendar: utcCalendar)

        XCTAssertNil(snapshot.latestEventMetadataSummary)
        XCTAssertEqual(snapshot.continuityLines.first?.label, "Last event")
        XCTAssertEqual(snapshot.continuityLines.first?.value, "Saved event")
        XCTAssertEqual(snapshot.footerItems, ["1 event"])
    }

    @MainActor
    func testPreviewShowsActiveAndUpcomingReminderContext() {
        let now = fixedTestNow
        let thing = Thing(name: "Warranty")
        let activeWindow = LedgerRule(
            title: "",
            ruleType: .reminder,
            rawText: "Warranty coverage.",
            startsAt: now.addingTimeInterval(-2 * 86_400),
            expiresAt: now.addingTimeInterval(4 * 86_400),
            createdAt: now,
            thing: thing
        )
        let scheduledCheck = LedgerRule(
            title: "Renew coverage",
            ruleType: .reminder,
            rawText: "Renew coverage next month.",
            startsAt: now.addingTimeInterval(30 * 86_400),
            createdAt: now,
            thing: thing
        )
        thing.rules = [scheduledCheck, activeWindow]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.primaryActiveReminderTitle, "Saved reminder")
        XCTAssertEqual(snapshot.upcomingReminderTitle, "Saved reminder")
        XCTAssertEqual(snapshot.upcomingReminderKind, .expires)
        XCTAssertEqual(snapshot.continuityLines.map(\.label), ["Reminder", "Expires"])
        XCTAssertEqual(snapshot.continuityLines.map(\.value), ["Saved reminder", "Saved reminder"])
        XCTAssertEqual(snapshot.continuityLines[1].detail, "in 4 days")
    }

    func testEventMetadataDetailOrderUsesOperationalPriority() {
        let entries = [
            LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Northline Auto"),
            LedgerEventMetadataEntry(key: .identifier, valueKind: .string, stringValue: "INV-412"),
            LedgerEventMetadataEntry(key: .dueDate, valueKind: .date, dateValue: "2027-03-15"),
            LedgerEventMetadataEntry(key: .sourceText, valueKind: .string, stringValue: "receipt line"),
            LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 52_000, unit: "mi"),
            LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: 84.2, unit: "USD"),
            LedgerEventMetadataEntry(key: .location, valueKind: .string, stringValue: "Bay 3")
        ]

        let ordered = EventMetadataDisplayFormatter.orderedDetailEntries(entries, eventType: .maintenance)

        XCTAssertEqual(
            ordered.map(\.key),
            [.dueDate, .mileage, .amount, .vendor, .location, .identifier, .sourceText]
        )
        XCTAssertEqual(EventMetadataDisplayFormatter.displayValue(for: ordered[0]), "Mar 15, 2027")
        XCTAssertEqual(EventMetadataDisplayFormatter.displayValue(for: ordered[2]), "$84.20")
    }

    @MainActor
    func testPreviewRecomputesAfterRelationshipEditsAndDeletes() {
        let now = fixedTestNow
        let thing = Thing(name: "Car", eventCount: 2, lastEventAt: now)
        let olderEvent = LedgerEvent(
            title: "Bought wipers",
            occurredAt: now.addingTimeInterval(-10 * 86_400),
            rawText: "Bought wipers.",
            eventType: .purchase,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Parts Counter")
            ],
            thing: thing
        )
        let newerEvent = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 52_000, unit: "mi")
            ],
            thing: thing
        )
        let reminder = LedgerRule(title: "Check tire pressure", startsAt: now.addingTimeInterval(-86_400), thing: thing)
        let note = LedgerNote(text: "Uses synthetic oil.", createdAt: now, updatedAt: now, linkedThings: [thing])
        thing.events = [olderEvent, newerEvent]
        thing.rules = [reminder]
        thing.notes = [note]

        var snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)
        XCTAssertEqual(snapshot.latestEventTitle, "Changed oil")
        XCTAssertEqual(snapshot.activeReminderCount, 1)
        XCTAssertEqual(snapshot.latestNoteSnippet, "Uses synthetic oil.")

        thing.events = [olderEvent]
        thing.rules = []
        note.body = "Uses beam wipers."
        snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.eventCount, 1)
        XCTAssertEqual(snapshot.latestEventTitle, "Bought wipers")
        XCTAssertEqual(snapshot.activeReminderCount, 0)
        XCTAssertEqual(snapshot.latestNoteSnippet, "Uses beam wipers.")

        thing.events = []
        thing.notes = [
            LedgerNote(
                text: "Blade size moved to glove box card.",
                createdAt: now.addingTimeInterval(86_400),
                updatedAt: now.addingTimeInterval(86_400),
                linkedThings: [thing]
            )
        ]
        snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertNil(snapshot.latestEventTitle)
        XCTAssertEqual(snapshot.eventCount, 0)
        XCTAssertEqual(snapshot.latestNoteSnippet, "Blade size moved to glove box card.")
        XCTAssertEqual(snapshot.continuityLines.first?.label, "Last event")
        XCTAssertEqual(snapshot.continuityLines.first?.value, "Jan 15")
        XCTAssertEqual(snapshot.footerItems, ["1 note"])
    }

    @MainActor
    func testPreviewShowsVehicleServiceContinuityFromRepeatedMileageEvents() {
        let now = fixedTestNow
        let thing = Thing(name: "Car", category: .maintenance)
        let olderService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now.addingTimeInterval(-90 * 86_400),
            rawText: "Changed oil.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 46_000, unit: "mi")
            ],
            thing: thing
        )
        let latestService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 52_000, unit: "mi")
            ],
            thing: thing
        )
        thing.events = [olderService, latestService]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.continuityLines.map(\.label), ["Last event", "Service rhythm"])
        XCTAssertEqual(snapshot.continuityLines[1].value, "About every 6,000 mi")
        XCTAssertTrue(snapshot.continuityLines[1].detail?.contains("Next 58,000 mi") == true)
    }

    @MainActor
    func testPreviewShowsConsumablePatternAndExistingReminderSuppression() {
        let now = fixedTestNow
        let thing = Thing(name: "Home Air Filters")
        let olderReplacement = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now.addingTimeInterval(-90 * 86_400),
            rawText: "Replaced filters.",
            eventType: .replacement,
            thing: thing
        )
        let latestReplacement = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now.addingTimeInterval(-30 * 86_400),
            rawText: "Replaced filters again.",
            eventType: .replacement,
            thing: thing
        )
        let reminder = LedgerRule(
            title: "Replace filters",
            ruleType: .reminder,
            rawText: "Replace filters next month.",
            startsAt: now.addingTimeInterval(30 * 86_400),
            createdAt: now,
            updatedAt: now,
            thing: thing
        )
        thing.events = [olderReplacement, latestReplacement]
        thing.rules = [reminder]

        let snapshot = ThingPreviewSnapshot(thing: thing, now: now, calendar: utcCalendar)
        let pattern = snapshot.continuityLines.first { $0.label == "Replacement rhythm" }

        XCTAssertEqual(pattern?.value, "About every 60 days")
        XCTAssertEqual(pattern?.detail, "Reminder already saved: Replace filters")
        XCTAssertFalse(pattern?.detail?.contains("Expected next check") == true)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
