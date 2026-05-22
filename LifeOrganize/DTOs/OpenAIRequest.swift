import Foundation

struct OpenAIRequest: Codable, Equatable {
    var model: String
    var input: [OpenAIInputMessage]
    var text: OpenAITextOptions

    init(model: String, input: [OpenAIInputMessage], text: OpenAITextOptions) {
        self.model = model
        self.input = input
        self.text = text
    }
}

struct OpenAIInputMessage: Codable, Equatable {
    var role: String
    var content: [OpenAIInputContent]
}

struct OpenAIInputContent: Codable, Equatable {
    var type: String
    var text: String
}

struct OpenAITextOptions: Codable, Equatable {
    var format: OpenAIResponseFormat
}

struct OpenAIResponseFormat: Codable, Equatable {
    var type: String
    var name: String
    var strict: Bool
    var schema: JSONValue
}

struct OpenAIWebRequest: Codable, Equatable {
    var model: String
    var input: [OpenAIInputMessage]
    var tools: [OpenAIWebTool]
    var include: [String]?
    var toolChoice: String?
    var text: OpenAITextOptions?

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case tools
        case include
        case toolChoice = "tool_choice"
        case text
    }
}

struct OpenAIWebTool: Codable, Equatable {
    var type: String
    var userLocation: OpenAIWebUserLocation?

    private enum CodingKeys: String, CodingKey {
        case type
        case userLocation = "user_location"
    }
}

struct OpenAIWebUserLocation: Codable, Equatable {
    var type: String
    var country: String
    var region: String?
    var city: String?
    var timezone: String?
}
