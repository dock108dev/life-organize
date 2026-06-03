import Foundation

enum TimelineSectionSummaryDisplayMode {
    case compact
    case full
}

struct TimelineSectionSummaryText: Equatable {
    let itemCountText: String
    let timeRangeText: String
    let typeMixText: String

    var text: String {
        Self.joined([itemCountText, timeRangeText, typeMixText])
    }

    func displayText(mode: TimelineSectionSummaryDisplayMode) -> String {
        switch mode {
        case .compact:
            return Self.joined([itemCountText, timeRangeText])
        case .full:
            return text
        }
    }

    private static func joined(_ segments: [String]) -> String {
        segments
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct TimelineSectionSummaryMoment: Equatable {
    let date: Date
    let hasDisplayTime: Bool
}

enum TimelineSectionSummaryFormatting {
    static func timeRangeText(for dates: [Date], calendar: Calendar) -> String {
        timeRangeText(
            for: dates.map { TimelineSectionSummaryMoment(date: $0, hasDisplayTime: true) },
            calendar: calendar
        )
    }

    static func timeRangeText(for moments: [TimelineSectionSummaryMoment], calendar: Calendar) -> String {
        let displayDates = moments.filter(\.hasDisplayTime).map(\.date)
        guard let first = displayDates.min(), let last = displayDates.max() else { return "" }

        if calendar.isDate(first, inSameDayAs: last) {
            if first == last {
                return timeFormatter(calendar: calendar).string(from: first)
            }
            let formatter = timeFormatter(calendar: calendar)
            return "\(formatter.string(from: first))-\(formatter.string(from: last))"
        }

        let formatter = dateRangeFormatter(calendar: calendar, first: first, last: last)
        return "\(formatter.string(from: first))-\(formatter.string(from: last))"
    }

    private static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    private static func dateRangeFormatter(calendar: Calendar, first: Date, last: Date) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: first) == calendar.component(.year, from: last)
            ? "MMM d"
            : "MMM d, yyyy"
        return formatter
    }
}
