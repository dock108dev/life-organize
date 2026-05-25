import SwiftData
import XCTest
@testable import LifeOrganize

final class ThingDetailSnapshotTests: XCTestCase {
    @MainActor
    func testActiveRemindersUseContinuityLaneSorting() {
        let now = fixedTestNow
        let thing = Thing(name: "Car")
        let openEnded = LedgerRule(
            title: "Keep registration in glove box",
            ruleType: .reminder,
            rawText: "Keep registration in glove box.",
            startsAt: now.addingTimeInterval(-7 * day),
            createdAt: now.addingTimeInterval(-7 * day),
            updatedAt: now.addingTimeInterval(-7 * day),
            thing: thing
        )
        let expiresLater = LedgerRule(
            title: "Renew inspection",
            ruleType: .reminder,
            rawText: "Renew inspection next month.",
            startsAt: now.addingTimeInterval(-2 * day),
            expiresAt: now.addingTimeInterval(30 * day),
            createdAt: now.addingTimeInterval(-2 * day),
            updatedAt: now.addingTimeInterval(-2 * day),
            thing: thing
        )
        let expiresSoon = LedgerRule(
            title: "Replace temporary tire",
            ruleType: .reminder,
            rawText: "Replace temporary tire this week.",
            startsAt: now.addingTimeInterval(-day),
            expiresAt: now.addingTimeInterval(3 * day),
            createdAt: now.addingTimeInterval(-day),
            updatedAt: now.addingTimeInterval(-day),
            thing: thing
        )
        thing.rules = [openEnded, expiresLater, expiresSoon]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.status, .active)
        XCTAssertEqual(snapshot.activeReminders.map(\.title), [
            "Keep registration in glove box",
            "Replace temporary tire",
            "Renew inspection"
        ])
        XCTAssertEqual(snapshot.upcomingReminders.map(\.title), [
            "Keep registration in glove box",
            "Replace temporary tire",
            "Renew inspection"
        ])
        XCTAssertEqual(snapshot.nextReminder?.title, "Keep registration in glove box")
        XCTAssertEqual(snapshot.countSummary, "0 events · 0 notes · 3 active reminders")
    }

    @MainActor
    func testRecentHistoryWithoutActiveRemindersIsQuietAndUsesLatestActivity() {
        let now = fixedTestNow
        let thing = Thing(name: "HVAC")
        let event = LedgerEvent(
            title: "Changed filter",
            occurredAt: now.addingTimeInterval(-14 * day),
            rawText: "Changed HVAC filter.",
            createdAt: now.addingTimeInterval(-14 * day),
            thing: thing
        )
        let note = LedgerNote(
            text: "Filter size is 16x20.",
            createdAt: now.addingTimeInterval(-2 * day),
            updatedAt: now.addingTimeInterval(-2 * day),
            linkedThings: [thing]
        )
        thing.events = [event]
        thing.notes = [note]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.status, .quiet)
        XCTAssertEqual(snapshot.latestActivity?.title, "Note updated")
        XCTAssertEqual(snapshot.latestActivity?.date, note.updatedAt)
        XCTAssertEqual(snapshot.events.first?.title, "Changed filter")
        XCTAssertEqual(snapshot.notes.first?.text, "Filter size is 16x20.")
    }

    @MainActor
    func testInactiveRemindersSortByLifecycleDateAndOldRecordsAreHistorical() {
        let now = fixedTestNow
        let thing = Thing(name: "Lease")
        let olderExpired = LedgerRule(
            title: "Old parking window",
            ruleType: .reminder,
            rawText: "Parking window ended.",
            startsAt: now.addingTimeInterval(-220 * day),
            expiresAt: now.addingTimeInterval(-180 * day),
            createdAt: now.addingTimeInterval(-220 * day),
            updatedAt: now.addingTimeInterval(-180 * day),
            thing: thing
        )
        let newerExpired = LedgerRule(
            title: "Expired rent discount",
            ruleType: .reminder,
            rawText: "Rent discount ended.",
            startsAt: now.addingTimeInterval(-120 * day),
            expiresAt: now.addingTimeInterval(-95 * day),
            createdAt: now.addingTimeInterval(-120 * day),
            updatedAt: now.addingTimeInterval(-95 * day),
            thing: thing
        )
        let oldEvent = LedgerEvent(
            title: "Signed lease",
            occurredAt: now.addingTimeInterval(-200 * day),
            rawText: "Signed lease.",
            createdAt: now.addingTimeInterval(-200 * day),
            thing: thing
        )
        thing.rules = [olderExpired, newerExpired]
        thing.events = [oldEvent]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.status, .historical)
        XCTAssertTrue(snapshot.activeReminders.isEmpty)
        XCTAssertEqual(snapshot.inactiveReminders.map(\.title), [
            "Expired rent discount",
            "Old parking window"
        ])
    }

    @MainActor
    func testOperationalSummariesUseKnownEventReminderAndNoteFacts() {
        let now = fixedTestNow
        let thing = Thing(name: "Storage Unit")
        let event = LedgerEvent(
            title: "Renewed storage unit",
            occurredAt: now,
            rawText: "Renewed storage unit.",
            eventType: .renewal,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: 129, unit: "USD"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Boxwell Depot"),
                LedgerEventMetadataEntry(key: .dueDate, valueKind: .date, dateValue: "2027-03-15")
            ],
            thing: thing
        )
        let scheduledReminder = LedgerRule(
            title: "Confirm storage renewal",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Confirm renewal in March.",
            startsAt: now.addingTimeInterval(14 * day),
            createdAt: now,
            updatedAt: now,
            thing: thing
        )
        let note = LedgerNote(
            text: "Gate code works after hours.",
            createdAt: now.addingTimeInterval(-day),
            updatedAt: now.addingTimeInterval(-day),
            linkedThings: [thing]
        )
        thing.events = [event]
        thing.rules = [scheduledReminder]
        thing.notes = [note]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertEqual(snapshot.reminderSummary.label, "Scheduled reminder")
        XCTAssertEqual(snapshot.reminderSummary.value, "Confirm storage renewal")
        XCTAssertTrue(snapshot.reminderSummary.detail?.contains("Due") == true)
        XCTAssertEqual(snapshot.primaryOperationalSummary?.label, "Latest activity")
        XCTAssertEqual(snapshot.primaryOperationalSummary?.value, "Renewed storage unit")
        XCTAssertEqual(snapshot.recentActivitySummary?.label, "Recent timeline activity")
        XCTAssertEqual(snapshot.recentActivitySummary?.value, "Renewed storage unit")
        XCTAssertEqual(snapshot.upcomingReminders.map(\.title), ["Confirm storage renewal"])
        XCTAssertTrue(snapshot.inactiveReminders.isEmpty)
        XCTAssertEqual(snapshot.latestEventSummary?.label, "Last event")
        XCTAssertEqual(snapshot.latestEventSummary?.value, "Renewed storage unit")
        XCTAssertTrue(snapshot.latestEventSummary?.detail?.contains("Due Date: Mar 15, 2027") == true)
        XCTAssertTrue(snapshot.latestEventSummary?.detail?.contains("Vendor: Boxwell Depot") == true)
        XCTAssertTrue(snapshot.latestEventSummary?.detail?.contains("Amount: $129.00") == true)
        XCTAssertEqual(snapshot.latestNoteSummary?.value, "Gate code works after hours.")
        XCTAssertEqual(snapshot.timelineEntryPoints.map(\.label), ["Event", "Note", "Reminder"])
        XCTAssertTrue(snapshot.hasHistory)
    }

    @MainActor
    func testDetailPreviewAndRelationshipTraversalReflectEditAndDeleteReassignment() throws {
        let now = fixedTestNow
        let context = makeInMemoryModelContext()
        let source = Thing(name: "NWS", category: .work, createdAt: now, updatedAt: now)
        let target = Thing(name: "Nimbus Web Services", aliases: ["Nimbus"], category: .work, createdAt: now, updatedAt: now)
        let event = LedgerEvent(title: "Deploy completed", occurredAt: now, rawText: "Deploy completed.", thing: source)
        let reminder = LedgerRule(title: "Review deploy", ruleType: .reminder, rawText: "Review deploy.", startsAt: now, thing: source)
        let note = LedgerNote(text: "Release notes are in the deploy folder.", linkedThings: [source])
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })
        context.insert(source)
        context.insert(target)
        try service.insertEvent(event)
        try service.insertRule(reminder)
        try service.insertNote(note)
        try context.save()

        var sourceSnapshot = ThingDetailSnapshot(thing: source, now: now, calendar: utcCalendar)
        XCTAssertEqual(sourceSnapshot.countSummary, "1 event · 1 note · 1 active reminder")
        XCTAssertEqual(Set(sourceSnapshot.timelineEntryPoints.map(\.navigationTarget)), [
            .eventDetail(event.id),
            .ruleDetail(reminder.id),
            .noteDetail(note.id)
        ])

        target.registerAliases(["NWS"], updatedAt: now.addingTimeInterval(60))
        try service.deleteThing(source, reassigningRecordsTo: target)
        try context.save()

        let savedThings = try context.fetch(FetchDescriptor<Thing>())
        let savedEvents = try context.fetch(FetchDescriptor<LedgerEvent>())
        let savedRules = try context.fetch(FetchDescriptor<LedgerRule>())
        let savedNotes = try context.fetch(FetchDescriptor<LedgerNote>())
        XCTAssertFalse(savedThings.contains { $0.id == source.id })

        let targetSnapshot = ThingDetailSnapshot(thing: target, now: now, calendar: utcCalendar)
        let targetPreview = ThingPreviewSnapshot(thing: target, now: now, calendar: utcCalendar)
        let relatedTargets = RelationshipTraversalService().relatedRecords(
            for: .thing(target.id),
            in: RelationshipTraversalRecords(
                things: savedThings,
                events: savedEvents,
                rules: savedRules,
                notes: savedNotes
            ),
            allowedTargetTypes: [.event, .rule, .note]
        )

        sourceSnapshot = ThingDetailSnapshot(thing: target, now: now, calendar: utcCalendar)
        XCTAssertEqual(sourceSnapshot.countSummary, targetSnapshot.countSummary)
        XCTAssertEqual(targetSnapshot.countSummary, "1 event · 1 note · 1 active reminder")
        XCTAssertEqual(targetSnapshot.identityRows.first { $0.label == "Aliases" }?.value, "Nimbus, NWS")
        XCTAssertEqual(targetPreview.listSummaryLine.text, "3 records · Reminder due today")
        XCTAssertEqual(targetPreview.footerItems, ["1 event", "1 note"])
        XCTAssertEqual(Set(relatedTargets.map(\.target)), [.event(event.id), .rule(reminder.id), .note(note.id)])
    }

    @MainActor
    func testContinuityMetricInputsStaySeparateFromIdentityAndDiagnostics() {
        let now = fixedTestNow
        let thing = Thing(
            name: "Car",
            details: "Parked in garage.",
            aliases: ["Honda"],
            category: .maintenance,
            createdAt: now.addingTimeInterval(-12 * day),
            updatedAt: now
        )
        let olderService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now.addingTimeInterval(-80 * day),
            rawText: "Changed oil at 40,000 mi.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 40_000, unit: "mi")
            ],
            thing: thing
        )
        let latestService = LedgerEvent(
            title: "Changed oil",
            occurredAt: now.addingTimeInterval(-10 * day),
            rawText: "Changed oil at 45,000 mi.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 45_000, unit: "mi")
            ],
            thing: thing
        )
        let reminder = LedgerRule(
            title: "Check oil level",
            ruleType: .reminder,
            rawText: "Check oil level.",
            startsAt: now.addingTimeInterval(-day),
            createdAt: now.addingTimeInterval(-day),
            updatedAt: now.addingTimeInterval(-day),
            thing: thing
        )
        let note = LedgerNote(
            text: "Use synthetic oil.",
            createdAt: now.addingTimeInterval(-2 * day),
            updatedAt: now.addingTimeInterval(-2 * day),
            linkedThings: [thing]
        )
        thing.events = [olderService, latestService]
        thing.rules = [reminder]
        thing.notes = [note]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)
        let continuityLabels = [
            snapshot.statusSummary.label,
            snapshot.primaryOperationalSummary?.label,
            snapshot.continuitySummary?.label,
            snapshot.reminderSummary.label,
            snapshot.recentActivitySummary?.label
        ].compactMap { $0 }

        XCTAssertEqual(continuityLabels, [
            "Status",
            "Latest service",
            "Service continuity",
            "Active reminder",
            "Recent timeline activity"
        ])
        XCTAssertEqual(snapshot.identityRows.map(\.label), ["Category", "Details", "Aliases"])
        XCTAssertEqual(snapshot.diagnosticRows.map(\.label), ["Created", "Updated", "Extraction records"])
    }

    @MainActor
    func testOperationalSummariesStayQuietForRecordedFilterFactsWithoutPrediction() {
        let now = fixedTestNow
        let thing = Thing(name: "Home Air Filters")
        let event = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now.addingTimeInterval(-30 * day),
            rawText: "Replaced filters.",
            eventType: .replacement,
            thing: thing
        )
        thing.events = [event]

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)
        let renderedSummary = [
            snapshot.statusSummary.value,
            snapshot.statusSummary.detail,
            snapshot.reminderSummary.value,
            snapshot.reminderSummary.detail,
            snapshot.latestEventSummary?.value,
            snapshot.latestEventSummary?.detail
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        XCTAssertEqual(snapshot.status, .quiet)
        XCTAssertEqual(snapshot.reminderSummary.value, "No reminders")
        XCTAssertFalse(renderedSummary.localizedCaseInsensitiveContains("next likely"))
        XCTAssertFalse(renderedSummary.localizedCaseInsensitiveContains("typical interval"))
        XCTAssertFalse(renderedSummary.localizedCaseInsensitiveContains("usually"))
    }

    @MainActor
    func testIdentityAndDiagnosticRowsAreDemotedOutOfOperationalHistory() {
        let now = fixedTestNow
        let sourceMessageID = UUID()
        let sourceAttemptID = UUID()
        let thing = Thing(
            name: "Car",
            details: "Stored in the north garage.",
            aliases: ["Honda"],
            category: .maintenance,
            createdAt: now.addingTimeInterval(-10 * day),
            updatedAt: now,
            sourceMessageIDs: [sourceMessageID],
            sourceExtractionAttemptIDs: [sourceAttemptID]
        )

        let snapshot = ThingDetailSnapshot(thing: thing, now: now, calendar: utcCalendar)

        XCTAssertFalse(snapshot.hasHistory)
        XCTAssertEqual(snapshot.identityRows.map(\.label), ["Category", "Details", "Aliases"])
        XCTAssertEqual(snapshot.identityRows.map(\.value), ["Maintenance", "Stored in the north garage.", "Honda"])
        XCTAssertEqual(snapshot.diagnosticRows.map(\.label), ["Created", "Updated", "Extraction records"])
        XCTAssertEqual(snapshot.diagnosticRows.last?.value, "2 records")
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
