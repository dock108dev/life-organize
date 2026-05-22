import Foundation

@MainActor
extension ChatSendService {
    func mapExtractionError(_ error: Error) -> (
        status: ExtractionStatus,
        code: ExtractionErrorCode,
        userMessage: String,
        detail: String
    ) {
        let formatter = ChatResponseFormatter()
        if case AppError.missingAPIKey = error {
            return (
                .pendingKey,
                .missingAPIKey,
                formatter.extractionUnavailable(
                    reason: "Connect to the AI service when you want it organized across your timeline."
                ),
                "AI service credential is missing."
            )
        }
        if case AppError.invalidAPIKey = error {
            return (
                .pendingKey,
                .invalidAPIKey,
                formatter.extractionUnavailable(reason: "Reconnect the AI service in Settings."),
                "AI service credential was rejected."
            )
        }
        if case AppError.networkUnavailable = error {
            return (
                .pendingRetry,
                .networkUnavailable,
                formatter.delayedOrganization("Timeline connections will retry when the connection works."),
                "The network is unavailable."
            )
        }
        if case AppError.timeout = error {
            return (
                .pendingRetry,
                .timeout,
                formatter.delayedOrganization("Timeline connections will retry when the connection works."),
                "The AI service request timed out."
            )
        }
        if case AppError.rateLimited = error {
            return (
                .pendingRetry,
                .rateLimited,
                formatter.delayedOrganization("Timeline connections are delayed and will retry."),
                "AI service rate limit reached."
            )
        }
        if case AppError.serverError = error {
            return (
                .pendingRetry,
                .serverError,
                formatter.delayedOrganization("Timeline connections will retry later."),
                "AI service error."
            )
        }

        let detail = error.localizedDescription
        return (
            .pendingRetry,
            .unknown,
            formatter.delayedOrganization("Timeline connections will retry later."),
            detail
        )
    }

    func nextRetryDate(for attemptCount: Int) -> Date {
        let exponent = max(0, min(attemptCount - 1, 5))
        let delay = TimeInterval(60 * (1 << exponent))
        return dateProvider.now.addingTimeInterval(delay)
    }
}
