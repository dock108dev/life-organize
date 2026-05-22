import Foundation

protocol AIServiceExtractionSending {
    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload
}

protocol AIServiceWebSending {
    func sendWebRequest(_ request: BackendWebRequest) async throws -> BackendWebResponse
}

protocol AIServiceHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AIServiceHTTPSession {}

struct AIServiceClient {
    let deviceToken: String?
    var baseURL = URL(string: "https://life.dock108.dev")!
    var session: any AIServiceHTTPSession = URLSession.shared

    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload {
        let response: BackendExtractionResponse = try await send(request, path: "/api/v1/extractions")
        return ExtractionResponsePayload(
            rawResponseText: response.rawResponseText,
            requestJSON: response.requestJSON,
            modelName: response.modelName
        )
    }

    func sendWebRequest(_ request: BackendWebRequest) async throws -> BackendWebResponse {
        try await send(request, path: "/api/v1/web-requests")
    }

    private func send<Request: Encodable, Response: Decodable>(_ request: Request, path: String) async throws -> Response {
        guard let deviceToken, !deviceToken.isEmpty else {
            throw AppError.missingServiceToken
        }

        guard let endpoint = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AppError.invalidResponse
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue(deviceToken, forHTTPHeaderField: "X-LifeOrganize-Device-Token")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw map(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw AppError.invalidResponse
            }
        case 401, 403:
            throw AppError.invalidServiceToken
        case 408:
            throw AppError.timeout
        case 429:
            throw AppError.rateLimited
        case 500..<600:
            throw AppError.serverError
        default:
            throw AppError.invalidResponse
        }
    }

    private func map(_ error: URLError) -> AppError {
        switch error.code {
        case .timedOut:
            .timeout
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            .networkUnavailable
        default:
            .networkUnavailable
        }
    }
}

extension AIServiceClient: AIServiceExtractionSending {}
extension AIServiceClient: AIServiceWebSending {}
