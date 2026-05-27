import XCTest
@testable import LifeOrganize

final class DateFormattingTests: XCTestCase {
    func testParseISODateTimeAcceptsPlainAndFractionalTimestamps() throws {
        let plain = try XCTUnwrap(DateFormatting.parseISODateTime("2026-05-26T14:15:16Z"))
        let fractional = try XCTUnwrap(DateFormatting.parseISODateTime("2026-05-26T14:15:16.123Z"))

        XCTAssertEqual(
            DateFormatting.isoDateTimeString(plain, timeZone: TimeZone(secondsFromGMT: 0)!),
            "2026-05-26T14:15:16Z"
        )
        XCTAssertEqual(
            DateFormatting.isoDateTimeString(fractional, timeZone: TimeZone(secondsFromGMT: 0)!),
            "2026-05-26T14:15:16Z"
        )
    }

    func testInclusiveDateRangeSummaryMatchesSingleDayAndCrossYearBehavior() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let sameDayStart = try XCTUnwrap(DateFormatting.parseISODateTime("2026-05-26T00:00:00Z"))
        let sameDayEnd = try XCTUnwrap(DateFormatting.parseISODateTime("2026-05-27T00:00:00Z"))
        let crossYearStart = try XCTUnwrap(DateFormatting.parseISODateTime("2026-12-31T00:00:00Z"))
        let crossYearEnd = try XCTUnwrap(DateFormatting.parseISODateTime("2027-01-02T00:00:00Z"))

        XCTAssertEqual(
            DateFormatting.inclusiveDateRangeSummary(
                start: sameDayStart,
                endExclusive: sameDayEnd,
                calendar: calendar
            ),
            "May 26"
        )
        XCTAssertEqual(
            DateFormatting.inclusiveDateRangeSummary(
                start: crossYearStart,
                endExclusive: crossYearEnd,
                calendar: calendar
            ),
            "Dec 31, 2026-Jan 1, 2027"
        )
    }
}
