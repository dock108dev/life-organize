import Foundation

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
            guard let sourceMessage = event.sourceMessage else {
                return event.occurredAt
            }
            return DateFormatting.normalizedUndatedExtractionDateForDisplay(
                event.occurredAt,
                sourceDate: sourceMessage.createdAt,
                contextText: [event.rawText, event.title].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
        case .reminder(let reminder):
            if let manuallyDeactivatedAt = reminder.manuallyDeactivatedAt {
                return manuallyDeactivatedAt
            }
            guard let sourceMessage = reminder.sourceMessage else {
                return reminder.startsAt
            }
            return DateFormatting.normalizedUndatedExtractionDateForDisplay(
                reminder.startsAt,
                sourceDate: sourceMessage.createdAt,
                contextText: [reminder.rawText, reminder.title].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
        case .note(let note):
            return note.createdAt
        }
    }

    func hasDisplayTime(calendar: Calendar) -> Bool {
        switch self {
        case .message, .note:
            return true
        case .event(let event):
            return DateFormatting.shouldDisplayTime(
                for: event.occurredAt,
                contextText: [event.rawText, event.title, event.note].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
        case .reminder(let reminder):
            if reminder.manuallyDeactivatedAt != nil {
                return true
            }
            return DateFormatting.shouldDisplayTime(
                for: reminder.startsAt,
                contextText: [reminder.rawText, reminder.title, reminder.reason].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                calendar: calendar
            )
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

    var summaryKind: LedgerFeedSummaryKind {
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
        .sorted { LedgerFeedItem.newestFirst($0, $1, calendar: calendar) }
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

        return grouped.keys.sorted(by: sectionSort).compactMap { day in
            guard let items = grouped[day], !items.isEmpty else { return nil }
            return LedgerFeedSection(day: day, items: items, calendar: calendar, now: now)
        }
    }

    private func sectionSort(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsGroup = LedgerFeedDateGrouping(calendar: calendar, now: now).group(for: lhs)
        let rhsGroup = LedgerFeedDateGrouping(calendar: calendar, now: now).group(for: rhs)

        if lhsGroup == .upcoming, rhsGroup != .upcoming {
            return true
        }
        if lhsGroup != .upcoming, rhsGroup == .upcoming {
            return false
        }
        return lhs > rhs
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
