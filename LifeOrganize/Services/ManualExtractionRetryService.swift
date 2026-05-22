import Foundation
import SwiftData

@MainActor
struct ManualExtractionRetryService {
    let modelContext: ModelContext
    let apiKeyStore: any APIKeyStore
    var dateProvider: any DateProvider = AppRuntimeConfiguration.current.dateProvider
    var dataGeneration: UUID?
    var isDataGenerationCurrent: (UUID) -> Bool = { _ in true }
    var extractorFactory: (any APIKeyStore) -> any MessageExtractionClient = { apiKeyStore in
        AppRuntimeConfiguration.current.messageExtractionClient(apiKeyStore: apiKeyStore)
    }

    func canRetry(_ message: ChatMessage) throws -> ManualExtractionRetryBlockedReason? {
        guard message.role == .user else {
            return .assistantOrSystemMessage
        }

        switch message.extractionStatus {
        case .pending, .extracting:
            return .alreadyExtracting
        case .succeeded:
            return .alreadySucceeded
        case .partiallySucceeded:
            return .createdRecordsExist
        case .notRequired:
            return .notRequired
        case .pendingKey, .pendingRetry, .failed:
            break
        case .failedNeedsReview, .needsReview:
            if try hasCreatedRecords(for: message) {
                return .createdRecordsExist
            }
        }

        return nil
    }

    @discardableResult
    func retry(_ message: ChatMessage) async throws -> ChatMessage? {
        if let blockedReason = try canRetry(message) {
            throw ManualExtractionRetryError.notRetryable(blockedReason)
        }

        guard try apiKeyStore.ensureDeviceToken().isEmpty == false else {
            throw ManualExtractionRetryError.missingAPIKey
        }

        let service = ChatSendService(
            modelContext: modelContext,
            extractor: extractorFactory(apiKeyStore),
            dateProvider: dateProvider,
            dataGeneration: dataGeneration,
            isDataGenerationCurrent: isDataGenerationCurrent
        )
        return try await service.retryExtraction(for: message)
    }

    private func hasCreatedRecords(for message: ChatMessage) throws -> Bool {
        let attempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        return attempts.contains { attempt in
            guard attempt.sourceMessage?.id == message.id else {
                return false
            }
            return !attempt.createdThingIDs.isEmpty ||
                !attempt.createdEventIDs.isEmpty ||
                !attempt.createdRuleIDs.isEmpty ||
                !attempt.createdNoteIDs.isEmpty
        }
    }
}

enum ManualExtractionRetryError: LocalizedError, Equatable {
    case missingAPIKey
    case notRetryable(ManualExtractionRetryBlockedReason)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "This entry is saved on this device. Connect to the AI service, then retry it."
        case .notRetryable(let reason):
            return reason.message
        }
    }
}

enum ManualExtractionRetryBlockedReason: Equatable {
    case assistantOrSystemMessage
    case alreadyExtracting
    case alreadySucceeded
    case notRequired
    case createdRecordsExist

    var message: String {
        switch self {
        case .assistantOrSystemMessage:
            return "Only your entries can be retried."
        case .alreadyExtracting:
            return "This entry is already being updated."
        case .alreadySucceeded:
            return "This entry is already connected across your timeline."
        case .notRequired:
            return "This entry is already saved as local text."
        case .createdRecordsExist:
            return "This entry already created saved records. Review or edit those records instead."
        }
    }
}
