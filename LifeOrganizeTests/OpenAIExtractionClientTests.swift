import Foundation
import SwiftData
import XCTest
@testable import LifeOrganize

final class OpenAIExtractionClientTests: XCTestCase {
    @MainActor
    func testExtractionRequestCarriesStrictSchemaAndLocalDateContext() throws {
        let now = fixedTestNow
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let request = OpenAIMessageExtractionClient.request(
            for: #"Changed the "hallway" filter today."#,
            now: now,
            timeZone: timeZone
        )
        let requestData = try JSONEncoder().encode(request)
        let requestText = String(decoding: requestData, as: UTF8.self)
        let userText = request.input[1].content[0].text

        XCTAssertEqual(request.text.format.type, "json_schema")
        XCTAssertEqual(request.text.format.name, "life_ledger_extraction_v1")
        XCTAssertEqual(request.text.format.strict, true)
        XCTAssertTrue(userText.contains(#""currentDate": "2027-01-15""#))
        XCTAssertTrue(userText.contains(#""timezone": "America/New_York""#))
        XCTAssertTrue(userText.contains(#""userMessage": "Changed the \"hallway\" filter today.""#))
        XCTAssertTrue(requestText.contains("Do not provide advice, coaching, emotional analysis, or conversation."))
        XCTAssertTrue(requestText.contains("recallQueries"))
        XCTAssertTrue(requestText.contains("eventType"))
        XCTAssertTrue(requestText.contains("EventMetadataExtraction"))
        XCTAssertTrue(requestText.contains("Use only the eventType values in the schema"))
        XCTAssertTrue(requestText.contains("Choose other instead of inventing a new event ontology."))
        XCTAssertTrue(requestText.contains("Do not store those as standalone Notes."))
        XCTAssertTrue(requestText.contains("Sparse freeform fallback for durable facts"))
        XCTAssertTrue(requestText.contains("Short annotation about this event only."))
        XCTAssertTrue(requestText.contains(#""quantity""#))
        XCTAssertTrue(requestText.contains("confidence"))
        XCTAssertTrue(requestText.contains("errors"))
        XCTAssertTrue(requestText.contains("ownerRef"))
        XCTAssertTrue(requestText.contains("ownerField"))
        XCTAssertTrue(requestText.contains("DateExtraction entries as evidence"))
    }

    @MainActor
    func testWebLookupRequestEnablesWebSearchAndSourceCollection() throws {
        let request = OpenAIWebRequestClient.request(
            for: "Saturday best college football games with kickoff times.",
            mode: .answer,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let encoded = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)

        XCTAssertEqual(request.tools.first?.type, "web_search")
        XCTAssertEqual(request.tools.first?.userLocation?.country, "US")
        XCTAssertEqual(request.tools.first?.userLocation?.timezone, "America/New_York")
        XCTAssertEqual(request.include, ["web_search_call.action.sources"])
        XCTAssertEqual(request.toolChoice, "auto")
        XCTAssertNil(request.text)
        XCTAssertTrue(encoded.contains("source URLs"))
        XCTAssertTrue(encoded.contains(#""type":"web_search""#))
    }

    @MainActor
    func testWebImportRequestUsesLedgerSchemaWithWebSearch() throws {
        let request = OpenAIWebRequestClient.request(
            for: "Add all Rutgers football home games for 2026.",
            mode: .importRecords,
            now: fixedTestNow,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        let encoded = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)

        XCTAssertEqual(request.tools.first?.type, "web_search")
        XCTAssertEqual(request.text?.format.type, "json_schema")
        XCTAssertEqual(request.text?.format.name, "life_ledger_extraction_v1")
        XCTAssertTrue(encoded.contains("Create Things for stable subjects"))
        XCTAssertTrue(encoded.contains("tailgating before a game"))
    }

    @MainActor
    func testMissingKeySkipsOpenAIClientAndReturnsPendingKeyThroughSendFlow() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: OpenAIMessageExtractionClient(
                apiKey: "",
                client: FailingOpenAISender()
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(message.extractionStatus, .pendingKey)
        XCTAssertEqual(message.extractionErrorCode, .missingAPIKey)
        XCTAssertNil(message.nextExtractionRetryAt)
        XCTAssertEqual(message.extractionAttemptCount, 1)
        XCTAssertEqual(message.lastExtractionAttemptAt, fixedTestNow)
        XCTAssertEqual(attempt.errorCode, .missingAPIKey)
    }

    @MainActor
    func testRetryableOpenAIErrorsRecordRetryMetadata() async throws {
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
    func testInvalidKeyIsReviewableAfterKeyChangeNotScheduledRetry() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.invalidAPIKey),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed filter today.")

        let message = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })

        XCTAssertEqual(message.extractionStatus, .pendingKey)
        XCTAssertEqual(message.extractionErrorCode, .invalidAPIKey)
        XCTAssertNil(message.nextExtractionRetryAt)
    }

    @MainActor
    func testOpenAIClientMapsHTTPAndTransportFailures() async throws {
        try await assertClientError(statusCode: 401, expected: .invalidAPIKey)
        try await assertClientError(statusCode: 429, expected: .rateLimited)
        try await assertClientError(statusCode: 500, expected: .serverError)

        let client = OpenAIClient(deviceToken: "test-token", session: StubHTTPSession(error: URLError(.timedOut)))
        do {
            _ = try await client.sendExtraction(emptyBackendRequest())
            XCTFail("Expected timeout.")
        } catch let error as AppError {
            XCTAssertEqual(error, .timeout)
        }
    }

    @MainActor
    func testRawResponseAndRequestDebugTextDoNotStoreAPIKey() async throws {
        let rawResponse = canonicalExtractionJSON()
        let extractor = OpenAIMessageExtractionClient(
            apiKey: "sk-test-secret",
            client: StaticOpenAISender(response: OpenAIResponse(outputText: rawResponse))
        )

        let payload = try await extractor.extractRawResponse(
            for: "Changed filter today.",
            now: fixedTestNow
        )

        XCTAssertEqual(payload.rawResponseText, rawResponse)
        XCTAssertFalse(payload.requestJSON?.contains("sk-test-secret") ?? true)
    }

    @MainActor
    private func assertClientError(statusCode: Int, expected: AppError) async throws {
        let client = OpenAIClient(deviceToken: "test-token", session: StubHTTPSession(statusCode: statusCode))
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
        OpenAIMessageExtractionClient.backendRequest(
            for: "",
            now: fixedTestNow,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }
}

private struct StaticOpenAISender: OpenAIExtractionSending {
    var response: OpenAIResponse

    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload {
        ExtractionResponsePayload(rawResponseText: response.outputText, requestJSON: nil, modelName: "test-backend")
    }
}

private struct FailingOpenAISender: OpenAIExtractionSending {
    func sendExtraction(_ request: BackendExtractionRequest) async throws -> ExtractionResponsePayload {
        XCTFail("Backend client should not be called without a device token.")
        return ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON(), requestJSON: nil, modelName: nil)
    }
}

private struct StubHTTPSession: OpenAIHTTPSession {
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
