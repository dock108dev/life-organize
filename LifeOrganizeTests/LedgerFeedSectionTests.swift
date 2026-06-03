import XCTest
@testable import LifeOrganize

final class LedgerFeedSectionTests: XCTestCase {
    func testDateGroupingUsesLocalCalendarBuckets() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 10, calendar: calendar)
        let grouping = LedgerFeedDateGrouping(calendar: calendar, now: now)

        XCTAssertEqual(grouping.group(for: try Self.date(2026, 5, 21, 12, calendar: calendar)), .today)
        XCTAssertEqual(grouping.group(for: try Self.date(2026, 5, 20, 12, calendar: calendar)), .yesterday)
        XCTAssertEqual(grouping.group(for: try Self.date(2026, 5, 18, 12, calendar: calendar)), .thisWeek)
        XCTAssertEqual(grouping.group(for: try Self.date(2026, 5, 16, 12, calendar: calendar)), .earlier)
        XCTAssertEqual(grouping.group(for: try Self.date(2026, 6, 1, 12, calendar: calendar)), .upcoming)
    }

    func testDefaultTimelineVisibilityKeepsRecentDaysAndUpcomingOnly() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 21, 12, calendar: calendar)
        let visibility = TimelineDefaultVisibility(calendar: calendar, now: now)
        let today = try Self.section(day: Self.date(2026, 5, 21, 12, calendar: calendar), calendar: calendar, now: now)
        let yesterday = try Self.section(day: Self.date(2026, 5, 20, 12, calendar: calendar), calendar: calendar, now: now)
        let twoDaysAgo = try Self.section(day: Self.date(2026, 5, 19, 12, calendar: calendar), calendar: calendar, now: now)
        let earlierThisWeek = try Self.section(day: Self.date(2026, 5, 18, 12, calendar: calendar), calendar: calendar, now: now)
        let upcoming = try Self.section(day: Self.date(2026, 6, 1, 12, calendar: calendar), calendar: calendar, now: now)

        XCTAssertTrue(visibility.isVisibleByDefault(upcoming))
        XCTAssertTrue(visibility.isVisibleByDefault(today))
        XCTAssertTrue(visibility.isVisibleByDefault(yesterday))
        XCTAssertTrue(visibility.isVisibleByDefault(twoDaysAgo))
        XCTAssertFalse(visibility.isVisibleByDefault(earlierThisWeek))
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
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private static func section(day: Date, calendar: Calendar, now: Date) throws -> LedgerFeedSection {
        LedgerFeedSection(
            day: day,
            items: [
                .event(
                    LedgerEvent(
                        title: "Sample",
                        occurredAt: day,
                        rawText: "Sample",
                        createdAt: day
                    )
                )
            ],
            calendar: calendar,
            now: now
        )
    }
}
