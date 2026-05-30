import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class ManualExtractionRetryServiceTests: XCTestCase {
    func testRetryRequiresUserMessage() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .assistant, text: "Saved.", extractionStatus: .failed)
        context.insert(message)

        let service = ManualExtractionRetryService(modelContext: context, deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"))

        XCTAssertEqual(try service.canRetry(message), .assistantOrSystemMessage)
    }

    func testRetryCreatesServiceTokenBeforeRetry() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .failed)
        context.insert(message)

        let tokenStore = InMemoryDeviceTokenStore()
        var service = ManualExtractionRetryService(modelContext: context, deviceTokenStore: tokenStore)
        service.extractorFactory = { store in
            XCTAssertNotNil(try? store.loadDeviceToken())
            return StaticMessageExtractionClient(payload: ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON()))
        }

        try await service.retry(message)

        XCTAssertNotNil(try tokenStore.loadDeviceToken())
    }

    func testBlockedReasonCopyUsesSavedEntryLanguage() {
        XCTAssertEqual(
            ManualExtractionRetryBlockedReason.alreadyExtracting.message,
            "This entry is already being updated."
        )
        XCTAssertEqual(
            ManualExtractionRetryBlockedReason.alreadySucceeded.message,
            "This entry is already connected across your timeline."
        )
        XCTAssertEqual(
            ManualExtractionRetryBlockedReason.notRequired.message,
            "This entry is already saved as local text."
        )
        XCTAssertEqual(
            ManualExtractionRetryBlockedReason.createdRecordsExist.message,
            "This entry already created saved items. Review or edit those items instead."
        )
    }

    func testRetryBlocksMessagesWithCreatedRecords() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .needsReview)
        let attempt = ExtractionAttempt(status: .failed, createdEventIDs: [UUID()], sourceMessage: message)
        context.insert(message)
        context.insert(attempt)

        let service = ManualExtractionRetryService(modelContext: context, deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"))

        XCTAssertEqual(try service.canRetry(message), .createdRecordsExist)
    }

    func testRetryCreatesNewAttemptAndKeepsPriorAttemptAudit() async throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore(token: "test-device-token")
        let message = ChatMessage(
            role: .user,
            text: "Changed oil.",
            extractionStatus: .failed,
            extractionError: "Network failed.",
            extractionErrorCode: .networkUnavailable,
            extractionAttemptCount: 1
        )
        let priorAttempt = ExtractionAttempt(
            status: .failed,
            rawResponseText: "prior raw response",
            errorCode: .networkUnavailable,
            errorMessage: "Network failed.",
            sourceMessage: message
        )
        context.insert(message)
        context.insert(priorAttempt)
        try context.save()

        var service = ManualExtractionRetryService(
            modelContext: context,
            deviceTokenStore: tokenStore,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        service.extractorFactory = { _ in
            ThrowingMessageExtractionClient(error: AppError.networkUnavailable)
        }

        try await service.retry(message)

        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(priorAttempt.rawResponseText, "prior raw response")
        XCTAssertEqual(message.extractionAttemptCount, 2)
        XCTAssertEqual(message.lastExtractionAttemptAt, fixedTestNow)
    }
}
