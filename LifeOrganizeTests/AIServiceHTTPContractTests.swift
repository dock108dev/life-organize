import Foundation
import XCTest
@testable import LifeOrganize

final class AIServiceHTTPContractTests: XCTestCase {
    @MainActor
    func testAIServiceClientMapsHTTPAndTransportFailures() async throws {
        try await assertClientError(deviceToken: nil, expected: .missingServiceToken, expectedRequestCount: 0)
        try await assertClientError(deviceToken: "", expected: .missingServiceToken, expectedRequestCount: 0)
        try await assertClientError(deviceToken: "   ", expected: .missingServiceToken, expectedRequestCount: 0)
        try await assertClientError(statusCode: 401, expected: .invalidServiceToken)
        try await assertClientError(
            statusCode: 403,
            body: #"{"detail":{"code":"invalid_device_token","detail":"Device token was rejected."}}"#,
            expected: .invalidServiceToken
        )
        try await assertClientError(statusCode: 408, expected: .timeout)
        try await assertClientError(statusCode: 429, expected: .rateLimited)
        try await assertClientError(statusCode: 500, expected: .serverError)
        try await assertClientError(statusCode: 400, expected: .invalidResponse)
        try await assertClientError(statusCode: 422, fixture: "backend_validation_error.v1", expected: .invalidResponse)
        try await assertClientError(statusCode: 502, fixture: "backend_error_flat.v1", expected: .rateLimited)
        try await assertClientError(statusCode: 502, fixture: "backend_error_nested.v1", expected: .timeout)
        try await assertClientError(
            statusCode: 502,
            body: #"{"detail":{"code":"network_unavailable","detail":"OpenAI network request failed."}}"#,
            expected: .networkUnavailable
        )
        try await assertClientError(
            statusCode: 422,
            body: #"{"detail":{"code":"invalid_model_response","detail":"OpenAI response did not include output text."}}"#,
            expected: .invalidResponse
        )

        let client = AIServiceClient(deviceToken: "test-token", session: StubHTTPSession(error: URLError(.timedOut)))
        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected timeout.")
        } catch let error as AppError {
            XCTAssertEqual(error, .timeout)
        }

        let offlineClient = AIServiceClient(
            deviceToken: "test-token",
            session: StubHTTPSession(error: URLError(.notConnectedToInternet))
        )
        do {
            _ = try await offlineClient.sendExtraction(emptyBackendRequest())
            XCTFail("Expected network unavailable.")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkUnavailable)
        }
    }

    @MainActor
    func testAIServiceClientMapsMalformedSuccessBodyToInvalidResponse() async throws {
        let client = AIServiceClient(
            deviceToken: "test-token",
            session: StubHTTPSession(statusCode: 200, body: #"{"rawResponseText":42}"#)
        )

        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected invalid response.")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    @MainActor
    func testAIServiceClientRequestsUseRuntimeProductionDefaultEndpoints() async throws {
        let session = RecordingHTTPSession()
        let client = AIServiceClient(deviceToken: "test-token", session: session)

        _ = try await client.sendExtraction(emptyBackendRequest())
        _ = try await client.sendWebRequest(webAnswerBackendRequest())

        let extractionRequest = try XCTUnwrap(session.requests.first)
        let webRequest = try XCTUnwrap(session.requests.last)
        XCTAssertEqual(client.baseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
        XCTAssertEqual(extractionRequest.url?.absoluteString, "https://life.dock108.dev/api/v1/extractions")
        XCTAssertEqual(webRequest.url?.absoluteString, "https://life.dock108.dev/api/v1/web-requests")
    }

    @MainActor
    func testAIServiceClientUsesExplicitServiceBaseURLOverride() async throws {
        let session = RecordingHTTPSession()
        let overrideURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8787"))
        let client = AIServiceClient(deviceToken: "test-token", baseURL: overrideURL, session: session)

        _ = try await client.sendExtraction(emptyBackendRequest())
        _ = try await client.sendWebRequest(webAnswerBackendRequest())

        XCTAssertEqual(session.requests.map { $0.url?.absoluteString }, [
            "http://127.0.0.1:8787/api/v1/extractions",
            "http://127.0.0.1:8787/api/v1/web-requests"
        ])
    }

    @MainActor
    func testAIServiceClientRequestHeadersBodyAndTimeoutMatchBackendContract() async throws {
        let session = RecordingHTTPSession()
        let request = AIServiceMessageExtractionClient.backendRequest(
            for: #"Changed the "hallway" filter today."#,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let client = AIServiceClient(deviceToken: "test-token", session: session)

        _ = try await client.sendExtraction(request)

        let sentRequest = try XCTUnwrap(session.requests.first)
        let body = try XCTUnwrap(sentRequest.httpBody)
        let decodedBody = try JSONDecoder().decode(BackendExtractionRequest.self, from: body)
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertEqual(sentRequest.timeoutInterval, 30)
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "X-LifeOrganize-Device-Token"), "test-token")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(decodedBody, request)
    }

    @MainActor
    func testAIServiceClientWebRequestHeadersBodyAndTimeoutMatchBackendContract() async throws {
        let session = RecordingHTTPSession(body: #"{"assistantText":"Answer.","modelName":"test-backend"}"#)
        let request = webAnswerBackendRequest()
        let client = AIServiceClient(deviceToken: "test-token", session: session)

        _ = try await client.sendWebRequest(request)

        let sentRequest = try XCTUnwrap(session.requests.first)
        let body = try XCTUnwrap(sentRequest.httpBody)
        let decodedBody = try JSONDecoder().decode(BackendWebRequest.self, from: body)
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertEqual(sentRequest.timeoutInterval, 30)
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "X-LifeOrganize-Device-Token"), "test-token")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(decodedBody, request)
    }

    @MainActor
    private func assertClientError(
        deviceToken: String? = "test-token",
        statusCode: Int = 500,
        fixture: String? = nil,
        body: String? = nil,
        expected: AppError,
        expectedRequestCount: Int = 1
    ) async throws {
        let responseBody: String?
        if let fixture {
            responseBody = try XCTUnwrap(String(data: contractFixtureData(fixture), encoding: .utf8))
        } else {
            responseBody = body
        }
        let session = RecordingHTTPSession(
            statusCode: statusCode,
            body: responseBody ?? #"{"rawResponseText":"{}","requestJSON":null,"modelName":"test-backend"}"#
        )
        let client = AIServiceClient(deviceToken: deviceToken, session: session)
        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected \(expected).")
        } catch let error as AppError {
            XCTAssertEqual(error, expected)
        }
        XCTAssertEqual(session.requests.count, expectedRequestCount)
    }

    @MainActor
    private func emptyBackendRequest() -> BackendExtractionRequest {
        AIServiceMessageExtractionClient.backendRequest(
            for: "",
            now: fixedTestNow,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    @MainActor
    private func webAnswerBackendRequest() -> BackendWebRequest {
        AIServiceWebRequestClient.backendRequest(
            for: "Saturday best college football games with kickoff times.",
            mode: .answer,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
    }
}

private struct StubHTTPSession: AIServiceHTTPSession {
    var statusCode: Int?
    var error: Error?
    var body: Data

    init(statusCode: Int, body: String? = nil) {
        self.statusCode = statusCode
        self.error = nil
        self.body = Data(
            (body ?? #"{"rawResponseText":"{}","requestJSON":null,"modelName":"test-backend"}"#).utf8
        )
    }

    init(error: Error) {
        self.statusCode = nil
        self.error = error
        self.body = Data()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode ?? 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}

private final class RecordingHTTPSession: AIServiceHTTPSession {
    private(set) var requests: [URLRequest] = []
    var statusCode: Int
    var body: Data

    init(
        statusCode: Int = 200,
        body: String = #"{"rawResponseText":"{}","requestJSON":null,"modelName":"test-backend"}"#
    ) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
