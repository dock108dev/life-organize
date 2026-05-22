import XCTest
@testable import LifeOrganize

final class RecallContinuityTests: XCTestCase {
    @MainActor
    func testLastTimeRecallIncludesTypedEventMetadata() {
        let car = Thing(name: "Car")
        let event = LedgerEvent(
            title: "Logged car mileage",
            occurredAt: fixedTestNow,
            rawText: "Car is at 48,231 miles.",
            eventType: .measurement,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .mileage,
                    valueKind: .number,
                    numberValue: 48231,
                    unit: "mi",
                    sourceText: "48,231 miles"
                )
            ],
            thing: car
        )

        XCTAssertEqual(
            RecallService(now: fixedTestNow).answer(
                query: "When did I last log car mileage?",
                things: [car],
                events: [event]
            ).answer,
            """
            Last logged:
            Logged car mileage for Car on January 15, 2027. Mileage was 48,231 mi.
            """
        )
    }

    @MainActor
    func testEventSpanRecallAndSearchDoNotMatchSiblingSourceText() {
        let sourceMessage = ChatMessage(
            role: .user,
            text: "Bought cat food yesterday. Watered the fern today.",
            createdAt: fixedTestNow
        )
        let catFood = LedgerEvent(
            title: "Bought cat food",
            occurredAt: fixedTestNow,
            rawText: "Bought cat food yesterday.",
            sourceMessage: sourceMessage
        )
        let fern = LedgerEvent(
            title: "Watered fern",
            occurredAt: fixedTestNow.addingTimeInterval(86_400),
            rawText: "Watered the fern today.",
            sourceMessage: sourceMessage
        )
        let search = SearchService()

        XCTAssertEqual(
            RecallService(now: fixedTestNow).answer(
                query: "When did I last buy cat food?",
                things: [],
                events: [catFood, fern]
            ).answer,
            """
            Last logged:
            Bought cat food on January 15, 2027.
            """
        )
        XCTAssertEqual(
            search.search("cat food", in: search.records(things: [], events: [catFood, fern])).map(\.title),
            ["Bought cat food"]
        )
    }

    @MainActor
    func testReminderLookupSeparatesRestrictionsFromDateBasedReminders() throws {
        let domains = Thing(name: "Domains")
        let homeFilters = Thing(name: "Home Air Filters")
        let domainRestriction = LedgerRule(
            title: "No buying domains",
            ruleType: .restriction,
            rawText: "No buying domains for 30 days.",
            startsAt: fixedTestNow,
            expiresAt: Date(timeIntervalSince1970: 1_802_592_000),
            createdAt: fixedTestNow,
            thing: domains
        )
        let filterReminder = LedgerRule(
            title: "Replace HVAC filter",
            ruleType: .reminder,
            rawText: "Replace HVAC filter in 2 months.",
            startsAt: try XCTUnwrap(ExtractionService.parseDate("2027-03-15")),
            createdAt: fixedTestNow,
            thing: homeFilters
        )

        XCTAssertEqual(
            RecallService(now: fixedTestNow).answer(
                query: "Can I buy another domain?",
                things: [domains, homeFilters],
                rules: [domainRestriction, filterReminder]
            ).answer,
            """
            Blocked.

            Active restriction:
            No buying domains until February 14, 2027.

            30 days left.
            """
        )
        XCTAssertEqual(
            RecallService(now: fixedTestNow).answer(
                query: "Is there a reminder about HVAC filter?",
                things: [domains, homeFilters],
                rules: [domainRestriction, filterReminder]
            ).answer,
            """
            Coming Up:
            Replace HVAC filter.
            Due March 15, 2027
            """
        )
    }

    @MainActor
    func testLocalSearchUsesThingSeedsAndEventMetadata() {
        let car = Thing(name: "Car")
        let homeFilters = Thing(name: "Home Air Filters")
        let mileage = LedgerEvent(
            title: "Logged mileage",
            occurredAt: fixedTestNow,
            rawText: "Car is at 48,231 miles.",
            eventType: .measurement,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .mileage,
                    valueKind: .number,
                    numberValue: 48231,
                    unit: "mi",
                    sourceText: "48,231 miles"
                )
            ],
            thing: car
        )
        let filter = LedgerEvent(
            title: "Replaced home filter",
            occurredAt: fixedTestNow,
            rawText: "Replaced home filter.",
            thing: homeFilters
        )
        let search = SearchService()
        let records = search.records(things: [car, homeFilters], events: [mileage, filter])

        XCTAssertTrue(search.search("mileage", in: records).contains { $0.title == "Logged mileage" })
        XCTAssertTrue(search.search("48,231 miles", in: records).contains { $0.title == "Logged mileage" })
        XCTAssertTrue(search.search("HVAC filter", in: records).contains { $0.title == "Home Air Filters" })
        XCTAssertTrue(search.search("cabin filter", in: records).isEmpty)
        XCTAssertTrue(search.search("domain", in: search.records(things: [Thing(name: "Domains")])).contains { $0.title == "Domains" })
    }
}
