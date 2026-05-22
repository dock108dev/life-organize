import Foundation

struct DeterministicMessageExtractionFixture {
    let id: String
    let matches: @Sendable (_ normalizedText: String) -> Bool
    let responseText: @Sendable (_ originalText: String, _ now: Date) -> String

    func responseIfMatched(for text: String, now: Date) -> String? {
        guard matches(text.lowercased()) else { return nil }
        return responseText(text, now)
    }
}
