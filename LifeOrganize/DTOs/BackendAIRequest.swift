import Foundation

struct BackendExtractionRequest: Codable, Equatable {
    var text: String
    var currentDate: String
    var currentDateTime: String
    var timezone: String
    var schemaVersion: Int
}

struct BackendWebRequest: Codable, Equatable {
    var text: String
    var mode: String
    var currentDate: String
    var currentDateTime: String
    var timezone: String
}

struct BackendExtractionResponse: Decodable, Equatable {
    var rawResponseText: String
    var requestJSON: String?
    var modelName: String?
}

struct BackendWebResponse: Decodable, Equatable {
    var assistantText: String?
    var rawResponseText: String?
    var requestJSON: String?
    var modelName: String?
}

struct BackendErrorResponse: Decodable, Equatable {
    var code: String?
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        if let text = try? container.decodeIfPresent(String.self, forKey: .detail) {
            detail = text
        } else if let nested = try? container.decodeIfPresent(BackendErrorResponse.self, forKey: .detail) {
            code = code ?? nested.code
            detail = nested.detail
        } else {
            detail = nil
        }
    }
}
