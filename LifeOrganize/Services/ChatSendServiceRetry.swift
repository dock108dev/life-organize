import Foundation
import SwiftData

@MainActor
extension ChatSendService {
    @discardableResult
    func retryExtraction(for message: ChatMessage) async throws -> ChatMessage? {
        guard message.role == .user else { return nil }

        let now = dateProvider.now
        message.extractionStatus = .extracting
        message.extractionAttemptCount += 1
        message.lastExtractionAttemptAt = now
        message.nextExtractionRetryAt = nil

        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        modelContext.insert(attempt)
        try modelContext.save()

        do {
            let payload = try await extractor.extractRawResponse(for: message.text, now: now)
            guard canWriteResults(for: dataGeneration) else {
                return nil
            }
            try complete(message: message, attempt: attempt, payload: payload)
        } catch {
            guard canWriteResults(for: dataGeneration) else {
                return nil
            }
            LocalDiagnosticEventStore().record(
                severity: .warning,
                category: "extraction",
                operation: "retry_extraction",
                error: error,
                affectedRecordID: message.id
            )
            try fail(message: message, attempt: attempt, error: error)
        }

        return message
    }
}
