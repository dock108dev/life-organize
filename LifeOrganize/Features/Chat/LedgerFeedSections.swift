import Foundation

enum LedgerFeedDateGroup: String, CaseIterable, Identifiable {
    case upcoming
    case today
    case yesterday
    case thisWeek
    case earlier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .thisWeek:
            return "This Week"
        case .earlier:
            return "Earlier"
        }
    }
}

struct LedgerFeedDateGrouping {
    let calendar: Calendar
    let now: Date

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    func group(for date: Date) -> LedgerFeedDateGroup {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)

        if day > today {
            return .upcoming
        }
        if day == today {
            return .today
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return .earlier
        }
        if day == yesterday {
            return .yesterday
        }

        if calendar.isDate(day, equalTo: today, toGranularity: .weekOfYear),
           calendar.isDate(day, equalTo: today, toGranularity: .yearForWeekOfYear) {
            return .thisWeek
        }

        return .earlier
    }
}

struct LedgerFeedSection: Identifiable {
    let day: Date
    let group: LedgerFeedDateGroup
    let title: String
    let subtitle: String?
    let summary: LedgerFeedSectionSummary
    let items: [LedgerFeedItem]

    var id: String {
        "\(DateFormatting.dateOnlyString(day, calendar: calendar, timeZone: calendar.timeZone))-\(group.rawValue)"
    }

    private let calendar: Calendar

    init(day: Date, items: [LedgerFeedItem], calendar: Calendar, now: Date) {
        self.day = calendar.startOfDay(for: day)
        self.group = LedgerFeedDateGrouping(calendar: calendar, now: now).group(for: day)
        let title = LedgerTimelineSectionTitle(day: day, calendar: calendar, now: now)
        self.title = title.primary
        self.subtitle = title.secondary
        self.summary = LedgerFeedSectionSummary(items: items, calendar: calendar)
        self.items = items
        self.calendar = calendar
    }
}

struct LedgerTimelineSectionTitle {
    let primary: String
    let secondary: String?

    init(day: Date, calendar: Calendar, now: Date) {
        let today = calendar.startOfDay(for: now)
        let normalizedDay = calendar.startOfDay(for: day)

        if normalizedDay > today {
            primary = Self.monthDay(normalizedDay, calendar: calendar, includeYear: !Self.isSameYear(normalizedDay, now, calendar: calendar))
            secondary = "Upcoming · \(Self.weekday(normalizedDay, calendar: calendar))"
        } else if normalizedDay == today {
            primary = "Today"
            secondary = Self.weekdayMonthDay(normalizedDay, calendar: calendar)
        } else if normalizedDay == calendar.date(byAdding: .day, value: -1, to: today) {
            primary = "Yesterday"
            secondary = Self.weekdayMonthDay(normalizedDay, calendar: calendar)
        } else if calendar.isDate(normalizedDay, equalTo: today, toGranularity: .weekOfYear),
                  calendar.isDate(normalizedDay, equalTo: today, toGranularity: .yearForWeekOfYear) {
            primary = Self.weekday(normalizedDay, calendar: calendar)
            secondary = Self.monthDay(normalizedDay, calendar: calendar)
        } else if Self.isSameYear(normalizedDay, now, calendar: calendar) {
            primary = Self.monthDay(normalizedDay, calendar: calendar)
            secondary = Self.weekday(normalizedDay, calendar: calendar)
        } else {
            primary = Self.monthDay(normalizedDay, calendar: calendar, includeYear: true)
            secondary = Self.weekday(normalizedDay, calendar: calendar)
        }
    }

    private static func weekdayMonthDay(_ date: Date, calendar: Calendar) -> String {
        "\(weekdayAbbreviation(date, calendar: calendar)), \(monthDay(date, calendar: calendar))"
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        DateFormatting.string(from: date, format: "EEEE", calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func weekdayAbbreviation(_ date: Date, calendar: Calendar) -> String {
        DateFormatting.string(from: date, format: "EEE", calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func monthDay(_ date: Date, calendar: Calendar, includeYear: Bool = false) -> String {
        DateFormatting.string(
            from: date,
            format: includeYear ? "MMM d, yyyy" : "MMM d",
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }

    private static func isSameYear(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        calendar.component(.year, from: lhs) == calendar.component(.year, from: rhs)
    }
}

struct LedgerFeedSectionSummary: Equatable {
    let itemCountText: String
    let timeRangeText: String
    let typeMixText: String

    var text: String {
        summaryText.text
    }

    func displayText(mode: TimelineSectionSummaryDisplayMode) -> String {
        summaryText.displayText(mode: mode)
    }

    init(items: [LedgerFeedItem], calendar: Calendar) {
        itemCountText = LedgerDisplayFormatting.count(items.count, singular: "item", plural: "items")
        timeRangeText = TimelineSectionSummaryFormatting.timeRangeText(
            for: items.map {
                TimelineSectionSummaryMoment(
                    date: $0.timelineDate(calendar: calendar),
                    hasDisplayTime: $0.hasDisplayTime(calendar: calendar)
                )
            },
            calendar: calendar
        )
        typeMixText = Self.typeMixText(for: items)
    }

    private var summaryText: TimelineSectionSummaryText {
        TimelineSectionSummaryText(
            itemCountText: itemCountText,
            timeRangeText: timeRangeText,
            typeMixText: typeMixText
        )
    }

    private static func typeMixText(for items: [LedgerFeedItem]) -> String {
        let counts = Dictionary(grouping: items, by: \.summaryKind).mapValues(\.count)
        let orderedKinds: [LedgerFeedSummaryKind] = [.event, .reminder, .note, .message]

        return orderedKinds.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(count) \(kind.label(count: count))"
        }
        .joined(separator: ", ")
    }
}

enum LedgerFeedSummaryKind: Hashable {
    case message
    case event
    case reminder
    case note

    func label(count: Int) -> String {
        switch self {
        case .message:
            return count == 1 ? "timeline entry" : "timeline entries"
        case .event:
            return count == 1 ? "event" : "events"
        case .reminder:
            return count == 1 ? "reminder" : "reminders"
        case .note:
            return count == 1 ? "note" : "notes"
        }
    }
}
