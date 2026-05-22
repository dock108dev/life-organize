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

struct OpenAIWebRequestClient: WebRequestClient {
    private let deviceTokenProvider: () throws -> String?
    private let serviceBaseURL: URL
    var client: (any OpenAIWebSending)?

    init(apiKey: String?, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any OpenAIWebSending)? = nil) {
        self.deviceTokenProvider = { apiKey }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    init(apiKeyStore: any APIKeyStore, serviceBaseURL: URL = AppRuntimeConfiguration.defaultAIServiceBaseURL, client: (any OpenAIWebSending)? = nil) {
        self.deviceTokenProvider = { try apiKeyStore.ensureDeviceToken() }
        self.serviceBaseURL = serviceBaseURL
        self.client = client
    }

    func resolve(_ text: String, mode: WebRequestMode, now: Date) async throws -> WebRequestResult {
        let deviceToken = try deviceTokenProvider()
        guard let deviceToken, !deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.missingAPIKey
        }

        let request = Self.backendRequest(for: text, mode: mode, now: now)
        let requestData = try? Self.encoder.encode(request)
        let requestJSON = requestData.flatMap { String(data: $0, encoding: .utf8) }
        let response = try await (client ?? OpenAIClient(deviceToken: deviceToken, baseURL: serviceBaseURL)).sendWebRequest(request)

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

    static func request(for text: String, mode: WebRequestMode, now: Date, timeZone: TimeZone = .current) -> OpenAIWebRequest {
        let format: OpenAITextOptions?
        switch mode {
        case .answer:
            format = nil
        case .importRecords:
            format = OpenAITextOptions(
                format: OpenAIResponseFormat(
                    type: "json_schema",
                    name: OpenAIExtractionSchema.name,
                    strict: true,
                    schema: OpenAIExtractionSchema.value
                )
            )
        }

        return OpenAIWebRequest(
            model: WebRequestContract.modelName,
            input: [
                OpenAIInputMessage(
                    role: "system",
                    content: [
                        OpenAIInputContent(
                            type: "input_text",
                            text: instructions(for: mode)
                        ),
                    ]
                ),
                OpenAIInputMessage(
                    role: "user",
                    content: [
                        OpenAIInputContent(
                            type: "input_text",
                            text: OpenAIUserPayload.string(for: text, now: now, timeZone: timeZone)
                        ),
                    ]
                ),
            ],
            tools: [
                OpenAIWebTool(
                    type: "web_search",
                    userLocation: OpenAIWebUserLocation(
                        type: "approximate",
                        country: "US",
                        region: nil,
                        city: nil,
                        timezone: timeZone.identifier
                    )
                ),
            ],
            include: ["web_search_call.action.sources"],
            toolChoice: "auto",
            text: format
        )
    }

    private static func instructions(for mode: WebRequestMode) -> String {
        switch mode {
        case .answer:
            return """
            Answer the user's web-backed ledger question using current web results.
            Keep the answer concise and factual. Include dates, times, and time zones when relevant.
            Include source URLs in the answer text. Do not provide betting advice.
            """
        case .importRecords:
            return """
            Use web search to find the requested public schedule or dated facts, then return only JSON
            matching the provided ledger extraction schema. Do not include prose outside JSON.
            Create Things for stable subjects, Events for dated games or appointments, and reminder Rules
            for user-stated preparation times such as tailgating before a game.
            Resolve all dates using the supplied current date and timezone. Use null only when the source
            does not provide a date or kickoff time. Include source URLs in rawText, notes, or metadata
            sourceText when possible.
            """
        }
    }

    private static let encoder = JSONEncoder()
}

enum WebRequestContract {
    static let modelName = ExtractionContract.modelName
}
