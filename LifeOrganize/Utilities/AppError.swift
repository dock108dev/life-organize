import Foundation

enum AppError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case networkUnavailable
    case timeout
    case rateLimited
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "AI service credential is missing."
        case .invalidAPIKey:
            "AI service credential was rejected."
        case .networkUnavailable:
            "The network is unavailable."
        case .timeout:
            "The AI service request timed out."
        case .rateLimited:
            "AI service rate limit reached."
        case .serverError:
            "AI service error."
        case .invalidResponse:
            "AI service returned an invalid response."
        }
    }
}
