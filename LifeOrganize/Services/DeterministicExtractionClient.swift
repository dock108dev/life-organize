import Foundation

@MainActor
struct DeterministicMessageExtractionClient: MessageExtractionClient {
    func extractRawResponse(for text: String, now: Date) async throws -> ExtractionResponsePayload {
        ExtractionResponsePayload(
            rawResponseText: DeterministicMessageExtractionFixtureLibrary.responseText(for: text, now: now),
            requestJSON: #"{"mode":"deterministic"}"#,
            modelName: "deterministic-extractor"
        )
    }
}

struct SimulatedUnavailableMessageExtractionClient: MessageExtractionClient {
    let error: AppError

    func extractRawResponse(for text: String, now: Date) async throws -> ExtractionResponsePayload {
        _ = text
        _ = now
        throw error
    }
}

struct SimulatedUnavailableWebRequestClient: WebRequestClient {
    let error: AppError

    func resolve(_ text: String, mode: WebRequestMode, now: Date) async throws -> WebRequestResult {
        _ = text
        _ = mode
        _ = now
        throw error
    }
}
