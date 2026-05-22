import Foundation
import SwiftData

@Model
final class LedgerEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var occurredAt: Date
    var rawText: String
    var createdAt: Date
    var updatedAt: Date
    var note: String?
    var sourceClientID: String?
    var sourceExtractionRunID: UUID?
    var eventTypeRawValue: String?
    var metadataJSONText: String = "[]"
    var metadataKeyRawValues: [String] = []
    var thing: Thing?
    var sourceMessage: ChatMessage?

    var eventType: LedgerEventType {
        get {
            guard let eventTypeRawValue else { return .generic }
            return LedgerEventType(rawValue: eventTypeRawValue) ?? .other
        }
        set {
            eventTypeRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var metadataEntries: [LedgerEventMetadataEntry] {
        get { Self.decodeMetadata(from: metadataJSONText) }
        set {
            metadataJSONText = Self.encodeMetadata(newValue)
            metadataKeyRawValues = newValue.map(\.keyRawValue)
            updatedAt = Date()
        }
    }

    var thingID: UUID? {
        get { thing?.id }
        set { _ = newValue }
    }

    var sourceMessageID: UUID? {
        sourceMessage?.id
    }

    init(
        id: UUID = UUID(),
        title: String,
        occurredAt: Date,
        rawText: String,
        thingID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        note: String? = nil,
        sourceClientID: String? = nil,
        sourceExtractionRunID: UUID? = nil,
        eventType: LedgerEventType = .generic,
        metadataEntries: [LedgerEventMetadataEntry] = [],
        thing: Thing? = nil,
        sourceMessage: ChatMessage? = nil
    ) {
        self.id = id
        self.title = title
        self.occurredAt = occurredAt
        self.rawText = rawText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.note = note
        self.sourceClientID = sourceClientID
        self.sourceExtractionRunID = sourceExtractionRunID
        self.eventTypeRawValue = eventType.rawValue
        self.metadataJSONText = Self.encodeMetadata(metadataEntries)
        self.metadataKeyRawValues = metadataEntries.map(\.keyRawValue)
        self.thing = thing
        self.sourceMessage = sourceMessage
    }

    private static func decodeMetadata(from text: String) -> [LedgerEventMetadataEntry] {
        guard let data = text.data(using: .utf8),
              let entries = try? JSONDecoder().decode([LedgerEventMetadataEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private static func encodeMetadata(_ entries: [LedgerEventMetadataEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

enum LedgerEventType: String, Codable, CaseIterable, Identifiable {
    case generic
    case maintenance
    case purchase
    case visit
    case replacement
    case cleaning
    case renewal
    case appointment
    case project
    case note
    case reminder
    case measurement
    case statusChange = "status_change"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .generic:
            "Generic"
        case .maintenance:
            "Maintenance"
        case .purchase:
            "Purchase"
        case .visit:
            "Visit"
        case .replacement:
            "Replacement"
        case .cleaning:
            "Cleaning"
        case .renewal:
            "Renewal"
        case .appointment:
            "Appointment"
        case .project:
            "Project"
        case .note:
            "Note"
        case .reminder:
            "Reminder"
        case .measurement:
            "Measurement"
        case .statusChange:
            "Status Change"
        case .other:
            "Other"
        }
    }
}

struct LedgerEventMetadataEntry: Codable, Equatable {
    var keyRawValue: String
    var valueKindRawValue: String
    var stringValue: String?
    var numberValue: Double?
    var dateValue: String?
    var boolValue: Bool?
    var unit: String?
    var sourceText: String?

    var key: LedgerEventMetadataKey {
        LedgerEventMetadataKey(rawValue: keyRawValue) ?? .other
    }

    var valueKind: LedgerEventMetadataValueKind {
        LedgerEventMetadataValueKind(rawValue: valueKindRawValue) ?? .string
    }

    var displayValue: String {
        switch valueKind {
        case .number:
            if let numberValue {
                return [LedgerDisplayFormatting.decimal(numberValue), unit]
                    .compactMap { $0?.nilIfEmpty }
                    .joined(separator: " ")
            }
        case .date:
            if let dateValue, !dateValue.isEmpty {
                return dateValue
            }
        case .boolean:
            if let boolValue {
                return boolValue ? "true" : "false"
            }
        case .string:
            break
        }
        return stringValue?.nilIfEmpty ?? sourceText?.nilIfEmpty ?? ""
    }

    init(
        key: LedgerEventMetadataKey,
        valueKind: LedgerEventMetadataValueKind,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: String? = nil,
        boolValue: Bool? = nil,
        unit: String? = nil,
        sourceText: String? = nil
    ) {
        self.keyRawValue = key.rawValue
        self.valueKindRawValue = valueKind.rawValue
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
        self.unit = unit
        self.sourceText = sourceText
    }

    init(
        keyRawValue: String,
        valueKindRawValue: String,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: String? = nil,
        boolValue: Bool? = nil,
        unit: String? = nil,
        sourceText: String? = nil
    ) {
        self.keyRawValue = keyRawValue
        self.valueKindRawValue = valueKindRawValue
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
        self.unit = unit
        self.sourceText = sourceText
    }
}

enum LedgerEventMetadataKey: String, Codable, CaseIterable {
    case mileage
    case amount
    case quantity
    case unit
    case vendor
    case location
    case subtype
    case identifier
    case dueDate = "due_date"
    case calendarInterval = "calendar_interval"
    case mileageInterval = "mileage_interval"
    case nextDueDate = "next_due_date"
    case nextDueMileage = "next_due_mileage"
    case packageQuantity = "package_quantity"
    case serviceReset = "service_reset"
    case recurrenceEvidence = "recurrence_evidence"
    case sourceText = "source_text"
    case other

    var displayName: String {
        switch self {
        case .mileage:
            "Mileage"
        case .amount:
            "Amount"
        case .quantity:
            "Quantity"
        case .unit:
            "Unit"
        case .vendor:
            "Vendor"
        case .location:
            "Location"
        case .subtype:
            "Subtype"
        case .identifier:
            "Identifier"
        case .dueDate:
            "Due Date"
        case .calendarInterval:
            "Calendar Interval"
        case .mileageInterval:
            "Mileage Interval"
        case .nextDueDate:
            "Next Due Date"
        case .nextDueMileage:
            "Next Due Mileage"
        case .packageQuantity:
            "Package Quantity"
        case .serviceReset:
            "Service Reset"
        case .recurrenceEvidence:
            "Recurrence Evidence"
        case .sourceText:
            "Source Text"
        case .other:
            "Other"
        }
    }
}

enum LedgerEventMetadataValueKind: String, Codable, CaseIterable {
    case string
    case number
    case date
    case boolean
}
