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
        if case AppError.missingServiceToken = error {
            return (
                .pendingToken,
                .missingServiceToken,
                formatter.extractionUnavailable(
                    reason: "The service is unavailable. This will stay saved locally."
                ),
                "Service credential could not be prepared."
            )
        }
        if case AppError.invalidServiceToken = error {
            return (
                .pendingToken,
                .invalidServiceToken,
                formatter.extractionUnavailable(reason: "The service rejected this device. This will stay saved locally."),
                "Service credential was rejected."
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
                "The service request timed out."
            )
        }
        if case AppError.rateLimited = error {
            return (
                .pendingRetry,
                .rateLimited,
                formatter.delayedOrganization("Timeline connections are delayed and will retry."),
                "Service rate limit reached."
            )
        }
        if case AppError.serverError = error {
            return (
                .pendingRetry,
                .serverError,
                formatter.delayedOrganization("Timeline connections will retry later."),
                "Service error."
            )
        }
        if case AppError.invalidResponse = error {
            return (
                .failedNeedsReview,
                .schemaValidationFailed,
                formatter.extractionFailed(),
                "Service returned an invalid response."
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
