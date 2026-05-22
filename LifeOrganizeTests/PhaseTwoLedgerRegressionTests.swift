import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class PhaseTwoLedgerRegressionTests: XCTestCase {
    func testRepresentativeLedgerFlowPropagatesAcrossSurfaces() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("Changed oil at 40k miles.")
        _ = try await service.send("Replaced HVAC filter.")
        _ = try await service.send("Replace air filter in 2 months.")
        _ = try await service.send("No buying domains for 30 days.")
        _ = try await service.send("Gate code is 4821.")
        _ = try await service.send("Find 40k")
        _ = try await service.send("When did I last change oil?")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessages = messages.filter { $0.role == .user }
        let assistantMessages = messages.filter { $0.role == .assistant }
        let extractionAttempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let reminders = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())

        XCTAssertEqual(userMessages.count, 7)
        XCTAssertEqual(assistantMessages.count, 7)
        XCTAssertEqual(extractionAttempts.count, 5)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(things.count, 5)
        XCTAssertTrue(extractionAttempts.allSatisfy { $0.status == .succeeded })

        let oilEvent = try XCTUnwrap(events.first { $0.title == "Changed oil" })
        XCTAssertEqual(oilEvent.thing?.name, "Car")
        XCTAssertEqual(oilEvent.eventType, .maintenance)
        XCTAssertEqual(oilEvent.metadataEntries.first?.key, .mileage)
        XCTAssertEqual(oilEvent.metadataEntries.first?.numberValue, 40_000)
        XCTAssertEqual(oilEvent.metadataEntries.first?.unit, "mi")

        let filterEvent = try XCTUnwrap(events.first { $0.title == "Replaced HVAC filter" })
        let filterThing = try XCTUnwrap(filterEvent.thing)
        XCTAssertEqual(filterThing.name, "Home Air Filters")

        let filterReminder = try XCTUnwrap(reminders.first { $0.title == "Replace air filters" })
        let reminderThing = try XCTUnwrap(filterReminder.thing)
        XCTAssertEqual(reminderThing.name, "Air Filter")
        XCTAssertEqual(filterReminder.ruleType, .reminder)
        XCTAssertEqual(filterReminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(filterReminder.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-03-15")))
        XCTAssertNil(filterReminder.expiresAt)

        let domainRestriction = try XCTUnwrap(reminders.first { $0.title == "No buying domains" })
        XCTAssertEqual(domainRestriction.ruleType, .restriction)
        XCTAssertEqual(domainRestriction.continuityBehavior, .timeLimitedWindow)
        XCTAssertEqual(domainRestriction.expiresAt, try XCTUnwrap(ExtractionService.parseDate("2027-02-14")))

        let gateNote = try XCTUnwrap(notes.first)
        XCTAssertEqual(gateNote.text, "Gate code is 4821.")
        XCTAssertEqual(gateNote.linkedThings.map(\.name), ["Gate"])

        XCTAssertEqual(links.filter { $0.relation == .extractedFrom }.count, 5)
        XCTAssertEqual(links.filter { $0.relation == .primaryThing }.count, 4)
        XCTAssertEqual(links.filter { $0.relation == .aboutThing }.count, 1)
        XCTAssertEqual(links.filter { $0.relation == .mentionsThing }.count, 5)
        XCTAssertTrue(links.allSatisfy { $0.sourceMessageID != nil })

        let feedItems = LedgerFeedProjection(calendar: utcCalendar, now: now).items(
            messages: messages,
            events: events,
            reminders: reminders,
            notes: notes
        )
        XCTAssertEqual(feedItems.filter(\.isUserMessage).count, 0)
        XCTAssertTrue(feedItems.contains { $0.isEvent(oilEvent) })
        XCTAssertFalse(feedItems.contains { $0.isReminder(filterReminder) })
        XCTAssertTrue(feedItems.contains { $0.isNote(gateNote) })

        let filterPreview = ThingPreviewSnapshot(thing: filterThing, now: now, calendar: utcCalendar)
        XCTAssertEqual(filterPreview.latestEventTitle, "Replaced HVAC filter")
        XCTAssertNil(filterPreview.upcomingReminderTitle)

        let reminderPreview = ThingPreviewSnapshot(thing: reminderThing, now: now, calendar: utcCalendar)
        XCTAssertEqual(reminderPreview.upcomingReminderTitle, "Replace air filters")
        XCTAssertEqual(reminderPreview.upcomingReminderRelativeDueText, "in 59 days")

        let filterDetail = ThingDetailSnapshot(thing: filterThing, now: now, calendar: utcCalendar)
        XCTAssertEqual(filterDetail.status, .quiet)
        XCTAssertEqual(filterDetail.events.map(\.title), ["Replaced HVAC filter"])

        let reminderDetail = ThingDetailSnapshot(thing: reminderThing, now: now, calendar: utcCalendar)
        XCTAssertEqual(reminderDetail.upcomingReminders.map(\.title), ["Replace air filters"])
        XCTAssertTrue(reminderDetail.inactiveReminders.isEmpty)

        let search = SearchService()
        let records = search.records(things: things, events: events, rules: reminders, notes: notes, messages: userMessages)
        XCTAssertTrue(search.search("40k", in: records).contains { $0.title == "Changed oil" && $0.sourceKind == .event })
        XCTAssertTrue(search.search("date-based reminder", in: records).contains { $0.title == "Replace air filters" })
        XCTAssertTrue(search.search("4821", in: records).contains { $0.title == "Gate code is 4821." })
        XCTAssertTrue(search.search("domains", in: records).contains { $0.title == "No buying domains" })

        XCTAssertEqual(
            RecallService(now: now).answer(query: "When did I last change oil?", things: things, events: events).answer,
            """
            Last logged:
            Changed oil for Car on January 15, 2027. Mileage was 40,000 mi.
            """
        )
        XCTAssertTrue(try XCTUnwrap(assistantMessages.last?.text).contains("Last logged:"))
        XCTAssertTrue(assistantMessages.contains { $0.text.contains("Local results") && $0.text.contains("Changed oil") })

        let export = try exportService(context: context).envelope()
        XCTAssertEqual(export.records.chatMessages.count, messages.count)
        XCTAssertEqual(export.records.extractionRuns.count, extractionAttempts.count)
        XCTAssertEqual(export.records.events.count, events.count)
        XCTAssertEqual(export.records.rules.count, reminders.count)
        XCTAssertEqual(export.records.notes.count, notes.count)
        XCTAssertEqual(export.records.entityLinks.count, links.count)
        XCTAssertTrue(export.records.events.contains { $0.title == "Changed oil" && $0.metadata.contains { $0.key == "mileage" } })
    }

    func testRetryDebugAndExportPreserveFailedAndSuccessfulAttempts() async throws {
        let context = makeInMemoryModelContext()
        let messageText = "Changed oil at 40k miles."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: "not json",
                    requestJSON: #"{"model":"test"}"#,
                    modelName: "test-model"
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(messageText)

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let failedAttempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        XCTAssertEqual(message.extractionStatus, .failedNeedsReview)
        XCTAssertEqual(failedAttempt.errorCode, .invalidJSON)
        XCTAssertTrue(failedAttempt.normalizedJSONText.contains("invalid_json"))

        var retryService = ManualExtractionRetryService(
            modelContext: context,
            apiKeyStore: InMemoryAPIKeyStore(key: "test-key"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        retryService.extractorFactory = { _ in DeterministicMessageExtractionClient() }

        try await retryService.retry(message)

        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>()).sorted { $0.startedAt < $1.startedAt }
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first?.id, failedAttempt.id)
        XCTAssertEqual(attempts.first?.status, .failed)
        XCTAssertEqual(attempts.first?.rawResponseText, "not json")
        XCTAssertEqual(attempts.last?.status, .succeeded)
        XCTAssertEqual(attempts.last?.createdEventIDs.count, 1)
        XCTAssertEqual(message.extractionStatus, .succeeded)
        XCTAssertEqual(message.extractionAttemptCount, 2)
        XCTAssertEqual(events.first?.metadataEntries.first?.key, .mileage)

        let export = try exportService(context: context).envelope()
        let exportedMessage = try XCTUnwrap(export.records.chatMessages.first { $0.text == messageText })
        XCTAssertEqual(exportedMessage.extractionRunIds.count, 2)
        XCTAssertEqual(exportedMessage.successfulExtractionRunIds.count, 1)
        XCTAssertEqual(exportedMessage.extractionState?.status, "succeeded")
        XCTAssertTrue(export.records.extractionRuns.contains { $0.error?.kind == "invalid_json" })
        XCTAssertTrue(export.records.extractionRuns.contains { $0.createdEntities.events.count == 1 })
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
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

    func isNote(_ note: LedgerNote) -> Bool {
        if case .note(let itemNote) = self {
            return itemNote.id == note.id
        }
        return false
    }
}
