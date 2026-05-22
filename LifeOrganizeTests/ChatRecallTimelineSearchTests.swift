import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatRecallTimelineSearchTests: XCTestCase {
    @MainActor
    func testChatLocalSearchReturnsTimelineAwareMixedResults() async throws {
        let context = makeInMemoryModelContext()
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 5, 20, 12, calendar: calendar)
        let car = Thing(name: "Honda Civic", aliases: ["daily driver"], createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 4, 9, calendar: calendar),
            rawText: "Changed oil at 40k miles.",
            createdAt: now,
            thing: car
        )
        let reminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            rawText: "Renew registration.",
            startsAt: try Self.date(2026, 5, 12, 10, calendar: calendar),
            createdAt: now,
            thing: car
        )
        let note = LedgerNote(
            text: "Insurance card is in the glove box.",
            createdAt: try Self.date(2026, 5, 8, 14, calendar: calendar),
            linkedThings: [car]
        )
        let message = ChatMessage(
            role: .user,
            text: "Car entry needs review.",
            createdAt: try Self.date(2026, 5, 5, 12, calendar: calendar)
        )

        context.insert(car)
        context.insert(event)
        context.insert(reminder)
        context.insert(note)
        context.insert(message)
        try context.save()

        let answer = try ChatRecallResponseService(modelContext: context, now: now).answer(
            for: ChatIntentClassification(intent: .localSearch, targetText: "May 2026")
        )

        XCTAssertTrue(answer.contains("Local results:"))
        XCTAssertTrue(answer.contains("May 2026"))
        XCTAssertTrue(answer.contains("Renew registration"))
        XCTAssertTrue(answer.contains("Insurance card is in the glove box."))
        XCTAssertTrue(answer.contains("Car entry needs review."))
    }

    @MainActor
    func testBroadPriorRecallUsesTimelineAwareRoughTimingSearch() throws {
        let calendar = Self.newYorkCalendar
        let now = try Self.date(2026, 6, 15, 12, calendar: calendar)
        let car = Thing(name: "Honda Civic", createdAt: try Self.date(2026, 1, 1, 8, calendar: calendar), updatedAt: now)
        let event = LedgerEvent(
            title: "Oil change",
            occurredAt: try Self.date(2026, 5, 4, 9, calendar: calendar),
            rawText: "Changed oil.",
            thing: car
        )
        let reminder = LedgerRule(
            title: "Renew registration",
            ruleType: .reminder,
            rawText: "Renew registration.",
            startsAt: try Self.date(2026, 5, 12, 10, calendar: calendar),
            createdAt: try Self.date(2026, 5, 1, 8, calendar: calendar),
            thing: car
        )
        let note = LedgerNote(
            text: "Insurance card is in the glove box.",
            createdAt: try Self.date(2026, 5, 8, 14, calendar: calendar),
            linkedThings: [car]
        )
        let message = ChatMessage(
            role: .user,
            text: "Car entry needs review.",
            createdAt: try Self.date(2026, 5, 5, 12, calendar: calendar)
        )

        let answer = RecallService(now: now).answer(
            query: "What did I say last month?",
            things: [car],
            events: [event],
            rules: [reminder],
            notes: [note],
            chatMessages: [message]
        ).answer

        XCTAssertTrue(answer.contains("Local results:"))
        XCTAssertTrue(answer.contains("Last Month"))
        XCTAssertTrue(answer.contains("Insurance card is in the glove box."))
        XCTAssertTrue(answer.contains("Car entry needs review."))
        XCTAssertTrue(answer.contains("Oil change"))
    }

    @MainActor
    func testBroadPriorRecallWithoutTopicFallsBackToRecentSavedText() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = fixedTestNow
        let thing = Thing(name: "Garage Filter")
        let note = LedgerNote(text: "Garage filter size is 16x20.", createdAt: older, linkedThings: [thing])
        let message = ChatMessage(role: .user, text: "Garage filter spares are on shelf two.", createdAt: newer)
        let event = LedgerEvent(title: "Replaced garage filter", occurredAt: newer, rawText: "Replaced garage filter.", thing: thing)

        let answer = RecallService(now: newer).answer(
            query: "What did I say?",
            things: [thing],
            events: [event],
            notes: [note],
            chatMessages: [message]
        ).answer

        XCTAssertTrue(answer.contains("Garage filter size is 16x20."))
        XCTAssertTrue(answer.contains("Garage filter spares are on shelf two."))
        XCTAssertTrue(answer.contains("Replaced garage filter"))
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
