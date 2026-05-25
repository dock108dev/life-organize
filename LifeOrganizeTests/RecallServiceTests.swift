import SwiftData
import XCTest
@testable import LifeOrganize

final class RecallServiceTests: XCTestCase {
    @MainActor
    func testRecallUsesFactualRuleNoteAndNoMatchLabels() {
        let now = fixedTestNow
        let domains = Thing(name: "Domains")
        let garageFilter = Thing(name: "Garage Filter")
        let rule = LedgerRule(
            title: "No buying domains",
            rawText: "No buying domains for 30 days.",
            startsAt: now,
            expiresAt: Date(timeIntervalSince1970: 1_802_592_000),
            createdAt: now,
            thing: domains
        )
        let note = LedgerNote(
            text: "Spare filters are in the utility closet.",
            createdAt: now,
            linkedThings: [garageFilter]
        )

        XCTAssertEqual(
            RecallService(now: now).answer(query: "Can I buy another domain?", things: [domains], rules: [rule]).answer,
            """
            Blocked.

            Active restriction:
            No buying domains until February 14, 2027.

            30 days left.
            """
        )
        XCTAssertEqual(
            RecallService(now: now).answer(query: "garage filter", things: [garageFilter], notes: [note]).answer,
            """
            Recent notes:
            - "Spare filters are in the utility closet."
            """
        )
        XCTAssertEqual(
            RecallService(now: now).answer(query: "monitor", things: [domains], rules: [rule], notes: [note]).answer,
            "No saved records found."
        )
    }

    @MainActor
    func testPriorNoteRecallPrioritizesUserAuthoredTextThenStructuredRecords() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = fixedTestNow
        let garageFilter = Thing(name: "Garage Filter")
        let note = LedgerNote(text: "Garage filter size is 16x20.", createdAt: older, linkedThings: [garageFilter])
        let message = ChatMessage(role: .user, text: "Garage filter spares are on shelf two.", createdAt: newer)
        let assistantMessage = ChatMessage(role: .assistant, text: "Garage filter assistant summary.", createdAt: newer)
        let event = LedgerEvent(
            title: "Replaced garage filter",
            occurredAt: newer,
            rawText: "Replaced garage filter.",
            createdAt: newer,
            thing: garageFilter
        )
        let rule = LedgerRule(
            title: "No buying garage filters",
            rawText: "No buying garage filters this month.",
            startsAt: newer,
            createdAt: newer,
            thing: garageFilter
        )

        let answer = RecallService(now: newer).answer(
            query: "What did I say about the garage filter?",
            things: [garageFilter],
            events: [event],
            rules: [rule],
            notes: [note],
            chatMessages: [message, assistantMessage]
        ).answer
        XCTAssertTrue(answer.contains("Local results:"))
        XCTAssertTrue(answer.contains("Garage filter size is 16x20."))
        XCTAssertTrue(answer.contains(#""Garage filter spares are on shelf two.""#))
        XCTAssertTrue(answer.contains("Replaced garage filter"))
        XCTAssertFalse(answer.contains("Note:"))
        XCTAssertFalse(answer.contains("Message:"))
        XCTAssertFalse(answer.contains("Event:"))
        XCTAssertFalse(answer.contains("Reminder:"))
        XCTAssertFalse(answer.contains("assistant summary"))
        XCTAssertLessThan(
            try XCTUnwrap(answer.range(of: "Garage filter size")?.lowerBound),
            try XCTUnwrap(answer.range(of: "Garage filter spares")?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(answer.range(of: "Garage filter spares")?.lowerBound),
            try XCTUnwrap(answer.range(of: "Replaced garage filter")?.lowerBound)
        )
    }

    @MainActor
    func testPriorNoteRecallNoResultNamesTopicFactually() {
        let answer = RecallService(now: fixedTestNow).answer(
            query: "What did I say about attic vents?",
            things: [],
            chatMessages: []
        ).answer

        XCTAssertEqual(answer, #"No saved records found for "attic vents"."#)
    }

    @MainActor
    func testChatLocalSearchUsesSharedProjectionWithoutSourceLabels() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let garageFilter = Thing(name: "Garage Filter", createdAt: now, updatedAt: now)
        let note = LedgerNote(text: "Garage filter size is 16x20.", createdAt: now, updatedAt: now, linkedThings: [garageFilter])
        let message = ChatMessage(role: .user, text: "Garage filter spares are on shelf two.", createdAt: now)
        context.insert(garageFilter)
        context.insert(note)
        context.insert(message)
        try context.save()

        let answer = try ChatRecallResponseService(modelContext: context, now: now).answer(
            for: ChatIntentClassification(intent: .localSearch, targetText: "garage filter")
        )
        XCTAssertTrue(answer.contains("Local results:"))
        XCTAssertTrue(answer.contains("Garage Filter"))
        XCTAssertTrue(answer.contains("Garage filter size is 16x20. - Related to Garage Filter"))
        XCTAssertTrue(answer.contains("Garage filter spares are on shelf two."))
        XCTAssertFalse(answer.contains("Thing:"))
        XCTAssertFalse(answer.contains("Note:"))
        XCTAssertFalse(answer.contains("Message:"))
        XCTAssertFalse(answer.contains("matched:"))
        XCTAssertFalse(answer.contains("linkedThingName"))
    }

    @MainActor
    func testRecallNoMatchCopyCoversReminderAndLocalSearchPaths() async throws {
        XCTAssertEqual(
            RecallService(now: fixedTestNow).answer(
                query: "Is there a reminder about HVAC filter?",
                things: [],
                rules: []
            ).answer,
            "No active reminder found for hvac filter."
        )

        let context = makeInMemoryModelContext()
        let answer = try ChatRecallResponseService(modelContext: context, now: fixedTestNow).answer(
            for: ChatIntentClassification(intent: .localSearch, targetText: "attic vents")
        )

        XCTAssertEqual(answer, #"No saved records found for "attic vents"."#)
    }

    @MainActor
    func testPermissionRecallUsesAliasesAndMentionsRecentExpiredRule() {
        let now = fixedTestNow
        let domains = Thing(name: "Domains", aliases: ["domain name"])
        let expiredRule = LedgerRule(
            title: "No buying domains",
            rawText: "No buying domains for 30 days.",
            startsAt: Date(timeIntervalSince1970: 1_790_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_799_913_600),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            thing: domains
        )

        XCTAssertEqual(
            RecallService(now: now).answer(
                query: "Can I buy another domain name?",
                things: [domains],
                rules: [expiredRule]
            ).answer,
            """
            No active restriction found for domain name.

            The most recent related restriction expired on January 14, 2027:
            No buying domains.
            """
        )
    }
}
