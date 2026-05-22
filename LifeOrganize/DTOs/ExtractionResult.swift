import Foundation

enum ExtractionContract {
    static let schemaVersion = 1
    static let promptVersion = "openai-extractor-v1"
    static let modelName = "gpt-4.1-mini"
}

struct ExtractionResponsePayload: Equatable {
    var rawResponseText: String
    var requestJSON: String?
    var modelName: String?
}

struct ExtractionEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var classification: String
    var events: [ExtractedEvent]
    var rules: [ExtractedRule]
    var notes: [ExtractedNote]
    var things: [ExtractedThing]
    var aliases: [ExtractedAlias]
    var dates: [ExtractedDate]
    var temporalResolutionDecisions: [TemporalResolutionDecision]
    var recallQueries: [ExtractedRecallQuery]
    var confidence: ExtractionConfidence
    var extractionErrors: [ModelExtractionError]
    var recallQuery: String?
    var warnings: [ExtractionWarning]

    static func empty(
        classification: String = "log",
        warnings: [ExtractionWarning] = []
    ) -> ExtractionEnvelope {
        ExtractionEnvelope(
            schemaVersion: ExtractionContract.schemaVersion,
            classification: classification,
            events: [],
            rules: [],
            notes: [],
            things: [],
            aliases: [],
            dates: [],
            temporalResolutionDecisions: [],
            recallQueries: [],
            confidence: ExtractionConfidence(overall: 0, requiresReview: false, reasons: []),
            extractionErrors: [],
            recallQuery: nil,
            warnings: warnings
        )
    }

    static func emptyJSON(warnings: [ExtractionWarning] = []) -> String {
        (try? empty(warnings: warnings).jsonString()) ?? #"{"schemaVersion":1,"classification":"log","events":[],"rules":[],"notes":[],"things":[],"aliases":[],"dates":[],"temporalResolutionDecisions":[],"recallQueries":[],"confidence":{"overall":0,"requiresReview":false,"reasons":[]},"extractionErrors":[],"recallQuery":null,"warnings":[]}"#
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

struct ExtractedEvent: Codable, Equatable {
    var clientID: String
    var title: String
    var thingName: String?
    var occurredAt: String
    var rawText: String?
    var note: String?
    var eventType: String
    var metadata: [ExtractedEventMetadata]
}

struct ExtractedEventMetadata: Codable, Equatable {
    var key: String
    var valueKind: String
    var stringValue: String?
    var numberValue: Double?
    var dateValue: String?
    var boolValue: Bool?
    var unit: String?
    var sourceText: String?
}

struct ExtractedRule: Codable, Equatable {
    var clientID: String
    var title: String
    var thingName: String?
    var ruleType: LedgerRuleType
    var continuityBehavior: LedgerContinuityBehavior
    var reason: String?
    var startsAt: String
    var expiresAt: String?

    init(
        clientID: String,
        title: String,
        thingName: String?,
        ruleType: LedgerRuleType = .restriction,
        continuityBehavior: LedgerContinuityBehavior? = nil,
        reason: String?,
        startsAt: String,
        expiresAt: String?
    ) {
        self.clientID = clientID
        self.title = title
        self.thingName = thingName
        self.ruleType = ruleType
        self.continuityBehavior = continuityBehavior ?? LedgerContinuityBehavior.inferred(
            ruleType: ruleType,
            expiresAt: expiresAt,
            rawText: title
        )
        self.reason = reason
        self.startsAt = startsAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case clientID
        case title
        case thingName
        case ruleType
        case continuityBehavior
        case reason
        case startsAt
        case expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(String.self, forKey: .clientID)
        title = try container.decode(String.self, forKey: .title)
        thingName = try container.decodeIfPresent(String.self, forKey: .thingName)
        ruleType = try container.decodeIfPresent(LedgerRuleType.self, forKey: .ruleType) ?? .restriction
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        startsAt = try container.decode(String.self, forKey: .startsAt)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        continuityBehavior = try container.decodeIfPresent(
            LedgerContinuityBehavior.self,
            forKey: .continuityBehavior
        ) ?? LedgerContinuityBehavior.inferred(
            ruleType: ruleType,
            expiresAt: expiresAt,
            rawText: title
        )
    }
}

struct ExtractedNote: Codable, Equatable {
    var clientID: String
    var text: String
    var linkedThingNames: [String]
}

struct ExtractedThing: Codable, Equatable {
    var clientID: String
    var name: String
    var aliases: [String]
    var category: String?
    var confidence: Double?
}

struct ExtractedAlias: Codable, Equatable {
    var thingClientID: String
    var alias: String
    var sourceText: String
    var confidence: Double?
}

struct ExtractedDate: Codable, Equatable {
    // Top-level dates are a non-authoritative evidence ledger until later logic explicitly attaches them.
    var clientID: String
    var sourceText: String
    var date: String?
    var precision: String
    var role: String
    var ownerClientID: String?
    var ownerField: String?
    var isInferred: Bool
    var confidence: Double
    var resolvedConfidence: Double
    var resolvedSourceText: String?
}

struct TemporalResolutionDecision: Codable, Equatable {
    var chosenDateClientID: String?
    var rejectedDateClientIDs: [String]
    var reason: String
    var confidenceRationale: String?
}

struct ExtractedRecallQuery: Codable, Equatable {
    var clientID: String
    var queryType: String
    var thingName: String?
    var thingClientID: String?
    var rawText: String
}

struct ExtractionConfidence: Codable, Equatable {
    var overall: Double
    var requiresReview: Bool
    var reasons: [String]
}

struct ModelExtractionError: Codable, Equatable {
    var code: String
    var message: String
    var severity: String
    var sourceText: String?
}

struct ExtractionWarning: Codable, Equatable {
    var code: String
    var message: String
}

struct ExtractionParseResult: Equatable {
    var envelope: ExtractionEnvelope
    var extractedJSONText: String
}
