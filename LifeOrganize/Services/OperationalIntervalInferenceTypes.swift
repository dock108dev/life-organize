import Foundation

struct OperationalIntervalInference: Equatable {
    let thingID: UUID
    let thingName: String
    let track: OperationalIntervalTrack
    let title: String
    let calendarIntervalDays: Int?
    let nextExpectedDateRange: DateInterval?
    let mileageInterval: Int?
    let nextExpectedMileage: Int?
    let confidence: OperationalIntervalConfidence
    let evidence: [OperationalIntervalEvidenceRecord]
    let operationalReason: String
    let latestEventID: UUID
    let suppressionReason: String?

    var isSuppressed: Bool {
        suppressionReason != nil
    }

    func reviewItem() -> LedgerReviewItemCandidate? {
        guard !isSuppressed else { return nil }
        return LedgerReviewItemCandidate(
            title: title,
            thingID: thingID,
            thingName: thingName,
            reason: operationalReason,
            confidence: confidence,
            nextExpectedDateRange: nextExpectedDateRange,
            nextExpectedMileage: nextExpectedMileage,
            evidenceSourceIDs: evidence.map(\.sourceID)
        )
    }

    func suppressed(reason: String) -> OperationalIntervalInference {
        OperationalIntervalInference(
            thingID: thingID,
            thingName: thingName,
            track: track,
            title: title,
            calendarIntervalDays: calendarIntervalDays,
            nextExpectedDateRange: nextExpectedDateRange,
            mileageInterval: mileageInterval,
            nextExpectedMileage: nextExpectedMileage,
            confidence: confidence,
            evidence: evidence,
            operationalReason: operationalReason,
            latestEventID: latestEventID,
            suppressionReason: reason
        )
    }
}

struct LedgerReviewItemCandidate: Equatable {
    let title: String
    let thingID: UUID
    let thingName: String
    let reason: String
    let confidence: OperationalIntervalConfidence
    let nextExpectedDateRange: DateInterval?
    let nextExpectedMileage: Int?
    let evidenceSourceIDs: [UUID]
}

struct OperationalIntervalEvidenceRecord: Equatable {
    let source: OperationalIntervalEvidenceSource
    let sourceID: UUID
    let occurredAt: Date?
    let summary: String
    let detail: String?
}

enum OperationalIntervalEvidenceSource: String, Equatable {
    case event
    case derivedCalendarInterval = "derived_calendar_interval"
    case derivedMileageInterval = "derived_mileage_interval"
}

struct OperationalIntervalConfidence: Equatable {
    enum Level: String {
        case weak
        case medium
        case strong
    }

    let level: Level
    let score: Double

    static let weak = OperationalIntervalConfidence(level: .weak, score: 0.55)
    static let medium = OperationalIntervalConfidence(level: .medium, score: 0.75)
    static let strong = OperationalIntervalConfidence(level: .strong, score: 0.9)
}

enum OperationalIntervalTrack: String, Equatable, Hashable {
    case airFilter
    case dogFood
    case oilChange

    init?(event: LedgerEvent, thing: Thing) {
        let text = Self.normalizedText([thing.name, thing.details, event.title, event.rawText, event.note].compactMap { $0 })
        let subtype = event.metadataEntries.first { $0.key == .subtype }?.displayValue.lowercased() ?? ""

        if event.eventType == .purchase, text.contains("dog food") || text.contains("kibble") || text.contains("pet food") {
            self = .dogFood
            return
        }

        if event.eventType == .maintenance,
           thing.category == .vehicle || text.contains(" car ") || text.contains("vehicle") || text.contains("sedan") {
            if text.contains("oil change") || text.contains("changed oil") || text.contains("engine oil") || subtype.contains("oil") {
                self = .oilChange
                return
            }
        }

        if [.maintenance, .replacement].contains(event.eventType),
           text.contains("filter"),
           text.contains("air") || text.contains("hvac") || text.contains("furnace") || text.contains("return") {
            self = .airFilter
            return
        }

        return nil
    }

    var displayName: String {
        switch self {
        case .airFilter:
            "Air filter"
        case .dogFood:
            "Dog food purchase"
        case .oilChange:
            "Oil change"
        }
    }

    var operationalReason: String {
        switch self {
        case .airFilter:
            "This is based on saved replacement records for a maintained household item."
        case .dogFood:
            "This is based on saved purchase records for a recurring household supply."
        case .oilChange:
            "This is based on saved vehicle service records and mileage evidence."
        }
    }

    var supportsMileage: Bool {
        self == .oilChange
    }

    func matches(rule: LedgerRule) -> Bool {
        let text = Self.normalizedText([rule.title, rule.reason, rule.rawText].compactMap { $0 })
        switch self {
        case .airFilter:
            return text.contains("filter") && (text.contains("air") || text.contains("hvac") || text.contains("furnace") || text.contains("return"))
        case .dogFood:
            return text.contains("dog food") || text.contains("kibble") || text.contains("pet food")
        case .oilChange:
            return text.contains("oil change") || text.contains("changed oil") || text.contains("engine oil")
        }
    }

    private static func normalizedText(_ values: [String]) -> String {
        " " + values.joined(separator: " ").lowercased() + " "
    }
}
