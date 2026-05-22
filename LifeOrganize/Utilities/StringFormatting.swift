import Foundation

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum LedgerDisplayFormatting {
    static func count(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    static func ellipsized(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxLength > 3, trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength - 3)) + "..."
    }

    static func noteTitle(for text: String, emptyTitle: String = "Untitled Note", maxLength: Int = 48) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return emptyTitle }
        return trimmed.count <= maxLength ? trimmed : String(trimmed.prefix(maxLength)) + "..."
    }

    static func mileage(_ mileage: Int) -> String {
        "\(integer(mileage)) mi"
    }

    static func integer(_ value: Int) -> String {
        decimal(Double(value), maximumFractionDigits: 0)
    }

    static func decimal(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 3,
        locale: Locale? = nil
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ value: Double, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
