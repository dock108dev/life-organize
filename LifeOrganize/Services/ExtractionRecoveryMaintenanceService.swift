import Foundation
import SwiftData

@MainActor
struct ExtractionRecoveryMaintenanceService {
    let modelContext: ModelContext
    var now: () -> Date = { Date() }
    var staleAfter: TimeInterval = 5 * 60

    @discardableResult
    func repairInterruptedEntries() throws -> Int {
        let cutoff = now().addingTimeInterval(-staleAfter)
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let interruptedMessages = messages.filter { message in
            guard message.role == .user else { return false }
            guard message.extractionStatus == .pending || message.extractionStatus == .extracting else {
                return false
            }
            return (message.lastExtractionAttemptAt ?? message.createdAt) <= cutoff
        }

        guard !interruptedMessages.isEmpty else {
            return 0
        }

        let attempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        for message in interruptedMessages {
            recover(message, attempts: attempts)
        }

        try modelContext.save()
        return interruptedMessages.count
    }

    private func recover(_ message: ChatMessage, attempts: [ExtractionAttempt]) {
        message.extractionStatus = .pendingRetry
        message.extractionErrorCode = .unknown
        message.extractionError = "This entry was interrupted before its timeline details were connected."
        message.nextExtractionRetryAt = now()

        let matchingAttempts = attempts
            .filter { $0.sourceMessage?.id == message.id && $0.status == .pending }
            .sorted { $0.startedAt < $1.startedAt }
        for attempt in matchingAttempts {
            attempt.status = .failed
            attempt.completedAt = now()
            attempt.errorCode = .unknown
            attempt.errorMessage = message.extractionError
            attempt.normalizedJSONText = ExtractionEnvelope.empty(
                warnings: [
                    ExtractionWarning(
                        code: ExtractionErrorCode.unknown.rawValue,
                        message: message.extractionError ?? "The saved entry can be retried."
                    )
                ]
            )
            .jsonStringOrEmpty()
        }
    }
}

private extension ExtractionEnvelope {
    func jsonStringOrEmpty() -> String {
        (try? jsonString()) ?? ExtractionEnvelope.emptyJSON()
    }
}
