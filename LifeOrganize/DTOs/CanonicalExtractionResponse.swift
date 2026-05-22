import Foundation

struct CanonicalExtractionResponse: Decodable {
    var schemaVersion: String
    var messageType: String
    var language: String
    var summary: String
    var things: LossyExtractionArray<CanonicalThing>
    var events: LossyExtractionArray<CanonicalEvent>
    var rules: LossyExtractionArray<CanonicalRule>
    var notes: LossyExtractionArray<CanonicalNote>
    var dates: LossyExtractionArray<CanonicalDate>
    var aliases: LossyExtractionArray<CanonicalAlias>
    var recallQueries: LossyExtractionArray<CanonicalRecallQuery>
    var confidence: ExtractionConfidence
    var errors: LossyExtractionArray<ModelExtractionError>
}

struct LossyExtractionArray<Element: Decodable>: Decodable {
    var values: [Element]
    var failedCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        var failedCount = 0

        while !container.isAtEnd {
            do {
                values.append(try container.decode(Element.self))
            } catch {
                failedCount += 1
                _ = try? container.decode(SkipDecodable.self)
            }
        }

        self.values = values
        self.failedCount = failedCount
    }
}

private struct SkipDecodable: Decodable {}

struct CanonicalThing: Decodable {
    var ref: String
    var name: String
    var category: String
    var mentionedText: String
    var confidence: Double
}

struct CanonicalEvent: Decodable {
    var ref: String
    var thingRef: String?
    var title: String
    var eventType: String
    var rawText: String
    var occurredAt: CanonicalResolvedDate
    var note: String?
    var metadata: LossyExtractionArray<CanonicalEventMetadata>
    var confidence: Double
}

struct CanonicalEventMetadata: Decodable {
    var key: String
    var valueKind: String
    var stringValue: String?
    var numberValue: Double?
    var dateValue: String?
    var boolValue: Bool?
    var unit: String?
    var sourceText: String?
}

struct CanonicalRule: Decodable {
    var ref: String
    var thingRef: String?
    var title: String
    var ruleType: String
    var rawText: String
    var reason: String?
    var startsAt: CanonicalResolvedDate
    var expiresAt: CanonicalResolvedDate
    var isActiveOnCreatedDate: Bool
    var confidence: Double
}

struct CanonicalNote: Decodable {
    var ref: String
    var text: String
    var rawText: String
    var linkedThingRefs: [String]
    var confidence: Double
}

struct CanonicalDate: Decodable {
    var ref: String
    var sourceText: String
    var resolved: CanonicalResolvedDate
    var dateRole: String
    var ownerRef: String?
    var ownerField: String?
    var confidence: Double
}

struct CanonicalAlias: Decodable {
    var thingRef: String
    var alias: String
    var sourceText: String
    var confidence: Double
}

struct CanonicalRecallQuery: Decodable {
    var ref: String
    var queryType: String
    var thingName: String?
    var thingRef: String?
    var rawText: String
    var confidence: Double
}

struct CanonicalResolvedDate: Decodable {
    var date: String?
    var precision: String
    var isInferred: Bool
    var sourceText: String?
    var confidence: Double
}
