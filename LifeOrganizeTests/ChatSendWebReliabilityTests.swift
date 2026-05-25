import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatSendWebReliabilityTests: XCTestCase {
    @MainActor
    func testWebImportPersistsMessageAndAttemptBeforeClientResolution() async throws {
        let context = makeInMemoryModelContext()
        var callbackRan = false
        var resolveRan = false
        let client = StaticWebRequestClient(
            result: WebRequestResult(
                assistantText: nil,
                extractionPayload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        events: [canonicalEvent("event_1", title: "Rutgers vs Iowa", thingRef: nil, occurredAt: "2027-09-05")]
                    )
                )
            ),
            onResolve: { _, mode, _ in
                resolveRan = true
                XCTAssertTrue(callbackRan)
                XCTAssertEqual(mode, .importRecords)
                let message = try? context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user }
                XCTAssertEqual(message?.extractionStatus, .extracting)
                XCTAssertEqual((try? context.fetch(FetchDescriptor<ExtractionAttempt>()).count), 1)
            }
        )
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: client,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Add all Rutgers football home games to my things.") { message in
            callbackRan = true
            XCTAssertEqual(message.extractionStatus, .pending)
            XCTAssertEqual((try? context.fetch(FetchDescriptor<ChatMessage>()).count), 1)
            XCTAssertEqual((try? context.fetch(FetchDescriptor<ExtractionAttempt>()).count), 1)
        }

        XCTAssertTrue(resolveRan)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
    }

    @MainActor
    func testWebModesWithoutClientStayLocalAndDoNotLoseRawMessages() async throws {
        let lookupContext = makeInMemoryModelContext()
        let lookupService = ChatSendService(
            modelContext: lookupContext,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await lookupService.send("Saturday I need the 5 best college football games to watch with kickoff times.")

        let lookupUser = try XCTUnwrap(try lookupContext.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let lookupAssistant = try XCTUnwrap(try lookupContext.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(lookupUser.text, "Saturday I need the 5 best college football games to watch with kickoff times.")
        XCTAssertEqual(lookupUser.extractionStatus, .notRequired)
        XCTAssertEqual(lookupAssistant.text, "Web results:\nConnect to the AI service to look up current web information.")
        XCTAssertEqual(try lookupContext.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)

        let importContext = makeInMemoryModelContext()
        let importService = ChatSendService(
            modelContext: importContext,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await importService.send("Add all Rutgers football home games to my things.")

        let importUser = try XCTUnwrap(try importContext.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let importAttempt = try XCTUnwrap(try importContext.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(importUser.text, "Add all Rutgers football home games to my things.")
        XCTAssertEqual(importUser.extractionStatus, .pendingToken)
        XCTAssertEqual(importUser.extractionErrorCode, .missingServiceToken)
        XCTAssertNil(importUser.nextExtractionRetryAt)
        XCTAssertEqual(importAttempt.status, .failed)
        XCTAssertEqual(importAttempt.errorCode, .missingServiceToken)
    }

    @MainActor
    func testWebImportWithoutPayloadFailsAttemptInsteadOfLeavingItIncomplete() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(assistantText: "No import payload was returned.", extractionPayload: nil)
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Add all Rutgers football home games to my things.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.text, "Add all Rutgers football home games to my things.")
        XCTAssertEqual(message.extractionStatus, .failedNeedsReview)
        XCTAssertEqual(message.extractionErrorCode, .schemaValidationFailed)
        XCTAssertNil(message.nextExtractionRetryAt)
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.errorCode, .schemaValidationFailed)
        XCTAssertNotNil(attempt.completedAt)
        XCTAssertTrue(attempt.normalizedJSONText.contains(ExtractionErrorCode.schemaValidationFailed.rawValue))
    }

    @MainActor
    func testStaleWebAnswerAndImportDoNotWriteOldAsyncResults() async throws {
        let generation = UUID()
        let answerContext = makeInMemoryModelContext()
        let answerService = ChatSendService(
            modelContext: answerContext,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(assistantText: "Old kickoff answer.", extractionPayload: nil)
            ),
            dataGeneration: generation,
            isDataGenerationCurrent: { _ in false }
        )

        let answerMessage = try await answerService.send(
            "Saturday I need the 5 best college football games to watch with kickoff times."
        )

        XCTAssertNotNil(answerMessage)
        XCTAssertEqual(try answerContext.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .assistant }.count, 0)
        XCTAssertEqual(answerMessage?.extractionStatus, .notRequired)

        let importContext = makeInMemoryModelContext()
        let importService = ChatSendService(
            modelContext: importContext,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(
                    assistantText: nil,
                    extractionPayload: ExtractionResponsePayload(
                        rawResponseText: canonicalExtractionJSON(
                            events: [canonicalEvent("event_1", title: "Rutgers vs Iowa", thingRef: nil, occurredAt: "2027-09-05")]
                        )
                    )
                )
            ),
            dataGeneration: generation,
            isDataGenerationCurrent: { _ in false }
        )

        let importMessage = try await importService.send("Add all Rutgers football home games to my things.")
        let importAttempt = try XCTUnwrap(try importContext.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertNotNil(importMessage)
        XCTAssertEqual(importMessage?.extractionStatus, .extracting)
        XCTAssertEqual(importAttempt.status, .pending)
        XCTAssertNil(importAttempt.completedAt)
        XCTAssertEqual(try importContext.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
        XCTAssertEqual(try importContext.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .assistant }.count, 0)
    }
}
