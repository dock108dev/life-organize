extension AppRuntimeConfiguration {
    static func simulatedAIServiceError(from arguments: [String], isAutomationRuntime: Bool) -> AppError? {
        let prefix = "-simulate-ai-service-error="
        guard isAutomationRuntime,
              let rawValue = arguments.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count) else {
            return nil
        }

        switch String(rawValue) {
        case "missing-token":
            return .missingServiceToken
        case "network-unavailable":
            return .networkUnavailable
        case "timeout":
            return .timeout
        case "rate-limited":
            return .rateLimited
        case "server-error":
            return .serverError
        default:
            return nil
        }
    }
}
