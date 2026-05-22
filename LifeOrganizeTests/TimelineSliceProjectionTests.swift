import XCTest
@testable import LifeOrganize

final class TimelineSliceProjectionTests: XCTestCase {
    func testMonthSliceUsesLocalStartInclusiveEndExclusiveBoundaries() throws {
        let calendar = Self.newYorkCalendar
        let mayRange = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar))
        let aprilBoundaryEvent = LedgerEvent(
            title: "April close",
            occurredAt: try Self.date(2026, 4, 30, 23, 59, calendar: calendar),
            rawText: "April close"
        )
        let mayStartEvent = LedgerEvent(
            title: "May start",
            occurredAt: try Self.date(2026, 5, 1, 0, 0, calendar: calendar),
            rawText: "May start"
        )
        let mayEndEvent = LedgerEvent(
            title: "May end",
            occurredAt: try Self.date(2026, 5, 31, 23, 59, calendar: calendar),
            rawText: "May end"
        )
        let juneBoundaryEvent = LedgerEvent(
            title: "June start",
            occurredAt: try Self.date(2026, 6, 1, 0, 0, calendar: calendar),
            rawText: "June start"
        )

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            query: TimelineSliceQuery(dateRange: mayRange),
            events: [aprilBoundaryEvent, mayStartEvent, mayEndEvent, juneBoundaryEvent]
        )

        XCTAssertEqual(rows.map(\.displayLabel), ["May end", "May start"])
        XCTAssertEqual(rows.map(\.dateKind), [.occurred, .occurred])
    }

    func testMonthRangeRollsOverYear() throws {
        let calendar = Self.newYorkCalendar
        let range = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 12, calendar: calendar))

        XCTAssertEqual(Self.components([.year, .month, .day], from: range.start, calendar: calendar).year, 2026)
        XCTAssertEqual(Self.components([.year, .month, .day], from: range.start, calendar: calendar).month, 12)
        XCTAssertEqual(Self.components([.year, .month, .day], from: range.endExclusive, calendar: calendar).year, 2027)
        XCTAssertEqual(Self.components([.year, .month, .day], from: range.endExclusive, calendar: calendar).month, 1)
    }

    func testSinceDateSliceUsesLocalDayStartThroughExclusiveEnd() throws {
        let calendar = Self.newYorkCalendar
        let range = TimelineSliceDateRange.since(
            try Self.date(2026, 1, 15, 17, 30, calendar: calendar),
            through: try Self.date(2026, 5, 10, 12, 0, calendar: calendar),
            calendar: calendar
        )
        let beforeStart = LedgerNote(
            text: "Before",
            createdAt: try Self.date(2026, 1, 14, 23, 59, calendar: calendar)
        )
        let startDay = LedgerNote(
            text: "Start day",
            createdAt: try Self.date(2026, 1, 15, 1, 0, calendar: calendar)
        )
        let exclusiveEnd = LedgerNote(
            text: "End",
            createdAt: try Self.date(2026, 5, 10, 12, 0, calendar: calendar)
        )

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            query: TimelineSliceQuery(dateRange: range),
            notes: [beforeStart, startDay, exclusiveEnd]
        )

        XCTAssertEqual(rows.map(\.summaryText), ["Start day"])
        XCTAssertEqual(rows.first?.dateKind, .created)
    }

    func testProjectionRowsCoverDateKindsNavigationLabelsAndCleanSummaries() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, 0, calendar: calendar)
        let car = Thing(name: "Car", aliases: ["daily driver"], category: .vehicle, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "Car entry needs cleanup.", createdAt: now, extractionStatus: .failedNeedsReview)
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: now,
            rawText: "Changed oil at 40k miles.",
            createdAt: now,
            updatedAt: now,
            note: "Synthetic service",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Costco")
            ],
            thing: car
        )
        let reminder = LedgerRule(
            title: "Replace oil filter",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace oil filter next month.",
            startsAt: now.addingTimeInterval(30 * 86_400),
            createdAt: now,
            updatedAt: now,
            thing: car
        )
        let note = LedgerNote(text: "Oil filter brand is OEM.", createdAt: now, updatedAt: now.addingTimeInterval(10), linkedThings: [car])

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            messages: [message],
            things: [car],
            events: [event],
            reminders: [reminder],
            notes: [note]
        )

        XCTAssertTrue(rows.contains { $0.sourceKind == .message && $0.dateKind == .attention && $0.navigationTarget == .chatMessage(message.id) })
        XCTAssertTrue(rows.contains { $0.sourceKind == .event && $0.dateKind == .occurred && $0.navigationTarget == .eventDetail(event.id) })
        XCTAssertTrue(rows.contains { $0.sourceKind == .reminder && $0.dateKind == .dueStart && $0.navigationTarget == .ruleDetail(reminder.id) })
        XCTAssertTrue(rows.contains { $0.sourceKind == .note && $0.dateKind == .created && $0.navigationTarget == .noteDetail(note.id) })
        XCTAssertTrue(rows.contains { $0.sourceKind == .note && $0.dateKind == .updated && $0.navigationTarget == .noteDetail(note.id) })
        XCTAssertTrue(rows.contains { $0.sourceKind == .thing && $0.dateKind == .created && $0.navigationTarget == .thingDetail(car.id) })
        XCTAssertEqual(rows.first { $0.sourceID == event.id }?.displayLabel, "Oil change")
        XCTAssertEqual(rows.first { $0.sourceID == event.id }?.summaryText, "Synthetic service")
        XCTAssertTrue(rows.first { $0.sourceID == event.id }?.searchableText.contains("Costco") == true)
    }

    func testFutureReminderInactiveReminderHistoryAndReviewItemsUseDistinctDateKinds() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, 0, calendar: calendar)
        let futureReminder = LedgerRule(
            title: "Replace cabin filter",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace cabin filter in July.",
            startsAt: try Self.date(2026, 7, 1, 9, 0, calendar: calendar),
            createdAt: now
        )
        let completedReminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Renew registration.",
            startsAt: try Self.date(2026, 4, 1, 9, 0, calendar: calendar),
            createdAt: try Self.date(2026, 3, 1, 9, 0, calendar: calendar),
            manuallyDeactivatedAt: try Self.date(2026, 4, 2, 10, 0, calendar: calendar)
        )
        let reviewReminder = LedgerRule(
            title: "Check trial window",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            rawText: "Check trial window.",
            startsAt: try Self.date(2026, 4, 1, 9, 0, calendar: calendar),
            expiresAt: try Self.date(2026, 5, 1, 9, 0, calendar: calendar),
            createdAt: try Self.date(2026, 4, 1, 9, 0, calendar: calendar)
        )

        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            reminders: [futureReminder, completedReminder, reviewReminder]
        )

        XCTAssertTrue(rows.contains { $0.sourceID == futureReminder.id && $0.dateKind == .dueStart })
        XCTAssertTrue(rows.contains { $0.sourceID == completedReminder.id && $0.dateKind == .completedDeactivated })
        XCTAssertTrue(rows.contains { $0.sourceID == reviewReminder.id && $0.dateKind == .attention })
    }

    func testLinkedThingSlicesFilterByIDNameAndAliasWithRelationshipSourceContext() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, 0, calendar: calendar)
        let car = Thing(name: "Honda Civic", aliases: ["daily driver"], createdAt: now, updatedAt: now)
        let house = Thing(name: "House", createdAt: now, updatedAt: now)
        let carNote = LedgerNote(text: "Registration card is in glove box.", createdAt: now)
        let houseNote = LedgerNote(text: "Gate code changed.", createdAt: now, linkedThings: [house])
        let link = EntityLink(
            sourceType: .note,
            sourceID: carNote.id,
            targetType: .thing,
            targetID: car.id,
            relation: .aboutThing,
            createdBy: .user,
            sourceMessageID: UUID()
        )
        let projection = TimelineSliceProjection(calendar: calendar, now: now)

        let idRows = projection.rows(
            query: TimelineSliceQuery(linkedThingFilter: .id(car.id)),
            things: [car, house],
            notes: [carNote, houseNote],
            entityLinks: [link]
        )
        let nameRows = projection.rows(
            query: TimelineSliceQuery(linkedThingFilter: .text("honda")),
            things: [car, house],
            notes: [carNote, houseNote],
            entityLinks: [link]
        )
        let aliasRows = projection.rows(
            query: TimelineSliceQuery(linkedThingFilter: .text("daily driver")),
            things: [car, house],
            notes: [carNote, houseNote],
            entityLinks: [link]
        )

        XCTAssertTrue(idRows.contains { $0.sourceID == carNote.id })
        XCTAssertFalse(idRows.contains { $0.sourceID == houseNote.id })
        XCTAssertEqual(nameRows.map(\.sourceID), idRows.map(\.sourceID))
        XCTAssertEqual(aliasRows.map(\.sourceID), idRows.map(\.sourceID))
        let carNoteRow = try XCTUnwrap(idRows.first { $0.sourceID == carNote.id })
        XCTAssertEqual(carNoteRow.linkedThings.first?.relationshipSourceLabel, "Linked thing")
        XCTAssertEqual(carNoteRow.relationshipContext?.sourceLabel, "Linked thing")
    }

    func testNoResultSliceReturnsEmptyRows() throws {
        let calendar = Self.newYorkCalendar
        let range = try XCTUnwrap(TimelineSliceDateRange.month(year: 2027, month: 1, calendar: calendar))
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: try Self.date(2026, 5, 21, 12, 0, calendar: calendar),
            rawText: "Changed oil"
        )

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            query: TimelineSliceQuery(dateRange: range, linkedThingFilter: .text("attic vents")),
            events: [event]
        )

        XCTAssertTrue(rows.isEmpty)
    }

    func testTimezoneBoundariesUseTheProvidedCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let range = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar))
        let utcBoundaryStillAprilPacific = LedgerEvent(
            title: "UTC May but Pacific April",
            occurredAt: Date(timeIntervalSince1970: 1_777_610_400),
            rawText: "UTC May but Pacific April"
        )
        let pacificMayStart = LedgerEvent(
            title: "Pacific May",
            occurredAt: try Self.date(2026, 5, 1, 0, 0, calendar: calendar),
            rawText: "Pacific May"
        )

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            query: TimelineSliceQuery(dateRange: range),
            events: [utcBoundaryStillAprilPacific, pacificMayStart]
        )

        XCTAssertEqual(rows.map(\.displayLabel), ["Pacific May"])
    }

    func testTieOrderingUsesTimelineDateCreatedDateKindAndUUIDDeterministically() throws {
        let calendar = Self.newYorkCalendar
        let timelineDate = try Self.date(2026, 5, 21, 12, 0, calendar: calendar)
        let createdLate = try Self.date(2026, 5, 21, 11, 0, calendar: calendar)
        let createdEarly = try Self.date(2026, 5, 21, 10, 0, calendar: calendar)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let event = LedgerEvent(id: secondID, title: "Event", occurredAt: timelineDate, rawText: "Event", createdAt: createdEarly)
        let note = LedgerNote(id: firstID, text: "Note", createdAt: timelineDate, updatedAt: timelineDate)
        let lateMessage = ChatMessage(id: UUID(), role: .user, text: "Message", createdAt: timelineDate, extractionStatus: .needsReview)
        let lateEvent = LedgerEvent(id: firstID, title: "Late event", occurredAt: timelineDate, rawText: "Late event", createdAt: createdLate)

        let rows = TimelineSliceProjection(calendar: calendar).rows(
            messages: [lateMessage],
            events: [event, lateEvent],
            notes: [note]
        )

        XCTAssertEqual(rows.map(\.displayLabel), ["You", "Note", "Late event", "Event"])
    }

    private static var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private static func components(_ components: Set<Calendar.Component>, from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents(components, from: date)
    }
}
