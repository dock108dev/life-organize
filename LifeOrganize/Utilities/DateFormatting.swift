import Foundation

enum DateFormatting {
    static let utcGregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static let ledgerTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func normalizedDateOnly(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    static func isNormalizedDateOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return components.hour == 12
            && components.minute == 0
            && components.second == 0
            && components.nanosecond == 0
    }

    static func shouldDisplayTime(
        for date: Date,
        contextText: String,
        calendar: Calendar = .current
    ) -> Bool {
        !isNormalizedDateOnly(date, calendar: calendar) || containsExplicitClockTimeCue(contextText)
    }

    static func normalizedUndatedExtractionDateForDisplay(
        _ date: Date,
        sourceDate: Date,
        contextText: String,
        calendar: Calendar = .current
    ) -> Date {
        guard !containsExplicitTemporalCue(contextText),
              isNormalizedDateOnly(date, calendar: calendar),
              calendar.startOfDay(for: date) != calendar.startOfDay(for: sourceDate) else {
            return date
        }
        return normalizedDateOnly(sourceDate, calendar: calendar)
    }

    static func containsExplicitTemporalCue(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let temporalWords = [
            "today", "tonight", "tomorrow", "yesterday", "next", "last", "this",
            "week", "weeks", "weekend", "weekends", "month", "months", "year", "years",
            "day", "days", "due", "deadline", "until", "ago", "later",
            "jan", "january", "feb", "february", "mar", "march", "apr", "april",
            "may", "jun", "june", "jul", "july", "aug", "august", "sep", "sept",
            "september", "oct", "october", "nov", "november", "dec", "december",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "wed", "thu", "fri", "sat", "sun"
        ]
        if temporalWords.contains(where: { lowercased.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
            return true
        }
        return lowercased.range(of: #"\b\d{1,2}([/-]\d{1,2}|:\d{2}| ?(am|pm))\b"#, options: .regularExpression) != nil
    }

    static func containsExplicitClockTimeCue(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.range(of: #"\b\d{1,2}(:\d{2})?\s?(am|pm)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lowercased.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil {
            return true
        }
        return lowercased.range(of: #"\b(noon|midnight)\b"#, options: .regularExpression) != nil
    }

    static func dateOnlyString(
        _ date: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        string(from: date, format: "yyyy-MM-dd", calendar: calendar, timeZone: timeZone)
    }

    static func gregorianDateOnlyString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return dateOnlyString(date, calendar: calendar, timeZone: timeZone)
    }

    static func parseDateOnly(_ value: String, calendar: Calendar? = nil) -> Date? {
        let calendar = calendar ?? utcGregorianCalendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    static func filenameTimestamp(
        _ date: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        string(from: date, format: "yyyy-MM-dd-HHmm", calendar: calendar, timeZone: timeZone)
    }

    static func isoDateTimeString(
        _ date: Date,
        timeZone: TimeZone = .current,
        formatOptions: ISO8601DateFormatter.Options = [.withInternetDateTime]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = formatOptions
        return formatter.string(from: date)
    }

    static func parseISODateTime(_ value: String) -> Date? {
        isoDateTimeFormatter(formatOptions: [.withInternetDateTime]).date(from: value)
            ?? isoDateTimeFormatter(formatOptions: [.withInternetDateTime, .withFractionalSeconds]).date(from: value)
    }

    static func string(
        from date: Date,
        format: String,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func inclusiveDateRangeSummary(
        start: Date,
        endExclusive: Date,
        calendar: Calendar
    ) -> String {
        let end = calendar.date(byAdding: .second, value: -1, to: endExclusive) ?? endExclusive
        let format = calendar.component(.year, from: start) == calendar.component(.year, from: end) ? "MMM d" : "MMM d, yyyy"
        let startText = string(from: start, format: format, calendar: calendar, timeZone: calendar.timeZone)
        let endText = string(from: end, format: format, calendar: calendar, timeZone: calendar.timeZone)
        return startText == endText ? startText : "\(startText)-\(endText)"
    }

    static func ledgerDateSummary(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return string(from: date, format: "MMM d", calendar: calendar, timeZone: calendar.timeZone)
        }
        return shortDate.string(from: date)
    }

    private static func isoDateTimeFormatter(formatOptions: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        return formatter
    }
}
