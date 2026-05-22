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
}
