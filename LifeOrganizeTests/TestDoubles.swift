import Foundation
import SwiftData
@testable import LifeOrganize

let fixedTestNow = Date(timeIntervalSince1970: 1_800_000_000)

func makeInMemoryModelContext() -> ModelContext {
    ModelContext(ModelContainerFactory.make(inMemory: true))
}

func makeTemporaryDirectory(prefix: String = "LifeOrganizeTests") throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

struct TestDateProvider: DateProvider {
    var now: Date
}

enum TestTextNormalization {
    static func normalizedTimeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

@MainActor
struct StaticMessageExtractionClient: MessageExtractionClient {
    var payload: ExtractionResponsePayload

    func extractRawResponse(for _: String, now _: Date) async throws -> ExtractionResponsePayload {
        payload
    }
}

@MainActor
struct ThrowingMessageExtractionClient: MessageExtractionClient {
    var error: Error

    func extractRawResponse(for _: String, now _: Date) async throws -> ExtractionResponsePayload {
        throw error
    }
}

@MainActor
struct InspectingExtractionClient: MessageExtractionClient {
    var inspect: (String, Date) throws -> ExtractionResponsePayload

    func extractRawResponse(for text: String, now: Date) async throws -> ExtractionResponsePayload {
        try inspect(text, now)
    }
}

@MainActor
struct StaticWebRequestClient: WebRequestClient {
    var result: WebRequestResult
    var onResolve: ((String, WebRequestMode, Date) -> Void)?

    func resolve(_ text: String, mode: WebRequestMode, now: Date) async throws -> WebRequestResult {
        onResolve?(text, mode, now)
        return result
    }
}

@MainActor
struct ThrowingWebRequestClient: WebRequestClient {
    var error: Error

    func resolve(_: String, mode _: WebRequestMode, now _: Date) async throws -> WebRequestResult {
        throw error
    }
}
