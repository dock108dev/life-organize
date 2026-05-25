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

    @MainActor
    func testBackendRequestDTOsMatchContractFixtures() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let extraction = AIServiceMessageExtractionClient.backendRequest(
            for: #"Changed the "hallway" filter today."#,
            now: fixedTestNow,
            timeZone: timeZone
        )
        let answer = AIServiceWebRequestClient.backendRequest(
            for: "Saturday best college football games with kickoff times.",
            mode: .answer,
            now: fixedTestNow,
            timeZone: timeZone
        )
        let importRequest = AIServiceWebRequestClient.backendRequest(
            for: "Add all home games from my schedule.",
            mode: .importRecords,
            now: fixedTestNow,
            timeZone: timeZone
        )

        XCTAssertEqual(
            extraction,
            try decodeContractFixture(BackendExtractionRequest.self, "backend_extraction_request.v1")
        )
        XCTAssertEqual(
            answer,
            try decodeContractFixture(BackendWebRequest.self, "backend_web_answer_request.v1")
        )
        XCTAssertEqual(
            importRequest,
            try decodeContractFixture(BackendWebRequest.self, "backend_web_import_request.v1")
        )
    }

    func testBackendResponseDTOsDecodeContractFixtures() throws {
        let extraction = try decodeContractFixture(BackendExtractionResponse.self, "backend_extraction_response.v1")
        let answer = try decodeContractFixture(BackendWebResponse.self, "backend_web_answer_response.v1")
        let importResponse = try decodeContractFixture(BackendWebResponse.self, "backend_web_import_response.v1")

        XCTAssertEqual(extraction.modelName, "test-backend")
        XCTAssertNotNil(extraction.requestJSON)
        XCTAssertNotNil(answer.assistantText)
        XCTAssertNil(answer.rawResponseText)
        XCTAssertNotNil(importResponse.rawResponseText)
        XCTAssertNotNil(importResponse.requestJSON)
    }

    func testBackendErrorResponseDecodesFlatNestedAndValidationShapes() throws {
        let flat = try decodeContractFixture(BackendErrorResponse.self, "backend_error_flat.v1")
        let nested = try decodeContractFixture(BackendErrorResponse.self, "backend_error_nested.v1")
        let validation = try decodeContractFixture(BackendErrorResponse.self, "backend_validation_error.v1")

        XCTAssertEqual(flat.code, "rate_limited")
        XCTAssertEqual(flat.detail, "OpenAI rate limit reached.")
        XCTAssertEqual(nested.code, "timeout")
        XCTAssertEqual(nested.detail, "OpenAI request timed out.")
        XCTAssertNil(validation.code)
        XCTAssertNil(validation.detail)
    }

    func testExtractionContractMetadataMatchesClientConstants() throws {
        let metadata = try decodeContractFixture(ExtractionContractMetadata.self, "extraction_contract.v1")

        XCTAssertEqual(metadata.requestSchemaVersion, ExtractionContract.schemaVersion)
        XCTAssertEqual(metadata.webModes, ["answer", "importRecords"])
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
    func testAIServiceClientErrorsMapToDistinctRecoveryStates() {
        let service = ChatSendService(
            modelContext: makeInMemoryModelContext(),
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        assertRecoveryMapping(
            service.mapExtractionError(AppError.missingServiceToken),
            status: .pendingToken,
            code: .missingServiceToken,
            detail: "AI service credential is missing."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.invalidServiceToken),
            status: .pendingToken,
            code: .invalidServiceToken,
            detail: "AI service credential was rejected."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.networkUnavailable),
            status: .pendingRetry,
            code: .networkUnavailable,
            detail: "The network is unavailable."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.timeout),
            status: .pendingRetry,
            code: .timeout,
            detail: "The AI service request timed out."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.rateLimited),
            status: .pendingRetry,
            code: .rateLimited,
            detail: "AI service rate limit reached."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.serverError),
            status: .pendingRetry,
            code: .serverError,
            detail: "AI service error."
        )
        assertRecoveryMapping(
            service.mapExtractionError(AppError.invalidResponse),
            status: .failedNeedsReview,
            code: .schemaValidationFailed,
            detail: "AI service returned an invalid response."
        )
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

    private func assertRecoveryMapping(
        _ mapping: (status: ExtractionStatus, code: ExtractionErrorCode, userMessage: String, detail: String),
        status: ExtractionStatus,
        code: ExtractionErrorCode,
        detail: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(mapping.status, status, file: file, line: line)
        XCTAssertEqual(mapping.code, code, file: file, line: line)
        XCTAssertEqual(mapping.detail, detail, file: file, line: line)
        XCTAssertFalse(mapping.userMessage.isEmpty, file: file, line: line)
    }
}

private struct ExtractionContractMetadata: Decodable {
    let requestSchemaVersion: Int
    let webModes: [String]
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
