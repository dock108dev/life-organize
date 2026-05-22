import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LocalDataClearServiceTests: XCTestCase {
    func testClearDeletesLedgerRecordsReviewItemsAndKeepsSavedToken() throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore()
        let createdAt = fixedTestNow
        let message = ChatMessage(role: .user, text: "Changed oil.", createdAt: createdAt, extractionStatus: .succeeded)
        let attempt = ExtractionAttempt(sourceMessage: message)
        let thing = Thing(name: "Oil Change", createdAt: createdAt, updatedAt: createdAt)
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: createdAt,
            rawText: message.text,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .calendarInterval,
                    valueKind: .number,
                    numberValue: 90,
                    unit: "days",
                    sourceText: "every 90 days"
                )
            ],
            thing: thing,
            sourceMessage: message
        )
        let rule = LedgerRule(
            title: "Change oil",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            rawText: "Change oil every 90 days.",
            sourceMessage: message
        )
        let note = LedgerNote(text: "Use synthetic oil.", sourceMessage: message, linkedThings: [thing])
        let link = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .mentionsThing,
            createdBy: .system,
            sourceMessageID: message.id
        )
        let reviewItem = LedgerReviewItem(
            dedupeKey: "interval-reminder-\(event.id.uuidString)",
            kind: .intervalReminder,
            title: "Oil cadence is ready",
            detail: "Saved records show a possible cadence.",
            targetType: .thing,
            targetID: thing.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: "90 days")
            ],
            createdAt: createdAt,
            updatedAt: createdAt
        )

        try tokenStore.saveDeviceToken("unit-test-device-token")
        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(link)
        context.insert(reviewItem)
        try context.save()

        try LocalDataClearService(modelContext: context).clearLedgerData()

        try assertStoreIsEmpty(context)
        XCTAssertEqual(try tokenStore.loadDeviceToken(), "unit-test-device-token")
        XCTAssertTrue(LedgerFeedProjection().sections(messages: [], events: [], reminders: [], notes: []).isEmpty)
        XCTAssertTrue(SearchService().records(things: [], events: [], rules: [], notes: [], messages: []).isEmpty)
        XCTAssertTrue(try LedgerReviewQueueService(modelContext: context, deviceTokenStore: tokenStore).entries(from: []).isEmpty)
    }

    func testCancelledClearLeavesLocalDataAndSavedTokenUnchanged() throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore()
        let message = ChatMessage(role: .user, text: "Keep this.", extractionStatus: .notRequired)

        try tokenStore.saveDeviceToken("unit-test-device-token")
        context.insert(message)
        try context.save()

        var flow = SettingsClearDataFlow()
        flow.cancel()

        XCTAssertEqual(flow.step, .exportPrompt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).map(\.text), ["Keep this."])
        XCTAssertEqual(try tokenStore.loadDeviceToken(), "unit-test-device-token")
    }

    func testStaleExtractionCompletionAfterClearCannotRecreateRecords() async throws {
        let context = makeInMemoryModelContext()
        let sessionState = AppSessionState()
        let generation = sessionState.dataGeneration
        let extractor = ControlledExtractionClient()
        let extractionStarted = expectation(description: "extraction started")
        extractor.onStart = {
            extractionStarted.fulfill()
        }
        let service = ChatSendService(
            modelContext: context,
            extractor: extractor,
            dataGeneration: generation,
            isDataGenerationCurrent: sessionState.isCurrentDataGeneration
        )
        let sendTask = Task {
            try await service.send("Changed oil.")
        }

        await fulfillment(of: [extractionStarted], timeout: 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).first?.extractionStatus, .extracting)

        sessionState.invalidateInFlightDataWork()
        try LocalDataClearService(modelContext: context).clearLedgerData()
        sessionState.reloadAfterLocalDataClear()
        extractor.succeed(
            ExtractionResponsePayload(
                rawResponseText: canonicalExtractionJSON(
                    events: [
                        canonicalEvent("event_1", title: "Changed oil", thingRef: nil, occurredAt: "2027-01-15")
                    ]
                )
            )
        )

        let result = try await sendTask.value

        XCTAssertNil(result)
        try assertStoreIsEmpty(context)
    }

    private func assertStoreIsEmpty(_ context: ModelContext) throws {
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityLink>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 0)
    }
}

@MainActor
private final class ControlledExtractionClient: MessageExtractionClient {
    var onStart: (() -> Void)?
    private var continuation: CheckedContinuation<ExtractionResponsePayload, Error>?

    func extractRawResponse(for _: String, now _: Date) async throws -> ExtractionResponsePayload {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
    }

    func succeed(_ payload: ExtractionResponsePayload) {
        continuation?.resume(returning: payload)
        continuation = nil
    }
}
