import Foundation

enum WebRequestMode: Equatable {
    case answer
    case importRecords
}

struct WebRequestResult: Equatable {
    var assistantText: String?
    var extractionPayload: ExtractionResponsePayload?
}

@MainActor
protocol WebRequestClient {
    func resolve(_ text: String, mode: WebRequestMode, now: Date) async throws -> WebRequestResult
}

struct AIServiceWebRequestClient: WebRequestClient {
    private let deviceTokenProvider: () throws -> String?
    private let serviceBaseURL: URL
    var client: (any AIServiceWebSending)?

    init(deviceToken: String?, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any AIServiceWebSending)? = nil) {
        self.deviceTokenProvider = { deviceToken }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    init(deviceTokenStore: any DeviceTokenStore, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any AIServiceWebSending)? = nil) {
        self.deviceTokenProvider = { try deviceTokenStore.ensureDeviceToken() }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    func resolve(_ text: String, mode: WebRequestMode, now: Date) async throws -> WebRequestResult {
        let deviceToken = try deviceTokenProvider()
        guard let deviceToken, !deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.missingServiceToken
        }

        let request = Self.backendRequest(for: text, mode: mode, now: now)
        let requestData = try? Self.encoder.encode(request)
        let requestJSON = requestData.flatMap { String(data: $0, encoding: .utf8) }
        let response = try await (client ?? AIServiceClient(deviceToken: deviceToken, baseURL: serviceBaseURL)).sendWebRequest(request)

        switch mode {
        case .answer:
            return WebRequestResult(assistantText: response.assistantText, extractionPayload: nil)
        case .importRecords:
            return WebRequestResult(
                assistantText: nil,
                extractionPayload: ExtractionResponsePayload(
                    rawResponseText: response.rawResponseText ?? "",
                    requestJSON: response.requestJSON ?? requestJSON,
                    modelName: response.modelName
                )
            )
        }
    }

    static func backendRequest(for text: String, mode: WebRequestMode, now: Date, timeZone: TimeZone = .current) -> BackendWebRequest {
        BackendWebRequest(
            text: text,
            mode: mode == .answer ? "answer" : "importRecords",
            currentDate: DateFormatting.dateOnlyString(now, timeZone: timeZone),
            currentDateTime: DateFormatting.isoDateTimeString(now, timeZone: timeZone, formatOptions: [.withInternetDateTime, .withFractionalSeconds]),
            timezone: timeZone.identifier
        )
    }

    private static let encoder = JSONEncoder()
}

enum WebRequestContract {
    static let modelName = ExtractionContract.modelName
}
