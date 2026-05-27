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
            for: items.map { $0.timelineDate(calendar: calendar) },
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

private enum LedgerFeedSummaryKind: Hashable {
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

enum LedgerFeedItem: Identifiable {
    case message(ChatMessage)
    case event(LedgerEvent)
    case reminder(LedgerRule)
    case note(LedgerNote)

    var id: String {
        switch self {
        case .message(let message):
            return Self.messageID(for: message.id)
        case .event(let event):
            return "event-\(event.id.uuidString)"
        case .reminder(let reminder):
            return "reminder-\(reminder.id.uuidString)"
        case .note(let note):
            return "note-\(note.id.uuidString)"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .message(let message):
            return "timeline-row-message-\(message.id.uuidString)"
        case .event(let event):
            return "timeline-row-event-\(event.id.uuidString)"
        case .reminder(let reminder):
            return "timeline-row-rule-\(reminder.id.uuidString)"
        case .note(let note):
            return "timeline-row-note-\(note.id.uuidString)"
        }
    }

    var timelineDate: Date {
        timelineDate(calendar: .current)
    }

    func timelineDate(calendar: Calendar) -> Date {
        switch self {
        case .message(let message):
            return message.createdAt
        case .event(let event):
            let legacyNormalized = DateFormatting.normalizedLegacyUTCDateOnlyForDisplay(event.occurredAt, calendar: calendar)
            guard let sourceMessage = event.sourceMessage else {
                return legacyNormalized
            }
            return DateFormatting.normalizedUndatedExtractionDateForDisplay(
                legacyNormalized,
                sourceDate: sourceMessage.createdAt,
                contextText: [event.rawText, event.title].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
        case .reminder(let reminder):
            if let manuallyDeactivatedAt = reminder.manuallyDeactivatedAt {
                return manuallyDeactivatedAt
            }
            let legacyNormalized = DateFormatting.normalizedLegacyUTCDateOnlyForDisplay(reminder.startsAt, calendar: calendar)
            guard let sourceMessage = reminder.sourceMessage else {
                return legacyNormalized
            }
            return DateFormatting.normalizedUndatedExtractionDateForDisplay(
                legacyNormalized,
                sourceDate: sourceMessage.createdAt,
                contextText: [reminder.rawText, reminder.title].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
        case .note(let note):
            return note.createdAt
        }
    }

    var occurredAt: Date {
        timelineDate
    }

    var reviewItemTarget: (type: LedgerReviewItemTargetType, id: UUID)? {
        switch self {
        case .message(let message):
            return (.chatMessage, message.id)
        case .event(let event):
            return (.event, event.id)
        case .reminder(let reminder):
            return (.rule, reminder.id)
        case .note:
            return nil
        }
    }

    var reviewOrigin: LedgerReviewOrigin? {
        guard let target = reviewItemTarget else { return nil }
        return LedgerReviewOrigin(targetType: target.type, targetID: target.id, label: originLabel)
    }

    private var originLabel: String {
        switch self {
        case .message:
            return "Timeline entry"
        case .event:
            return "Event"
        case .reminder:
            return "Reminder"
        case .note:
            return "Note"
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message):
            return message.createdAt
        case .event(let event):
            return event.createdAt
        case .reminder(let reminder):
            return reminder.createdAt
        case .note(let note):
            return note.createdAt
        }
    }

    var kindRank: Int {
        switch self {
        case .message:
            return 0
        case .event:
            return 1
        case .reminder:
            return 2
        case .note:
            return 3
        }
    }

    fileprivate var summaryKind: LedgerFeedSummaryKind {
        switch self {
        case .message:
            return .message
        case .event:
            return .event
        case .reminder:
            return .reminder
        case .note:
            return .note
        }
    }

    static func messageID(for id: UUID) -> String {
        "message-\(id.uuidString)"
    }

    static func newestFirst(_ lhs: LedgerFeedItem, _ rhs: LedgerFeedItem, calendar: Calendar) -> Bool {
        let lhsTimelineDate = lhs.timelineDate(calendar: calendar)
        let rhsTimelineDate = rhs.timelineDate(calendar: calendar)
        if lhsTimelineDate != rhsTimelineDate {
            return lhsTimelineDate > rhsTimelineDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.kindRank != rhs.kindRank {
            return lhs.kindRank < rhs.kindRank
        }
        return lhs.id < rhs.id
    }

    static func chronological(_ lhs: LedgerFeedItem, _ rhs: LedgerFeedItem, calendar: Calendar) -> Bool {
        let lhsTimelineDate = lhs.timelineDate(calendar: calendar)
        let rhsTimelineDate = rhs.timelineDate(calendar: calendar)
        if lhsTimelineDate != rhsTimelineDate {
            return lhsTimelineDate < rhsTimelineDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        if lhs.kindRank != rhs.kindRank {
            return lhs.kindRank < rhs.kindRank
        }
        return lhs.id < rhs.id
    }
}

struct LedgerFeedProjection {
    let calendar: Calendar
    let now: Date
    let upcomingReminderHorizonDays: Int

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = Date(), upcomingReminderHorizonDays: Int = 45) {
        self.calendar = calendar
        self.now = now
        self.upcomingReminderHorizonDays = upcomingReminderHorizonDays
    }

    func items(
        messages: [ChatMessage],
        events: [LedgerEvent],
        reminders: [LedgerRule],
        notes: [LedgerNote]
    ) -> [LedgerFeedItem] {
        (
            messages.filter(\.requiresPrimaryFeedAttention).map(LedgerFeedItem.message)
                + events.map(LedgerFeedItem.event)
                + reminders.filter(shouldIncludeReminder).map(LedgerFeedItem.reminder)
                + notes.map(LedgerFeedItem.note)
        )
        .sorted { LedgerFeedItem.chronological($0, $1, calendar: calendar) }
    }

    func sections(
        messages: [ChatMessage],
        events: [LedgerEvent],
        reminders: [LedgerRule],
        notes: [LedgerNote]
    ) -> [LedgerFeedSection] {
        let grouped = Dictionary(
            grouping: items(messages: messages, events: events, reminders: reminders, notes: notes),
            by: { calendar.startOfDay(for: $0.timelineDate(calendar: calendar)) }
        )

        return grouped.keys.sorted().compactMap { day in
            guard let items = grouped[day], !items.isEmpty else { return nil }
            return LedgerFeedSection(day: day, items: items, calendar: calendar, now: now)
        }
    }

    private func shouldIncludeReminder(_ reminder: LedgerRule) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(byAdding: .day, value: upcomingReminderHorizonDays, to: today) else {
            return true
        }

        if reminder.manuallyDeactivatedAt != nil {
            return true
        }
        return reminder.startsAt < horizonEnd
    }
}

struct TimelineDefaultVisibility {
    let calendar: Calendar
    let now: Date
    let pastWindowDays: Int

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = Date(), pastWindowDays: Int = 2) {
        self.calendar = calendar
        self.now = now
        self.pastWindowDays = pastWindowDays
    }

    func isVisibleByDefault(_ section: LedgerFeedSection) -> Bool {
        if section.group == .upcoming {
            return true
        }

        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -pastWindowDays, to: today) else {
            return true
        }
        return section.day >= cutoff
    }
}
