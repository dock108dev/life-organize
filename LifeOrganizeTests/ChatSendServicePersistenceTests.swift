import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatSendServicePersistenceTests: XCTestCase {
    @MainActor
    func testChatSendCommitsMessageAndPendingAttemptBeforeExtraction() async throws {
        let context = makeInMemoryModelContext()
        let extractor = InspectingExtractionClient { text, _ in
            XCTAssertEqual(text, "Changed oil today.")

            let messages = try context.fetch(FetchDescriptor<ChatMessage>())
            let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())

            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?.text, "Changed oil today.")
            XCTAssertEqual(messages.first?.extractionStatus, .extracting)
            XCTAssertEqual(attempts.count, 1)
            XCTAssertEqual(attempts.first?.status, .pending)
            XCTAssertFalse(attempts.first?.normalizedJSONText.isEmpty ?? true)

            return ExtractionResponsePayload(
                rawResponseText: canonicalExtractionJSON(
                    things: [canonicalThing("thing_1", name: "Oil Change", category: "vehicle")],
                    events: [
                        canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15")
                    ]
                ),
                requestJSON: #"{"model":"test"}"#,
                modelName: "test-model"
            )
        }
        let service = ChatSendService(
            modelContext: context,
            extractor: extractor,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("  Changed oil today.  ")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessage = try XCTUnwrap(messages.first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(messages.first { $0.role == .assistant })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(userMessage.extractionStatus, .succeeded)
        XCTAssertEqual(userMessage.extractionAttempts.first?.id, attempt.id)
        XCTAssertEqual(attempt.status, .succeeded)
        XCTAssertEqual(attempt.createdEventIDs.count, 1)
        XCTAssertEqual(attempt.createdThingIDs.count, 1)
        XCTAssertEqual(assistantMessage.text, "Event saved:\nChanged oil for Oil Change on January 15, 2027.")
    }

    @MainActor
    func testChatSendNotifiesAfterRawMessagePersistenceBeforeExtraction() async throws {
        let context = makeInMemoryModelContext()
        var persistedMessageID: UUID?
        let extractor = InspectingExtractionClient { _, _ in
            XCTAssertNotNil(persistedMessageID)
            return ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON())
        }
        let service = ChatSendService(
            modelContext: context,
            extractor: extractor,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed oil today.") { message in
            persistedMessageID = message.id
            XCTAssertEqual(message.text, "Changed oil today.")
            XCTAssertEqual(message.extractionStatus, .pending)
            XCTAssertEqual((try? context.fetch(FetchDescriptor<ChatMessage>()).count), 1)
            XCTAssertEqual((try? context.fetch(FetchDescriptor<ExtractionAttempt>()).count), 1)
        }

        XCTAssertNotNil(persistedMessageID)
    }

    @MainActor
    func testMissingServiceTokenKeepsRawMessageAndRecordsAttemptFailure() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.missingServiceToken),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("No buying domains for 30 days.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(userMessage.text, "No buying domains for 30 days.")
        XCTAssertEqual(userMessage.extractionStatus, .pendingToken)
        XCTAssertEqual(userMessage.extractionErrorCode, .missingServiceToken)
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.errorCode, .missingServiceToken)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant }?.text,
            "Saved on this device. Connect to the AI service when you want it organized across your timeline."
        )
        XCTAssertTrue(attempt.normalizedJSONText.contains("missing_service_token"))
    }

    @MainActor
    func testPendingTokenMessagesBecomeRetryableAfterTokenIsReady() throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore()
        let pendingMessage = ChatMessage(
            role: .user,
            text: "Book dentist.",
            extractionStatus: .pendingToken,
            extractionError: "AI service credential is missing.",
            extractionErrorCode: .missingServiceToken
        )
        let assistantMessage = ChatMessage(
            role: .assistant,
            text: "Saved locally.",
            extractionStatus: .notRequired
        )

        context.insert(pendingMessage)
        context.insert(assistantMessage)
        try context.save()
        try tokenStore.saveDeviceToken("unit-test-device-token")

        let changedCount = try PendingExtractionRetryService(
            modelContext: context,
            deviceTokenStore: tokenStore,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        .markPendingTokenMessagesRetryable()

        XCTAssertEqual(changedCount, 1)
        XCTAssertEqual(pendingMessage.extractionStatus, .pendingRetry)
        XCTAssertNil(pendingMessage.extractionErrorCode)
        XCTAssertNil(pendingMessage.extractionError)
        XCTAssertEqual(pendingMessage.nextExtractionRetryAt, fixedTestNow)
        XCTAssertEqual(assistantMessage.extractionStatus, .notRequired)
    }

    @MainActor
    func testRetryRecentPendingMessagesDoesNotAttemptWithoutSavedToken() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Changed filter.", extractionStatus: .pendingRetry)

        context.insert(message)
        try context.save()

        try await PendingExtractionRetryService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            extractorFactory: { _ in
                XCTFail("Extraction should not start without a service token.")
                return StaticMessageExtractionClient(
                    payload: ExtractionResponsePayload(rawResponseText: #"{"events":[]}"#)
                )
            }
        )
        .retryRecentPendingMessages()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
        XCTAssertEqual(message.extractionStatus, .pendingRetry)
    }

    @MainActor
    func testInvalidJSONStoresRawResponseAndReviewableEnvelope() async throws {
        let context = makeInMemoryModelContext()
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

        _ = try await service.send("Replaced HVAC filter.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(userMessage.rawLLMResponse, "not json")
        XCTAssertEqual(userMessage.extractionStatus, .failedNeedsReview)
        XCTAssertEqual(userMessage.extractionErrorCode, .invalidJSON)
        XCTAssertEqual(attempt.errorCode, .invalidJSON)
        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(rules.count, 0)
        XCTAssertEqual(notes.count, 0)
        XCTAssertEqual(things.count, 0)
        XCTAssertEqual(assistantMessage.text, "Saved for review.\nOpen the timeline entry to review the saved text.")
        XCTAssertTrue(attempt.normalizedJSONText.contains("invalid_json"))
    }

    @MainActor
    func testSingleMessageCreatesMultipleRecordsLinkedToSameSourceAndAttempt() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Oil Change", category: "vehicle"),
                            canonicalThing("thing_2", name: "Domains", category: "purchase"),
                            canonicalThing("thing_3", name: "Garage Filter", category: "home_maintenance")
                        ],
                        events: [
                            canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15"),
                            canonicalEvent("event_2", title: "Replaced filter", thingRef: "thing_3", occurredAt: "2027-01-15")
                        ],
                        rules: [
                            canonicalRule("rule_1", title: "No buying domains", thingRef: "thing_2", startsAt: "2027-01-15", expiresAt: "2027-02-14"),
                            canonicalRule("rule_2", title: "No new hardware", thingRef: nil, startsAt: "2027-01-15", expiresAt: "2027-07-01")
                        ],
                        notes: [
                            canonicalNote("note_1", text: "Garage filter is in the cabinet.", linkedThingRefs: ["thing_3"]),
                            canonicalNote("note_2", text: "Oil change receipt is in the glove box.", linkedThingRefs: ["thing_1"])
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed oil, replaced the garage filter, no domains, and remember the receipt.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(things.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.sourceMessage?.id == userMessage.id && $0.sourceExtractionRunID == attempt.id })
        XCTAssertTrue(rules.allSatisfy { $0.sourceMessage?.id == userMessage.id && $0.sourceExtractionRunID == attempt.id })
        XCTAssertTrue(notes.allSatisfy { $0.sourceMessage?.id == userMessage.id && $0.sourceExtractionRunID == attempt.id })
        XCTAssertTrue(things.allSatisfy { $0.sourceMessageIDs.contains(userMessage.id) })
        XCTAssertTrue(things.allSatisfy { $0.sourceExtractionAttemptIDs.contains(attempt.id) })
        XCTAssertEqual(attempt.createdEventIDs.count, 2)
        XCTAssertEqual(attempt.createdRuleIDs.count, 2)
        XCTAssertEqual(attempt.createdNoteIDs.count, 2)
        XCTAssertEqual(attempt.createdThingIDs.count, 3)
        XCTAssertEqual(
            assistantMessage.text,
            """
            Events saved:
            Changed oil for Oil Change on January 15, 2027.
            Replaced filter for Garage Filter on January 15, 2027.

            Restrictions saved:
            No buying domains until February 14, 2027.
            No new hardware until July 1, 2027.

            Notes saved:
            - "Garage filter is in the cabinet."
            - "Oil change receipt is in the glove box."
            """
        )
    }
}
