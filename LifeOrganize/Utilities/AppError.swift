import Foundation

enum AppError: LocalizedError, Equatable {
    case missingServiceToken
    case invalidServiceToken
    case networkUnavailable
    case timeout
    case rateLimited
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingServiceToken:
            "Service credential could not be prepared."
        case .invalidServiceToken:
            "Service credential was rejected."
        case .networkUnavailable:
            "The network is unavailable."
        case .timeout:
            "The service request timed out."
        case .rateLimited:
            "Service rate limit reached."
        case .serverError:
            "Service error."
        case .invalidResponse:
            "Service returned an invalid response."
        }
    }
}
