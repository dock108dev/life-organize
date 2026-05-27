import Foundation

enum LedgerEventIntervalEvidenceKind: String, Codable, CaseIterable {
    case calendarInterval = "calendar_interval"
    case mileageInterval = "mileage_interval"
    case nextDueDate = "next_due_date"
    case nextDueMileage = "next_due_mileage"
    case packageQuantity = "package_quantity"
    case serviceReset = "service_reset"
    case recurrenceEvidence = "recurrence_evidence"
    case sourceText = "source_text"

    var metadataKey: LedgerEventMetadataKey {
        LedgerEventMetadataKey(rawValue: rawValue) ?? .sourceText
    }
}

struct LedgerEventIntervalEvidence: Codable, Equatable {
    var kind: LedgerEventIntervalEvidenceKind
    var valueKind: LedgerEventMetadataValueKind
    var stringValue: String?
    var numberValue: Double?
    var dateValue: String?
    var boolValue: Bool?
    var unit: String?
    var sourceText: String?

    init?(_ metadata: LedgerEventMetadataEntry) {
        guard let kind = LedgerEventIntervalEvidenceKind(rawValue: metadata.keyRawValue),
              LedgerEventMetadataValidation.isSupported(metadata) else {
            return nil
        }
        self.kind = kind
        valueKind = metadata.valueKind
        stringValue = metadata.stringValue
        numberValue = metadata.numberValue
        dateValue = metadata.dateValue
        boolValue = metadata.boolValue
        unit = metadata.unit
        sourceText = metadata.sourceText
    }

    var metadataEntry: LedgerEventMetadataEntry {
        LedgerEventMetadataEntry(
            key: kind.metadataKey,
            valueKind: valueKind,
            stringValue: stringValue,
            numberValue: numberValue,
            dateValue: dateValue,
            boolValue: boolValue,
            unit: unit,
            sourceText: sourceText
        )
    }
}

extension LedgerEvent {
    var intervalEvidence: [LedgerEventIntervalEvidence] {
        metadataEntries.compactMap(LedgerEventIntervalEvidence.init)
    }
}

enum LedgerEventMetadataValidation {
    static func normalizedExtractionEntry(
        keyRawValue: String,
        valueKindRawValue: String,
        stringValue: String?,
        numberValue: Double?,
        dateValue: String?,
        boolValue: Bool?,
        unit: String?,
        sourceText: String?
    ) -> LedgerEventMetadataEntry? {
        guard let normalizedKey = normalizedKey(for: keyRawValue) else { return nil }
        let valueKind = LedgerEventMetadataValueKind(rawValue: valueKindRawValue) ?? .string
        let entry = LedgerEventMetadataEntry(
            keyRawValue: normalizedKey.rawValue,
            valueKindRawValue: valueKind.rawValue,
            stringValue: stringValue?.nilIfEmpty,
            numberValue: numberValue,
            dateValue: dateValue?.nilIfEmpty,
            boolValue: boolValue,
            unit: unit?.nilIfEmpty,
            sourceText: sourceText?.nilIfEmpty
        )
        return isSupported(entry) ? entry : nil
    }

    static func isSupported(_ entry: LedgerEventMetadataEntry) -> Bool {
        allowedValueKinds(for: entry.key).contains(entry.valueKind) && hasValueForKind(entry)
    }

    static func hasValueForKind(_ entry: LedgerEventMetadataEntry) -> Bool {
        switch entry.valueKind {
        case .string:
            entry.stringValue?.nilIfEmpty != nil || entry.sourceText?.nilIfEmpty != nil
        case .number:
            entry.numberValue != nil
        case .date:
            entry.dateValue.flatMap { ExtractionService.parseDate($0) } != nil
        case .boolean:
            entry.boolValue != nil
        }
    }

    private static func normalizedKey(for rawValue: String) -> LedgerEventMetadataKey? {
        if let key = LedgerEventMetadataKey(rawValue: rawValue) {
            return key
        }
        return isUnknownIntervalEvidenceKey(rawValue) ? nil : .other
    }

    private static func isUnknownIntervalEvidenceKey(_ rawValue: String) -> Bool {
        let normalized = rawValue.lowercased()
        return [
            "interval",
            "recurrence",
            "recurring",
            "next_due",
            "package",
            "reset"
        ].contains { normalized.contains($0) }
    }

    private static func allowedValueKinds(for key: LedgerEventMetadataKey) -> Set<LedgerEventMetadataValueKind> {
        switch key {
        case .mileage, .amount, .quantity, .calendarInterval, .mileageInterval,
             .nextDueMileage, .packageQuantity:
            [.number]
        case .dueDate, .nextDueDate:
            [.date]
        case .serviceReset:
            [.boolean]
        case .unit, .vendor, .location, .subtype, .identifier, .sourceText,
             .recurrenceEvidence:
            [.string]
        case .other:
            Set(LedgerEventMetadataValueKind.allCases)
        }
    }
}
