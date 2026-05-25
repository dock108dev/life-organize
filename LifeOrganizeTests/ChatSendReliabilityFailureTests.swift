import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatSendReliabilityFailureTests: XCTestCase {
    @MainActor
    func testBackendFailuresPreserveRawMessageAndMapToLocalStates() async throws {
        try await assertSendFailure(
            AppError.serverError,
            expectedStatus: .pendingRetry,
            expectedCode: .serverError,
            expectedRetryDelay: 60
        )
        try await assertSendFailure(
            AppError.timeout,
            expectedStatus: .pendingRetry,
            expectedCode: .timeout,
            expectedRetryDelay: 60
        )
        try await assertSendFailure(
            AppError.missingServiceToken,
            expectedStatus: .pendingToken,
            expectedCode: .missingServiceToken,
            expectedRetryDelay: nil
        )
        try await assertSendFailure(
            AppError.invalidServiceToken,
            expectedStatus: .pendingToken,
            expectedCode: .invalidServiceToken,
            expectedRetryDelay: nil
        )
        try await assertSendFailure(
            AppError.rateLimited,
            expectedStatus: .pendingRetry,
            expectedCode: .rateLimited,
            expectedRetryDelay: 60
        )
        try await assertSendFailure(
            AppError.invalidResponse,
            expectedStatus: .failedNeedsReview,
            expectedCode: .schemaValidationFailed,
            expectedRetryDelay: nil
        )
        try await assertSendFailure(
            AppError.networkUnavailable,
            expectedStatus: .pendingRetry,
            expectedCode: .networkUnavailable,
            expectedRetryDelay: 60
        )
    }

    @MainActor
    func testRetryFailureIncrementsAttemptCountAndCapsRetryDelay() async throws {
        let context = makeInMemoryModelContext()
        let retryNow = fixedTestNow.addingTimeInterval(600)
        let message = ChatMessage(
            role: .user,
            text: "Changed filter today.",
            extractionStatus: .pendingRetry,
            extractionAttemptCount: 5,
            nextExtractionRetryAt: fixedTestNow
        )
        context.insert(message)
        try context.save()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.timeout),
            dateProvider: TestDateProvider(now: retryNow)
        )

        _ = try await service.retryExtraction(for: message)

        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.text, "Changed filter today.")
        XCTAssertEqual(message.extractionAttemptCount, 6)
        XCTAssertEqual(message.lastExtractionAttemptAt, retryNow)
        XCTAssertEqual(message.extractionStatus, .pendingRetry)
        XCTAssertEqual(message.extractionErrorCode, .timeout)
        XCTAssertEqual(message.nextExtractionRetryAt, retryNow.addingTimeInterval(1_920))
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.errorCode, .timeout)
        XCTAssertEqual(attempt.sourceMessage?.id, message.id)
    }

    @MainActor
    func testRetryDelayUsesExponentialBackoffWithCap() {
        let service = ChatSendService(
            modelContext: makeInMemoryModelContext(),
            extractor: StaticMessageExtractionClient(payload: ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON())),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        XCTAssertEqual(service.nextRetryDate(for: 0), fixedTestNow.addingTimeInterval(60))
        XCTAssertEqual(service.nextRetryDate(for: 1), fixedTestNow.addingTimeInterval(60))
        XCTAssertEqual(service.nextRetryDate(for: 2), fixedTestNow.addingTimeInterval(120))
        XCTAssertEqual(service.nextRetryDate(for: 6), fixedTestNow.addingTimeInterval(1_920))
        XCTAssertEqual(service.nextRetryDate(for: 7), fixedTestNow.addingTimeInterval(1_920))
    }

    @MainActor
    func testStaleNormalExtractionFailureKeepsLocalSaveWithoutRetrySideEffects() async throws {
        let context = makeInMemoryModelContext()
        let generation = UUID()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.timeout),
            dataGeneration: generation,
            isDataGenerationCurrent: { _ in false }
        )

        let result = try await service.send("Changed filter today.")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let message = try XCTUnwrap(messages.first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertNil(result)
        XCTAssertEqual(message.text, "Changed filter today.")
        XCTAssertEqual(message.extractionStatus, .extracting)
        XCTAssertNil(message.extractionErrorCode)
        XCTAssertNil(message.nextExtractionRetryAt)
        XCTAssertNil(message.rawLLMResponse)
        XCTAssertEqual(attempt.status, .pending)
        XCTAssertNil(attempt.completedAt)
        XCTAssertEqual(messages.filter { $0.role == .assistant }.count, 0)
    }

    @MainActor
    func testStaleRetryDoesNotCompleteOrCreateRecords() async throws {
        let context = makeInMemoryModelContext()
        let generation = UUID()
        let retryNow = fixedTestNow.addingTimeInterval(300)
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today.",
            extractionStatus: .pendingRetry,
            extractionAttemptCount: 1,
            nextExtractionRetryAt: fixedTestNow
        )
        context.insert(message)
        try context.save()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        events: [canonicalEvent("event_1", title: "Changed oil", thingRef: nil, occurredAt: "2027-01-15")]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: retryNow),
            dataGeneration: generation,
            isDataGenerationCurrent: { _ in false }
        )

        let result = try await service.retryExtraction(for: message)

        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())

        XCTAssertNil(result)
        XCTAssertEqual(message.extractionStatus, .extracting)
        XCTAssertEqual(message.extractionAttemptCount, 2)
        XCTAssertEqual(message.lastExtractionAttemptAt, retryNow)
        XCTAssertNil(message.nextExtractionRetryAt)
        XCTAssertNil(message.rawLLMResponse)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.status, .pending)
        XCTAssertNil(attempts.first?.completedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .assistant }.count, 0)
    }

    @MainActor
    private func assertSendFailure(
        _ error: AppError,
        expectedStatus: ExtractionStatus,
        expectedCode: ExtractionErrorCode,
        expectedRetryDelay: TimeInterval?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: error),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let message = try XCTUnwrap(messages.first { $0.role == .user }, file: file, line: line)
        let assistant = try XCTUnwrap(messages.first { $0.role == .assistant }, file: file, line: line)
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first, file: file, line: line)

        XCTAssertEqual(message.text, "Changed filter today.", file: file, line: line)
        XCTAssertEqual(message.extractionStatus, expectedStatus, file: file, line: line)
        XCTAssertEqual(message.extractionErrorCode, expectedCode, file: file, line: line)
        XCTAssertEqual(message.extractionAttemptCount, 1, file: file, line: line)
        XCTAssertEqual(message.lastExtractionAttemptAt, fixedTestNow, file: file, line: line)
        XCTAssertFalse(assistant.text.isEmpty, file: file, line: line)
        XCTAssertEqual(attempt.status, .failed, file: file, line: line)
        XCTAssertEqual(attempt.errorCode, expectedCode, file: file, line: line)
        XCTAssertEqual(attempt.sourceMessage?.id, message.id, file: file, line: line)
        XCTAssertTrue(attempt.normalizedJSONText.contains(expectedCode.rawValue), file: file, line: line)

        if let expectedRetryDelay {
            XCTAssertEqual(message.nextExtractionRetryAt, fixedTestNow.addingTimeInterval(expectedRetryDelay), file: file, line: line)
        } else {
            XCTAssertNil(message.nextExtractionRetryAt, file: file, line: line)
        }
    }
}
