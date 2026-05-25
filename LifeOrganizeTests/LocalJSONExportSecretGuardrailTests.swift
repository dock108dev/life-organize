import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LocalJSONExportSecretGuardrailTests: XCTestCase {
    func testExportRedactsSecretLikeValuesFromPortableJSON() throws {
        let context = makeInMemoryModelContext()
        let deviceToken = "11111111-1111-1111-1111-111111111111.22222222-2222-2222-2222-222222222222"
        let providerKey = "sk-proj-1234567890abcdefghijklmnopqrstuvwxyz"
        let startedAt = try makeDate("2026-05-17T13:42:10Z")
        let message = ChatMessage(
            role: .user,
            text: "Pasted Authorization: Bearer \(deviceToken) and \(providerKey).",
            createdAt: startedAt,
            extractionStatus: .failed,
            extractionError: "Backend rejected Bearer \(deviceToken).",
            extractionErrorCode: .invalidServiceToken
        )
        let attempt = ExtractionAttempt(
            status: .failed,
            requestJSON: """
            {"Authorization":"Bearer \(deviceToken)","X-LifeOrganize-Device-Token":"\(deviceToken)","api_key":"\(providerKey)"}
            """,
            rawResponseText: #"{"error":"\#(providerKey)"}"#,
            normalizedJSONText: #"{"notes":[{"text":"Bearer \#(deviceToken)"}]}"#,
            errorCode: .invalidServiceToken,
            errorMessage: "Authorization: Bearer \(deviceToken)",
            startedAt: startedAt,
            completedAt: startedAt,
            sourceMessage: message
        )
        context.insert(message)
        context.insert(attempt)
        try context.save()

        let data = try exportService(context: context).jsonData()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(LedgerExportEnvelope.self, from: data)

        XCTAssertFalse(json.contains(deviceToken))
        XCTAssertFalse(json.contains(providerKey))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("bearer"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("x-lifeorganize-device-token"))
        XCTAssertTrue(json.contains(SecretRedactor.replacement))
        XCTAssertTrue(decoded.records.chatMessages.first?.text.contains(SecretRedactor.replacement) == true)
        XCTAssertTrue(decoded.records.extractionRuns.first?.requestJSON?.contains(SecretRedactor.replacement) == true)
        XCTAssertTrue(decoded.records.extractionRuns.first?.parsedResponse.debugDescription.contains(deviceToken) == false)
    }

    func testSecretRedactorPreservesNonSecretExportText() {
        XCTAssertEqual(
            SecretRedactor.redact("Changed oil and saved receipts."),
            "Changed oil and saved receipts."
        )
    }

    private func exportService(context: ModelContext) throws -> LocalJSONExportService {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalJSONExportService(
            modelContext: context,
            now: { Date(timeIntervalSince1970: 1_779_043_800) },
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private func makeDate(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }
}
