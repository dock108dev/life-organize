import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatIntentRoutingTests: XCTestCase {
    @MainActor
    func testPureLastTimeLookupPersistsLedgerMessagesWithoutExtractionSideEffects() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let oilChange = Thing(name: "Oil Change")
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil today.",
            createdAt: now,
            thing: oilChange
        )
        context.insert(oilChange)
        context.insert(event)
        try context.save()

        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("When did I last change oil?")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessage = try XCTUnwrap(messages.first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(messages.first { $0.role == .assistant })

        XCTAssertEqual(userMessage.extractionStatus, .notRequired)
        XCTAssertEqual(assistantMessage.extractionStatus, .notRequired)
        XCTAssertEqual(
            assistantMessage.text,
            """
            Last logged:
            Changed oil for Oil Change on January 15, 2027.
            """
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 1)
    }

    @MainActor
    func testUnsupportedPromptGetsBoundaryMessageWithoutExtractionAttempt() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError)
        )

        _ = try await service.send("What should I do with my life?")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(userMessage.extractionStatus, .notRequired)
        XCTAssertEqual(assistantMessage.text, "Add to Timeline, search saved records, or check Carry Forward.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
    }

    @MainActor
    func testTodayAgendaLookupAnswersActiveRemindersOnly() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let dueToday = LedgerRule(
            title: "Pay rent",
            ruleType: .reminder,
            rawText: "Pay rent today.",
            startsAt: now
        )
        let distantReminder = LedgerRule(
            title: "No bowling",
            ruleType: .reminder,
            rawText: "No bowling next year.",
            startsAt: now.addingTimeInterval(180 * 86_400)
        )
        context.insert(dueToday)
        context.insert(distantReminder)
        try context.save()

        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("What do I have to do today?")

        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })
        XCTAssertEqual(
            assistantMessage.text,
            """
            Today:
            - Pay rent. Due today.
            """
        )
        XCTAssertFalse(assistantMessage.text.contains("No bowling"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
    }

    @MainActor
    func testWebLookupPersistsCitedAnswerWithoutExtractionAttempt() async throws {
        let context = makeInMemoryModelContext()
        var observedMode: WebRequestMode?
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(
                    assistantText: "1. Ohio State at Michigan, 12:00 PM ET. Source: https://example.com/schedule",
                    extractionPayload: nil
                ),
                onResolve: { _, mode, _ in observedMode = mode }
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Saturday I need the 5 best college football games to watch with kickoff times.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(observedMode, .answer)
        XCTAssertEqual(userMessage.extractionStatus, .notRequired)
        XCTAssertEqual(assistantMessage.text, "Web results:\n1. Ohio State at Michigan, 12:00 PM ET. Source: https://example.com/schedule")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
    }

    @MainActor
    func testWebImportCreatesDatedGameAndTailgateReminder() async throws {
        let context = makeInMemoryModelContext()
        let kickoff = DateFormatting.isoDateTimeString(Date(timeIntervalSince1970: 1_791_036_000), timeZone: TimeZone(secondsFromGMT: 0)!)
        let tailgate = DateFormatting.isoDateTimeString(Date(timeIntervalSince1970: 1_791_025_200), timeZone: TimeZone(secondsFromGMT: 0)!)
        let payload = canonicalExtractionJSON(
            things: [canonicalThing("thing_rutgers", name: "Rutgers Football", category: "sports")],
            events: [
                canonicalEvent(
                    "event_rutgers_iowa",
                    title: "Rutgers vs Iowa",
                    thingRef: "thing_rutgers",
                    occurredAt: kickoff,
                    eventType: "appointment",
                    rawText: "Rutgers home game source: https://scarletknights.com/sports/football/schedule/2026"
                ),
            ],
            rules: [
                canonicalRule(
                    "rule_tailgate_iowa",
                    title: "Tailgate for Rutgers vs Iowa",
                    thingRef: "thing_rutgers",
                    startsAt: tailgate,
                    expiresAt: nil,
                    ruleType: "reminder",
                    rawText: "Tailgate starts 3 hours before kickoff."
                ),
            ]
        )
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(
                    assistantText: nil,
                    extractionPayload: ExtractionResponsePayload(
                        rawResponseText: payload,
                        requestJSON: #"{"tools":[{"type":"web_search"}]}"#,
                        modelName: "test-web"
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Add all Rutgers football home games to my things. I tailgate starting 3 hours before.")

        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })
        let event = try XCTUnwrap(events.first)
        let rule = try XCTUnwrap(rules.first)

        XCTAssertEqual(event.title, "Rutgers vs Iowa")
        XCTAssertEqual(event.thing?.name, "Rutgers Football")
        XCTAssertEqual(rule.title, "Tailgate for Rutgers vs Iowa")
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.thing?.name, "Rutgers Football")
        XCTAssertEqual(attempts.first?.modelName, "test-web")
        XCTAssertTrue(assistantMessage.text.contains("Event saved:"))
        XCTAssertTrue(assistantMessage.text.contains("Reminder saved:"))
    }

    @MainActor
    func testLastTimeLookupWithRuleLikeTargetUsesEventsOnly() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let domains = Thing(name: "Domains")
        let event = LedgerEvent(
            title: "Bought domain",
            occurredAt: now,
            rawText: "Bought a domain.",
            thing: domains
        )
        let rule = LedgerRule(
            title: "No buying domains",
            rawText: "No buying domains for 30 days.",
            startsAt: now,
            expiresAt: Date(timeIntervalSince1970: 1_802_592_000),
            thing: domains
        )

        context.insert(domains)
        context.insert(event)
        context.insert(rule)
        try context.save()

        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("When did I last buy a domain?")

        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })
        XCTAssertEqual(
            assistantMessage.text,
            """
            Last logged:
            Bought domain for Domains on January 15, 2027.
            """
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
    }

    @MainActor
    func testMixedExtractionCanCreateRecordsAndAnswerRecallQuery() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        messageType: "mixed",
                        things: [canonicalThing("thing_1", name: "Oil Change", category: "vehicle")],
                        events: [canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15")],
                        recallQueries: [
                            canonicalRecallQuery("query_1", queryType: "last_time", thingName: "Oil Change", rawText: "when did I last change oil"),
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("Changed oil today, and when did I last change oil?")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(userMessage.extractionStatus, .succeeded)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
        XCTAssertEqual(
            assistantMessage.text,
            """
            Event saved:
            Changed oil for Oil Change on January 15, 2027.

            Last logged:
            Changed oil for Oil Change on January 15, 2027.
            """
        )
    }
}
