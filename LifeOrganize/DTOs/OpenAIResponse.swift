import Foundation

struct OpenAIResponse: Decodable, Equatable {
    var outputText: String

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    init(outputText: String) {
        self.outputText = outputText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let outputText = try container.decodeIfPresent(String.self, forKey: .outputText) {
            self.outputText = outputText
            return
        }

        let output = try container.decode([OpenAIOutputItem].self, forKey: .output)
        let texts = output.flatMap(\.content).compactMap(\.text)
        guard let outputText = texts.first(where: { !$0.isEmpty }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .output,
                in: container,
                debugDescription: "OpenAI response did not include output text."
            )
        }
        self.outputText = outputText
    }
}

private struct OpenAIOutputItem: Decodable {
    var content: [OpenAIOutputContent]

    private enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent([OpenAIOutputContent].self, forKey: .content) ?? []
    }
}

private struct OpenAIOutputContent: Decodable {
    var type: String?
    var text: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }
}
