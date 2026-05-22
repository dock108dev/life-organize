import Foundation
import SwiftData
import XCTest
@testable import LifeOrganize

final class AIServiceClientTests: XCTestCase {
    @MainActor
    func testExtractionRequestCarriesBackendDateContextOnly() throws {
        let now = fixedTestNow
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let request = AIServiceMessageExtractionClient.backendRequest(
            for: #"Changed the "hallway" filter today."#,
            now: now,
            timeZone: timeZone
        )
        let requestData = try JSONEncoder().encode(request)
        let requestText = try XCTUnwrap(String(data: requestData, encoding: .utf8))

        XCTAssertEqual(request.text, #"Changed the "hallway" filter today."#)
        XCTAssertEqual(request.currentDate, "2027-01-15")
        XCTAssertEqual(request.timezone, "America/New_York")
        XCTAssertEqual(request.schemaVersion, ExtractionContract.schemaVersion)
        XCTAssertFalse(requestText.contains("json_schema"))
        XCTAssertFalse(requestText.contains("web_search"))
    }

    @MainActor
    func testWebLookupRequestCarriesBackendModeOnly() throws {
        let request = AIServiceWebRequestClient.backendRequest(
            for: "Saturday best college football games with kickoff times.",
            mode: .answer,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(request), encoding: .utf8))

        XCTAssertEqual(request.mode, "answer")
        XCTAssertEqual(request.timezone, "America/New_York")
        XCTAssertFalse(encoded.contains("web_search"))
        XCTAssertFalse(encoded.contains("source URLs"))
    }

    @MainActor
    func testWebImportRequestCarriesBackendImportModeOnly() throws {
        let request = AIServiceWebRequestClient.backendRequest(
            for: "Add all Rutgers football home games for 2026.",
            mode: .importRecords,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(request), encoding: .utf8))

        XCTAssertEqual(request.mode, "importRecords")
        XCTAssertEqual(request.currentDate, "2027-01-15")
        XCTAssertFalse(encoded.contains("json_schema"))
        XCTAssertFalse(encoded.contains("web_search"))
    }

    func testLegacyDirectProviderDTOsAreAbsent() {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let deletedPaths = [
            "LifeOrganize/DTOs/OpenAIRequest.swift",
            "LifeOrganize/DTOs/OpenAIResponse.swift",
            "LifeOrganize/DTOs/OpenAIExtractionSchema.swift",
            "LifeOrganize/Services/OpenAIUserPayload.swift"
        ]

        for path in deletedPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appending(path: path).path), path)
        }
    }

    @MainActor
    func testMissingKeySkipsAIServiceClientAndReturnsPendingTokenThroughSendFlow() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: AIServiceMessageExtractionClient(
                deviceToken: "",
                client: FailingAIServiceSender()
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.extractionStatus, .pendingToken)
        XCTAssertEqual(message.extractionErrorCode, .missingServiceToken)
        XCTAssertNil(message.nextExtractionRetryAt)
        XCTAssertEqual(message.extractionAttemptCount, 1)
        XCTAssertEqual(message.lastExtractionAttemptAt, fixedTestNow)
        XCTAssertEqual(attempt.errorCode, .missingServiceToken)
    }

    @MainActor
    func testRetryableAIServiceErrorsRecordRetryMetadata() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.rateLimited),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("No buying domains for 30 days.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.extractionStatus, .pendingRetry)
        XCTAssertEqual(message.extractionErrorCode, .rateLimited)
        XCTAssertEqual(message.extractionAttemptCount, 1)
        XCTAssertEqual(message.lastExtractionAttemptAt, now)
        XCTAssertEqual(message.nextExtractionRetryAt, now.addingTimeInterval(60))
        XCTAssertEqual(attempt.errorCode, .rateLimited)
    }

    @MainActor
    func testTransientFailuresStayLocalAndRetryable() async throws {
        try await assertRetryableSendFailure(AppError.networkUnavailable, expectedCode: .networkUnavailable)
        try await assertRetryableSendFailure(AppError.timeout, expectedCode: .timeout)
        try await assertRetryableSendFailure(AppError.serverError, expectedCode: .serverError)
    }

    @MainActor
    func testInvalidKeyIsReviewableAfterTokenChangeNotScheduledRetry() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.invalidServiceToken),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })

        XCTAssertEqual(message.extractionStatus, .pendingToken)
        XCTAssertEqual(message.extractionErrorCode, .invalidServiceToken)
        XCTAssertNil(message.nextExtractionRetryAt)
    }

    @MainActor
    func testAIServiceClientMapsHTTPAndTransportFailures() async throws {
        try await assertClientError(statusCode: 401, expected: .invalidServiceToken)
        try await assertClientError(statusCode: 429, expected: .rateLimited)
        try await assertClientError(statusCode: 500, expected: .serverError)

        let client = AIServiceClient(deviceToken: "test-token", session: StubHTTPSession(error: URLError(.timedOut)))
        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected timeout.")
        } catch let error as AppError {
            XCTAssertEqual(error, .timeout)
        }
    }

    @MainActor
    func testRawResponseAndRequestDebugTextDoNotStoreDeviceToken() async throws {
        let rawResponse = canonicalExtractionJSON()
        let extractor = AIServiceMessageExtractionClient(
            deviceToken: "test-device-token",
            client: StaticAIServiceSender(rawResponseText: rawResponse)
        )

        let payload = try await extractor.extractRawResponse(
            for: "Changed filter today.",
            now: fixedTestNow
        )

        XCTAssertEqual(payload.rawResponseText, rawResponse)
        XCTAssertFalse(payload.requestJSON?.contains("test-device-token") ?? true)
    }

    @MainActor
    private func assertClientError(statusCode: Int, expected: AppError) async throws {
        let client = AIServiceClient(deviceToken: "test-token", session: StubHTTPSession(statusCode: statusCode))
        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected \(expected).")
        } catch let error as AppError {
            XCTAssertEqual(error, expected)
        }
    }

    @MainActor
    private func assertRetryableSendFailure(_ error: AppError, expectedCode: ExtractionErrorCode) async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: error),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.text, "Changed filter today.")
        XCTAssertEqual(message.extractionStatus, .pendingRetry)
        XCTAssertEqual(message.extractionErrorCode, expectedCode)
        XCTAssertEqual(message.nextExtractionRetryAt, fixedTestNow.addingTimeInterval(60))
        XCTAssertEqual(attempt.status, .failed)
        XCTAssertEqual(attempt.errorCode, expectedCode)
    }

    @MainActor
    private func emptyBackendRequest() -> BackendExtractionRequest {
        AIServiceMessageExtractionClient.backendRequest(
            for: "",
            now: fixedTestNow,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }
}

private struct StaticAIServiceSender: AIServiceExtractionSending {
    var rawResponseText: String

    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload {
        ExtractionResponsePayload(rawResponseText: rawResponseText, requestJSON: nil, modelName: "test-backend")
    }
}

private struct FailingAIServiceSender: AIServiceExtractionSending {
    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload {
        XCTFail("Backend client should not be called without a device token.")
        return ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON(), requestJSON: nil, modelName: nil)
    }
}

private struct StubHTTPSession: AIServiceHTTPSession {
    var statusCode: Int?
    var error: Error?

    init(statusCode: Int) {
        self.statusCode = statusCode
        self.error = nil
    }

    init(error: Error) {
        self.statusCode = nil
        self.error = error
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
        return (Data(#"{"rawResponseText":"{}","requestJSON":null,"modelName":"test-backend"}"#.utf8), response)
    }
}
