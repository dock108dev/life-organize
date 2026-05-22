import SwiftData
import XCTest
@testable import LifeOrganize

final class SearchRecallServiceTests: XCTestCase {
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
    func testLocalSearchProjectionCoversLedgerRecordTypes() {
        let now = fixedTestNow
        let garageFilter = Thing(name: "Garage Filter", aliases: ["HVAC filter"], category: .maintenance, createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Replaced filter",
            occurredAt: now,
            rawText: "Replaced garage-filter.",
            createdAt: now,
            updatedAt: now,
            thing: garageFilter
        )
        let rule = LedgerRule(
            title: "No buying filters",
            rawText: "No buying garage filters this month.",
            startsAt: now,
            createdAt: now,
            updatedAt: now,
            thing: garageFilter
        )
        let note = LedgerNote(text: "Garage filter size is 16x20.", createdAt: now, updatedAt: now, linkedThings: [garageFilter])
        let message = ChatMessage(role: .user, text: "Garage filter spares are on shelf two.", createdAt: now)
        let search = SearchService()

        let results = search.search(
            "garage-filter",
            in: search.records(things: [garageFilter], events: [event], rules: [rule], notes: [note], messages: [message])
        )

        XCTAssertEqual(Set(results.map(\.sourceKind)), [.thing, .event, .rule, .note, .chatMessage])
        XCTAssertTrue(results.allSatisfy { !$0.matchedFields.isEmpty })
        XCTAssertEqual(results.first(where: { $0.sourceKind == .thing })?.linkedThingName, "Garage Filter")
        XCTAssertEqual(results.first(where: { $0.sourceKind == .event })?.subtitle, "Garage Filter")
        XCTAssertEqual(results.first(where: { $0.sourceKind == .chatMessage })?.title, "You")
    }

    @MainActor
    func testLocalSearchProjectionCoversEventMetadataAndReminderSemantics() throws {
        let now = fixedTestNow
        let dueDate = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let car = Thing(name: "Honda Civic", aliases: ["daily driver"], category: .maintenance, createdAt: now, updatedAt: now)
        let oilChange = LedgerEvent(
            title: "Oil change",
            occurredAt: now,
            rawText: "Changed oil at 40k miles at Valvoline for $89.95.",
            createdAt: now,
            updatedAt: now,
            note: "Synthetic oil service",
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 40_000, unit: "mi", sourceText: "40k miles"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Valvoline"),
                LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: 89.95, unit: "USD", sourceText: "$89.95")
            ],
            thing: car
        )
        let oilReminder = LedgerRule(
            title: "Replace oil filter",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace oil filter in March.",
            startsAt: dueDate,
            createdAt: now,
            updatedAt: now,
            thing: car
        )
        let purchaseRestriction = LedgerRule(
            title: "No oil additives",
            ruleType: .restriction,
            continuityBehavior: .timeLimitedWindow,
            rawText: "Do not buy oil additives until the next service.",
            startsAt: now,
            expiresAt: dueDate,
            createdAt: now,
            updatedAt: now,
            thing: car
        )
        let search = SearchService()
        let records = search.records(things: [car], events: [oilChange], rules: [oilReminder, purchaseRestriction])

        XCTAssertTrue(search.search("40k", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("mileage", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("oil", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("Valvoline", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("89.95", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("maintenance", in: records).contains { $0.title == "Oil change" })
        XCTAssertTrue(search.search("due", in: records).contains { $0.title == "Replace oil filter" })
        XCTAssertTrue(search.search("restriction", in: records).contains { $0.title == "No oil additives" })
        XCTAssertTrue(search.search("daily driver", in: records).contains { $0.title == "Replace oil filter" })
        let oilResult = try XCTUnwrap(search.search("Valvoline", in: records).first { $0.title == "Oil change" })
        XCTAssertEqual(oilResult.subtitle, "Honda Civic · Maintenance")
        XCTAssertTrue(oilResult.body?.contains("Mileage 40,000 mi") == true)
        XCTAssertTrue(oilResult.body?.contains("Vendor Valvoline") == true)
        XCTAssertTrue(oilResult.body?.contains("Amount $89.95") == true)
        XCTAssertFalse(oilResult.body?.contains("Changed oil at 40k miles") == true)
        XCTAssertFalse(oilResult.body?.contains("{") == true)
    }

    @MainActor
    func testEventSearchDisplayUsesOperationalMetadataInsteadOfRawSourceText() throws {
        let now = fixedTestNow
        let storage = Thing(name: "Storage Unit", createdAt: now, updatedAt: now)
        let renewal = LedgerEvent(
            title: "Renewed storage unit",
            occurredAt: now,
            rawText: "Raw renewal source with internal extraction wording.",
            createdAt: now,
            updatedAt: now,
            eventType: .renewal,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: 129, unit: "USD"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Boxwell Depot"),
                LedgerEventMetadataEntry(key: .dueDate, valueKind: .date, dateValue: "2027-03-15"),
                LedgerEventMetadataEntry(key: .sourceText, valueKind: .string, stringValue: "internal source fragment")
            ],
            thing: storage
        )
        let search = SearchService()

        let result = try XCTUnwrap(
            search.search("Boxwell", in: search.records(things: [storage], events: [renewal]))
                .first { $0.sourceKind == .event }
        )
        XCTAssertEqual(result.subtitle, "Storage Unit · Renewal")
        XCTAssertEqual(result.body, "Due Date Mar 15, 2027 · Vendor Boxwell Depot · Amount $129.00")
        XCTAssertFalse(result.body?.contains("Raw renewal source") == true)
        XCTAssertFalse(result.body?.contains("internal source") == true)
    }

    @MainActor
    func testLocalSearchRanksDurableTemporalRecordsAheadOfSourceMessages() throws {
        let now = fixedTestNow
        let oldDate = now.addingTimeInterval(-400 * 86_400)
        let dueSoon = now.addingTimeInterval(7 * 86_400)
        let car = Thing(
            name: "Car Maintenance",
            aliases: ["engine oil"],
            category: .vehicle,
            createdAt: oldDate,
            updatedAt: oldDate,
            lastEventAt: oldDate
        )
        let sourceMessage = ChatMessage(
            role: .user,
            text: "Changed oil at Costco at 40k miles.",
            createdAt: now
        )
        let oilChange = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil at Costco at 40k miles.",
            createdAt: now,
            updatedAt: now,
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 40_000, unit: "mi", sourceText: "40k miles"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Costco")
            ],
            thing: car,
            sourceMessage: sourceMessage
        )
        let oilReminder = LedgerRule(
            title: "Replace oil filter",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Replace oil filter next week.",
            startsAt: dueSoon,
            createdAt: now,
            updatedAt: now,
            thing: car,
            sourceMessage: sourceMessage
        )
        let search = SearchService()
        let records = search.records(things: [car], events: [oilChange], rules: [oilReminder], messages: [sourceMessage])
        let results = search.search(LocalSearchQuery(rawText: "oil", limit: 10, now: now), in: records)

        XCTAssertEqual(results.first?.sourceKind, .rule)
        let eventIndex = try XCTUnwrap(results.firstIndex { $0.sourceKind == .event })
        let thingIndex = try XCTUnwrap(results.firstIndex { $0.sourceKind == .thing })
        let messageIndex = try XCTUnwrap(results.firstIndex { $0.sourceKind == .chatMessage })
        let ruleIndex = try XCTUnwrap(results.firstIndex { $0.sourceKind == .rule })
        XCTAssertLessThan(eventIndex, thingIndex)
        XCTAssertLessThan(eventIndex, messageIndex)
        XCTAssertLessThan(ruleIndex, messageIndex)
    }

    @MainActor
    func testLocalSearchPhaseExamplesCoverStructuredRecordsAndHiddenSourceMessages() throws {
        let now = fixedTestNow
        let sourceMessage = ChatMessage(
            role: .user,
            text: "Changed oil at Costco at 40k miles, replaced filters, and signed up for bowling.",
            createdAt: now
        )
        let car = Thing(name: "Car", aliases: ["daily driver"], category: .vehicle, createdAt: now, updatedAt: now)
        let filters = Thing(name: "Furnace Filters", aliases: ["HVAC filters"], category: .maintenance, createdAt: now, updatedAt: now)
        let oilChange = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil at Costco at 40k miles.",
            createdAt: now,
            updatedAt: now,
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 40_000, unit: "mi", sourceText: "40k miles"),
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Costco")
            ],
            thing: car,
            sourceMessage: sourceMessage
        )
        let filterEvent = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now,
            rawText: "Replaced furnace filters.",
            createdAt: now,
            updatedAt: now,
            thing: filters,
            sourceMessage: sourceMessage
        )
        let filterReminder = LedgerRule(
            title: "Buy filters",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Buy filters next month.",
            startsAt: now.addingTimeInterval(30 * 86_400),
            createdAt: now,
            updatedAt: now,
            thing: filters,
            sourceMessage: sourceMessage
        )
        let bowlingReminder = LedgerRule(
            title: "Bowling league dues",
            ruleType: .reminder,
            rawText: "Pay bowling league dues.",
            startsAt: now,
            createdAt: now,
            updatedAt: now,
            sourceMessage: sourceMessage
        )
        let filterNote = LedgerNote(
            text: "Filters are in the utility closet.",
            createdAt: now,
            updatedAt: now,
            sourceMessage: sourceMessage,
            linkedThings: [filters]
        )
        let search = SearchService()
        let records = search.records(
            things: [car, filters],
            events: [oilChange, filterEvent],
            rules: [filterReminder, bowlingReminder],
            notes: [filterNote],
            messages: []
        )

        XCTAssertTrue(search.search("oil", in: records).contains { $0.navigationTarget == .eventDetail(oilChange.id) })
        XCTAssertTrue(search.search("Costco", in: records).contains { $0.navigationTarget == .eventDetail(oilChange.id) })
        XCTAssertTrue(search.search("40k", in: records).contains { $0.navigationTarget == .eventDetail(oilChange.id) })
        XCTAssertTrue(search.search("bowling", in: records).contains { $0.navigationTarget == .ruleDetail(bowlingReminder.id) })
        let filterKinds = Set(search.search("filters", in: records).map(\.sourceKind))
        XCTAssertTrue(filterKinds.isSuperset(of: [.thing, .event, .rule, .note]))
    }

    @MainActor
    func testLocalSearchDisplayContextExamplesAndNavigationTargetsStayProductFacing() throws {
        let now = fixedTestNow
        let filters = Thing(name: "Furnace Filters", aliases: ["HVAC filters"], createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Replaced filters",
            occurredAt: now,
            rawText: "Replaced furnace filters at Home Depot.",
            createdAt: now,
            updatedAt: now,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Home Depot")
            ],
            thing: filters
        )
        let reminder = LedgerRule(
            title: "Buy filters",
            ruleType: .reminder,
            rawText: "Buy filters next month.",
            startsAt: now.addingTimeInterval(30 * 86_400),
            createdAt: now,
            updatedAt: now,
            thing: filters
        )
        let note = LedgerNote(text: "Filters are in the utility closet.", createdAt: now, updatedAt: now, linkedThings: [filters])
        let message = ChatMessage(role: .user, text: "Filters are MERV 13.", createdAt: now)
        let search = SearchService()
        let results = search.search(
            "filters",
            in: search.records(things: [filters], events: [event], rules: [reminder], notes: [note], messages: [message])
        )

        XCTAssertEqual(results.first { $0.sourceKind == .thing }?.navigationTarget, .thingDetail(filters.id))
        XCTAssertEqual(results.first { $0.sourceKind == .event }?.navigationTarget, .eventDetail(event.id))
        XCTAssertEqual(results.first { $0.sourceKind == .rule }?.navigationTarget, .ruleDetail(reminder.id))
        XCTAssertEqual(results.first { $0.sourceKind == .note }?.navigationTarget, .noteDetail(note.id))
        XCTAssertEqual(results.first { $0.sourceKind == .chatMessage }?.navigationTarget, .chatMessage(message.id))
        XCTAssertEqual(results.first { $0.sourceKind == .event }?.productContextText, "Related to Furnace Filters")
        XCTAssertEqual(results.first { $0.sourceKind == .rule }?.productContextText, "For Furnace Filters")
        XCTAssertEqual(results.first { $0.sourceKind == .note }?.productContextText, "Related to Furnace Filters")
        XCTAssertFalse(results.compactMap(\.productContextText).joined(separator: " ").contains("matched"))
        XCTAssertFalse(results.compactMap(\.productContextText).joined(separator: " ").contains("metadata"))
        XCTAssertEqual(UnifiedSearchView.phaseThreeExampleQueries, ["oil last month", "May 2026", "HarborMart 40k", "upcoming"])
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.title, "Search")
        XCTAssertEqual(LedgerEmptyStateContent.searchLanding.body, "Look up a detail, date, place, or note.")
        XCTAssertEqual(
            LedgerEmptyStateContent.noSearchResults.body,
            "Try a shorter phrase or a different detail from the entry."
        )
        XCTAssertNil(LedgerEmptyStateContent.noSearchResults.secondaryBody)
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
