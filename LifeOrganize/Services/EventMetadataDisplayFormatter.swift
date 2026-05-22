import Foundation

struct EventMetadataDisplayFormatter {
    static func summary(
        for entries: [LedgerEventMetadataEntry],
        eventType: LedgerEventType,
        limit: Int,
        labelSeparator: String = ": ",
        itemSeparator: String = " · ",
        terminator: String = ""
    ) -> String? {
        let displayEntries = orderedSummaryEntries(entries, eventType: eventType)
            .compactMap { entry -> String? in
                guard let value = displayValue(for: entry).nilIfEmpty else { return nil }
                return "\(entry.key.displayName)\(labelSeparator)\(value)\(terminator)"
            }
            .prefix(limit)
        guard !displayEntries.isEmpty else { return nil }
        return displayEntries.joined(separator: itemSeparator)
    }

    static func orderedDetailEntries(
        _ entries: [LedgerEventMetadataEntry],
        eventType: LedgerEventType
    ) -> [LedgerEventMetadataEntry] {
        let preferredKeys = detailPreferredKeys
        return entries.enumerated().sorted { lhs, rhs in
            let lhsRank = preferredKeys.firstIndex(of: lhs.element.key) ?? preferredKeys.count
            let rhsRank = preferredKeys.firstIndex(of: rhs.element.key) ?? preferredKeys.count
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func displayValue(for entry: LedgerEventMetadataEntry) -> String {
        switch entry.key {
        case .amount:
            if let amount = entry.numberValue {
                return amountDisplay(amount, unit: entry.unit)
            }
        case .dueDate, .nextDueDate:
            if let dateValue = entry.dateValue?.nilIfEmpty {
                return readableDate(dateValue) ?? dateValue
            }
        case .serviceReset:
            if let boolValue = entry.boolValue {
                return boolValue ? "Yes" : "No"
            }
        default:
            break
        }
        return entry.displayValue
    }

    private static func orderedSummaryEntries(
        _ entries: [LedgerEventMetadataEntry],
        eventType: LedgerEventType
    ) -> [LedgerEventMetadataEntry] {
        let preferredKeys = summaryPreferredKeys(for: eventType)
        let preferred = preferredKeys.compactMap { key in
            entries.first { $0.key == key }
        }
        let remaining = entries.filter { entry in
            !preferredKeys.contains(entry.key)
        }
        return preferred + remaining
    }

    private static func summaryPreferredKeys(for eventType: LedgerEventType) -> [LedgerEventMetadataKey] {
        switch eventType {
        case .maintenance:
            [.mileage, .nextDueMileage, .nextDueDate, .mileageInterval, .calendarInterval, .serviceReset, .vendor, .amount, .location, .dueDate]
        case .purchase:
            [.vendor, .amount, .packageQuantity, .quantity, .location, .identifier, .dueDate, .nextDueDate]
        case .visit:
            [.location, .vendor, .amount, .dueDate]
        case .renewal:
            [.dueDate, .nextDueDate, .calendarInterval, .vendor, .amount, .identifier]
        case .appointment:
            [.dueDate, .location, .vendor]
        case .replacement:
            [.calendarInterval, .nextDueDate, .vendor, .amount, .mileage, .location]
        case .project:
            [.dueDate, .vendor, .amount, .location]
        default:
            [.mileage, .nextDueMileage, .dueDate, .nextDueDate, .vendor, .amount, .location]
        }
    }

    private static let detailPreferredKeys: [LedgerEventMetadataKey] = [
        .dueDate,
        .nextDueDate,
        .mileage,
        .nextDueMileage,
        .mileageInterval,
        .calendarInterval,
        .amount,
        .vendor,
        .location,
        .packageQuantity,
        .quantity,
        .unit,
        .subtype,
        .identifier,
        .serviceReset,
        .recurrenceEvidence,
        .other,
        .sourceText
    ]

    private static func amountDisplay(_ amount: Double, unit: String?) -> String {
        let cleanedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUnit = cleanedUnit?.uppercased()
        if cleanedUnit == nil || normalizedUnit == "USD" || cleanedUnit == "$" {
            return "$\(LedgerDisplayFormatting.decimal(amount, minimumFractionDigits: 2, maximumFractionDigits: 2, locale: Locale(identifier: "en_US_POSIX")))"
        }
        return [LedgerDisplayFormatting.decimal(amount), cleanedUnit]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " ")
    }

    private static func readableDate(_ value: String) -> String? {
        guard let date = DateFormatting.parseDateOnly(value) else { return nil }
        return DateFormatting.string(
            from: date,
            format: "MMM d, yyyy",
            calendar: DateFormatting.utcGregorianCalendar,
            timeZone: DateFormatting.utcGregorianCalendar.timeZone
        )
    }
}
