import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class PhaseThreeLedgerRegressionTests: XCTestCase {
    func testMessyTemporalInputFlowsThroughLedgerSurfacesWithoutDebugLeakage() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let input = "Changed furnace filter today. Next one due in 2 months."
        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send(input)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessages = messages.filter { $0.role == .user }
        let assistantMessages = messages.filter { $0.role == .assistant }
        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let reminders = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())

        let attempt = try XCTUnwrap(attempts.first)
        let event = try XCTUnwrap(events.first)
        let reminder = try XCTUnwrap(reminders.first)
        let thing = try XCTUnwrap(things.first)

        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(notes.count, 0)
        XCTAssertEqual(thing.name, "Home Air Filters")
        XCTAssertTrue(thing.aliases.contains("Furnace Filter"))

        XCTAssertEqual(event.title, "Changed furnace filter")
        XCTAssertEqual(event.eventType, .maintenance)
        XCTAssertEqual(event.thing?.id, thing.id)
        XCTAssertEqual(event.sourceMessage?.text, input)
        XCTAssertEqual(reminder.title, "Replace furnace filter")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, ExtractionService.parseDate("2027-03-15"))
        XCTAssertEqual(reminder.thing?.id, thing.id)
        XCTAssertEqual(reminder.sourceMessage?.text, input)
        XCTAssertTrue(links.contains { $0.relation == .sameMessage && $0.sourceID == event.id && $0.targetID == reminder.id })

        let feedProjection = LedgerFeedProjection(calendar: utcCalendar, now: now)
        let feedItems = feedProjection.items(messages: messages, events: events, reminders: reminders, notes: notes)
        XCTAssertEqual(feedItems.filter(\.isUserMessage).count, 0)
        XCTAssertTrue(feedItems.contains { $0.isEvent(event) })
        XCTAssertFalse(feedItems.contains { $0.isReminder(reminder) })
        let sections = feedProjection.sections(messages: messages, events: events, reminders: reminders, notes: notes)
        XCTAssertTrue(sections.contains { $0.group == .today && $0.items.contains { $0.isEvent(event) } })
        XCTAssertFalse(sections.contains { $0.group == .upcoming && $0.items.contains { $0.isReminder(reminder) } })

        let search = SearchService()
        let searchRecords = search.records(things: things, events: events, rules: reminders, notes: notes, messages: userMessages)
        let reminderSearch = search.search("date-based reminder", in: searchRecords)
        XCTAssertTrue(reminderSearch.contains { $0.title == "Replace furnace filter" && $0.sourceKind == .rule })
        XCTAssertTrue(search.search("furnace filter", in: searchRecords).contains { $0.title == "Changed furnace filter" })

        XCTAssertEqual(
            RecallService(now: now).answer(query: "When did I last change furnace filter?", things: things, events: events).answer,
            """
            Last logged:
            Changed furnace filter for Home Air Filters on January 15, 2027.
            """
        )
        let reminderAnswer = RecallService(now: now).answer(
            query: "When is my reminder for furnace filter?",
            things: things,
            rules: reminders
        ).answer
        XCTAssertTrue(reminderAnswer.contains("Coming Up:"))
        XCTAssertTrue(reminderAnswer.contains("Replace furnace filter."))
        XCTAssertTrue(reminderAnswer.contains("Due March 15, 2027"))

        let visibleFeedText = feedItems.map(Self.visibleText).joined(separator: "\n")
        let assistantText = assistantMessages.map(\.text).joined(separator: "\n")
        let normalDebugPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: false)
        let unlockedDebugPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: true)
        XCTAssertFalse(normalDebugPolicy.allowsExtractionDebugScreens)
        XCTAssertTrue(unlockedDebugPolicy.allowsExtractionDebugScreens)
        assertNoDebugTokens(in: visibleFeedText)
        assertNoDebugTokens(in: assistantText)

        XCTAssertEqual(attempt.modelName, "deterministic-extractor")
        XCTAssertEqual(attempt.requestJSON, #"{"mode":"deterministic"}"#)
        XCTAssertTrue(attempt.rawResponseText?.contains(#""schemaVersion": "1.0""#) == true)
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""clientID":"date_furnace_filter_next_due""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""ownerField":"startsAt""#))

        let export = try exportService(context: context).envelope()
        let exportedRun = try XCTUnwrap(export.records.extractionRuns.first)
        let exportedRule = try XCTUnwrap(export.records.rules.first)
        XCTAssertEqual(export.records.chatMessages.count, messages.count)
        XCTAssertEqual(export.records.entityLinks.count, links.count)
        XCTAssertEqual(exportedRun.model, "deterministic-extractor")
        XCTAssertEqual(exportedRun.requestJSON, #"{"mode":"deterministic"}"#)
        XCTAssertTrue(exportedRun.normalizedJSONText.contains(#""date_furnace_filter_next_due""#))
        XCTAssertEqual(exportedRule.title, "Replace furnace filter")
        XCTAssertEqual(exportedRule.continuityBehavior, LedgerContinuityBehavior.dateBasedReminder.rawValue)
        XCTAssertEqual(exportedRule.source.chatMessageId, userMessages.first?.id.uuidString)
        XCTAssertEqual(exportedRule.source.extractionRunId, attempt.id.uuidString)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func visibleText(_ item: LedgerFeedItem) -> String {
        let content = LedgerFeedRowContent(item: item)
        return [
            content.timestampText,
            content.sourceLabel,
            content.primaryText,
            content.secondaryText,
            content.detailText,
            content.linkedThingText
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }

    private func assertNoDebugTokens(in text: String, file: StaticString = #filePath, line: UInt = #line) {
        for token in [
            "deterministic-extractor",
            "requestJSON",
            "normalizedJSONText",
            "schemaVersion",
            "createdEntities",
            "date_furnace_filter_next_due",
            "invalid_json"
        ] {
            XCTAssertFalse(text.contains(token), "Visible text leaked \(token)", file: file, line: line)
        }
    }

    private func exportService(context: ModelContext) throws -> LocalJSONExportService {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalJSONExportService(
            modelContext: context,
            now: { fixedTestNow },
            calendar: calendar,
            timeZone: timeZone
        )
    }
}

private extension LedgerFeedItem {
    var isUserMessage: Bool {
        if case .message(let message) = self {
            return message.role == .user
        }
        return false
    }

    func isEvent(_ event: LedgerEvent) -> Bool {
        if case .event(let itemEvent) = self {
            return itemEvent.id == event.id
        }
        return false
    }

    func isReminder(_ reminder: LedgerRule) -> Bool {
        if case .reminder(let itemReminder) = self {
            return itemReminder.id == reminder.id
        }
        return false
    }
}
