import Foundation
import SwiftData

@MainActor
struct PendingExtractionRetryService {
    let modelContext: ModelContext
    let deviceTokenStore: any DeviceTokenStore
    var dateProvider: any DateProvider = SystemDateProvider()
    var dataGeneration: UUID?
    var isDataGenerationCurrent: (UUID) -> Bool = { _ in true }
    var extractorFactory: (String) -> any MessageExtractionClient = { token in
        AIServiceMessageExtractionClient(deviceToken: token)
    }

    @discardableResult
    func markPendingTokenMessagesRetryable() throws -> Int {
        _ = try deviceTokenStore.ensureDeviceToken()

        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let pendingMessages = messages.filter { message in
            message.role == .user && message.extractionStatus == .pendingToken
        }

        for message in pendingMessages {
            message.extractionStatus = .pendingRetry
            message.extractionErrorCode = nil
            message.extractionError = nil
            message.nextExtractionRetryAt = dateProvider.now
        }

        if !pendingMessages.isEmpty {
            try modelContext.save()
        }

        return pendingMessages.count
    }

    func retryRecentPendingMessages(limit: Int = 10) async throws {
        let deviceToken = try deviceTokenStore.ensureDeviceToken()

        let now = dateProvider.now
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
            .filter { message in
                guard message.role == .user else { return false }
                guard message.extractionStatus == .pendingRetry || message.extractionStatus == .pendingToken else {
                    return false
                }
                guard let nextRetryAt = message.nextExtractionRetryAt else { return true }
                return nextRetryAt <= now
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)

        for message in messages {
            let service = ChatSendService(
                modelContext: modelContext,
                extractor: extractorFactory(deviceToken),
                dateProvider: dateProvider,
                dataGeneration: dataGeneration,
                isDataGenerationCurrent: isDataGenerationCurrent
            )
            try await service.retryExtraction(for: message)
        }
    }
}
