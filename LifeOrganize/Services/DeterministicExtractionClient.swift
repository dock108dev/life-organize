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
