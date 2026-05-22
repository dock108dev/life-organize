import XCTest
@testable import LifeOrganize

final class TimelineAwareSearchTests: XCTestCase {
    func testDateOnlySearchReturnsMixedLocalResultsAndReplayDestination() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let mayRange = try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar))
        let car = Thing(name: "Honda Civic", aliases: ["daily driver"], createdAt: now, updatedAt: now)
        let event = LedgerEvent(title: "Oil change", occurredAt: try Self.date(2026, 5, 4, 9, calendar: calendar), rawText: "Changed oil", thing: car)
        let reminder = LedgerRule(title: "Renew registration", ruleType: .reminder, startsAt: try Self.date(2026, 5, 12, 10, calendar: calendar), createdAt: now, thing: car)
        let note = LedgerNote(text: "Insurance card is in the glove box.", createdAt: try Self.date(2026, 5, 8, 14, calendar: calendar), linkedThings: [car])
        let message = ChatMessage(role: .user, text: "Car entry needs review.", createdAt: try Self.date(2026, 5, 5, 12, calendar: calendar))
        let search = SearchService()
        let records = search.records(things: [car], events: [event], rules: [reminder], notes: [note], messages: [message])

        let results = search.search(LocalSearchQuery(rawText: "May 2026", limit: 20, now: now, calendar: calendar), in: records)

        XCTAssertTrue(search.search("", in: records).isEmpty)
        XCTAssertTrue(results.contains { $0.sourceKind == .timelineSlice })
        XCTAssertTrue(Set(results.map(\.sourceKind)).isSuperset(of: [.thing, .event, .rule, .note, .chatMessage, .timelineSlice]))
        let slice = try XCTUnwrap(results.first { $0.sourceKind == .timelineSlice })
        XCTAssertEqual(slice.title, "May 2026")
        if case .timelineSlice(let descriptor) = slice.navigationTarget {
            XCTAssertEqual(descriptor.query.dateRange, mayRange)
            XCTAssertNil(descriptor.query.linkedThingFilter)
        } else {
            XCTFail("Expected a timeline replay destination")
        }
    }

    func testLinkedThingDateRangeSearchPreservesReplayFiltersAndOrdering() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let car = Thing(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Honda Civic",
            aliases: ["daily driver"],
            createdAt: try Self.date(2026, 1, 2, 8, calendar: calendar),
            updatedAt: now
        )
        let house = Thing(name: "House", createdAt: now, updatedAt: now)
        let carEvent = LedgerEvent(title: "Tire rotation", occurredAt: try Self.date(2026, 3, 4, 9, calendar: calendar), rawText: "Rotated tires", thing: car)
        let houseEvent = LedgerEvent(title: "Paint touchup", occurredAt: try Self.date(2026, 3, 4, 9, calendar: calendar), rawText: "Paint", thing: house)
        let search = SearchService()
        let records = search.records(things: [car, house], events: [carEvent, houseEvent])
        let query = LocalSearchQuery(rawText: "Honda since January", limit: 5, now: now, calendar: calendar)

        let firstRun = search.search(query, in: records)
        let secondRun = search.search(query, in: records)

        XCTAssertEqual(firstRun.map(\.id), secondRun.map(\.id))
        XCTAssertTrue(firstRun.contains { $0.navigationTarget == .eventDetail(carEvent.id) })
        XCTAssertFalse(firstRun.contains { $0.navigationTarget == .eventDetail(houseEvent.id) })
        let slice = try XCTUnwrap(firstRun.first { $0.sourceKind == .timelineSlice })
        XCTAssertEqual(slice.linkedThingId, car.id)
        if case .timelineSlice(let descriptor) = slice.navigationTarget {
            XCTAssertEqual(descriptor.query.linkedThingFilter, .id(car.id))
            XCTAssertNotNil(descriptor.query.dateRange)
        } else {
            XCTFail("Expected a linked timeline replay destination")
        }
    }

    func testMetadataReminderStateRoughTimingAndLimitsCompose() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 6, 15, 12, calendar: calendar)
        let car = Thing(name: "Car", aliases: ["daily driver"], createdAt: try Self.date(2026, 1, 1, 8, calendar: calendar), updatedAt: now)
        let oilChange = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 2, 9, calendar: calendar),
            rawText: "Changed oil at 40k miles.",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 40_000, unit: "mi", sourceText: "40k miles")
            ],
            thing: car
        )
        let inactiveReminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            rawText: "Renew registration.",
            startsAt: try Self.date(2026, 5, 10, 9, calendar: calendar),
            createdAt: try Self.date(2026, 1, 1, 9, calendar: calendar),
            isActive: false,
            manuallyDeactivatedAt: try Self.date(2026, 5, 11, 9, calendar: calendar),
            thing: car
        )
        let futureReminder = LedgerRule(
            title: "Replace cabin filter",
            ruleType: .reminder,
            rawText: "Replace cabin filter.",
            startsAt: try Self.date(2026, 7, 1, 9, calendar: calendar),
            createdAt: now,
            thing: car
        )
        let search = SearchService()
        let records = search.records(things: [car], events: [oilChange], rules: [inactiveReminder, futureReminder])

        let mileageResults = search.search(LocalSearchQuery(rawText: "40k last month", limit: 10, now: now, calendar: calendar), in: records)
        XCTAssertTrue(mileageResults.contains { $0.navigationTarget == .eventDetail(oilChange.id) })
        XCTAssertEqual(mileageResults.first?.sourceKind, .timelineSlice)

        let inactiveExcluded = search.search(
            LocalSearchQuery(rawText: "registration since January", includeInactiveRules: false, now: now, calendar: calendar),
            in: records
        )
        XCTAssertFalse(inactiveExcluded.contains { $0.navigationTarget == .ruleDetail(inactiveReminder.id) })
        let inactiveIncluded = search.search(
            LocalSearchQuery(rawText: "registration since January", includeInactiveRules: true, now: now, calendar: calendar),
            in: records
        )
        XCTAssertTrue(inactiveIncluded.contains { $0.navigationTarget == .ruleDetail(inactiveReminder.id) })

        let upcoming = search.search(LocalSearchQuery(rawText: "upcoming", limit: 10, now: now, calendar: calendar), in: records)
        XCTAssertTrue(upcoming.contains { $0.navigationTarget == .ruleDetail(futureReminder.id) })

        let limited = search.search(LocalSearchQuery(rawText: "", limit: 1, now: now, dateRange: try XCTUnwrap(TimelineSliceDateRange.month(year: 2026, month: 5, calendar: calendar)), calendar: calendar), in: records)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited.first?.sourceKind, .timelineSlice)
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
}
