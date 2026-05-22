import Foundation

struct ThingPreviewSnapshot {
    let title: String
    let categoryTitle: String?
    let detailsSnippet: String?
    let aliasSummary: String?
    let eventCount: Int
    let fallbackLastEventAt: Date?
    let latestEventTitle: String?
    let latestEventDate: Date?
    let latestEventMetadataSummary: String?
    let latestEventNoteSnippet: String?
    let activeReminderCount: Int
    let primaryActiveReminderTitle: String?
    let primaryActiveReminderState: String?
    let upcomingReminderTitle: String?
    let upcomingReminderDate: Date?
    let upcomingReminderRelativeDueText: String?
    let upcomingReminderKind: UpcomingReminderKind?
    let noteCount: Int
    let latestNoteSnippet: String?
    let continuityLines: [ContinuityLine]

    enum UpcomingReminderKind: Equatable {
        case starts
        case expires

        var displayTitle: String {
            switch self {
            case .starts:
                "Upcoming"
            case .expires:
                "Expires"
            }
        }
    }

    struct ContinuityLine: Equatable {
        let label: String
        let value: String
        let detail: String?
        let tone: LedgerTone
    }

    init(
        thing: Thing,
        now: Date = Date(),
        calendar: Calendar = .current,
        ruleStatus: RuleStatusService = RuleStatusService()
    ) {
        let continuityService = ReminderContinuityPresentationService(statusService: ruleStatus)
        let sortedEvents = thing.events.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let latestEvent = sortedEvents.first

        let activeReminders = thing.rules
            .filter { ruleStatus.status(for: $0, at: now) == .active }
            .sorted {
                switch ($0.expiresAt, $1.expiresAt) {
                case let (lhs?, rhs?) where lhs != rhs:
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    if $0.startsAt != $1.startsAt {
                        return $0.startsAt > $1.startsAt
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }

        let scheduledStarts = thing.rules
            .filter { ruleStatus.status(for: $0, at: now) == .scheduled }
            .map { (rule: $0, date: $0.startsAt, kind: UpcomingReminderKind.starts) }
        let activeExpirations = activeReminders.compactMap { rule in
            rule.expiresAt.map { (rule: rule, date: $0, kind: UpcomingReminderKind.expires) }
        }
        let upcomingReminder = (scheduledStarts + activeExpirations)
            .filter { $0.date >= now }
            .sorted {
                if $0.date != $1.date {
                    return $0.date < $1.date
                }
                return $0.rule.title.localizedCaseInsensitiveCompare($1.rule.title) == .orderedAscending
            }
            .first

        let latestNote = thing.notes
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.createdAt > $1.createdAt
            }
            .first

        title = thing.name.nilIfEmpty ?? "Untitled thing"
        categoryTitle = thing.category.map(\.displayName)
        detailsSnippet = thing.details.nilIfEmpty
        aliasSummary = Self.aliasSummary(for: thing.aliases)
        eventCount = sortedEvents.count
        fallbackLastEventAt = thing.lastEventAt
        latestEventTitle = latestEvent?.title.nilIfEmpty
        latestEventDate = latestEvent?.occurredAt
        latestEventMetadataSummary = latestEvent.flatMap {
            EventMetadataDisplayFormatter.summary(
                for: Self.listPreviewMetadataEntries(for: $0),
                eventType: $0.eventType,
                limit: 2
            )
        }
        latestEventNoteSnippet = latestEvent?.note?.nilIfEmpty
        activeReminderCount = activeReminders.count
        primaryActiveReminderTitle = activeReminders.first.map { Self.reminderTitle(for: $0) }
        primaryActiveReminderState = activeReminders.first.map { continuityService.presentation(for: $0, at: now).primaryLine }
        upcomingReminderTitle = upcomingReminder.map { Self.reminderTitle(for: $0.rule) }
        upcomingReminderDate = upcomingReminder?.date
        upcomingReminderRelativeDueText = upcomingReminder.map {
            Self.relativeDueText(for: $0.date, now: now, calendar: calendar)
        }
        upcomingReminderKind = upcomingReminder?.kind
        noteCount = thing.notes.count
        latestNoteSnippet = latestNote?.text.nilIfEmpty
        continuityLines = Self.continuityLines(
            events: sortedEvents,
            fallbackLastEventAt: thing.lastEventAt,
            latestEventMetadataSummary: latestEventMetadataSummary,
            latestEventNoteSnippet: latestEventNoteSnippet,
            activeReminderCount: activeReminders.count,
            primaryActiveReminderTitle: primaryActiveReminderTitle,
            primaryActiveReminderState: primaryActiveReminderState,
            upcomingReminderTitle: upcomingReminderTitle,
            upcomingReminderKind: upcomingReminderKind,
            upcomingReminderRelativeDueText: upcomingReminderRelativeDueText,
            upcomingReminderDate: upcomingReminderDate,
            latestNoteSnippet: latestNoteSnippet,
            detailsSnippet: detailsSnippet,
            aliasSummary: aliasSummary,
            now: now,
            calendar: calendar
        )
    }

    var footerItems: [String] {
        var items: [String] = []
        if eventCount > 0 {
            items.append(LedgerDisplayFormatting.count(eventCount, singular: "event", plural: "events"))
        }
        if noteCount > 0 {
            items.append(LedgerDisplayFormatting.count(noteCount, singular: "note", plural: "notes"))
        }
        return items
    }

    var hasPreviewContent: Bool {
        latestEventTitle != nil
            || eventCount > 0
            || fallbackLastEventAt != nil
            || primaryActiveReminderTitle != nil
            || upcomingReminderTitle != nil
            || latestNoteSnippet != nil
            || detailsSnippet != nil
    }

    private static func aliasSummary(for aliases: [String]) -> String? {
        let cleanedAliases = aliases.compactMap(\.nilIfEmpty)
        guard !cleanedAliases.isEmpty else { return nil }
        if cleanedAliases.count <= 3 {
            return cleanedAliases.joined(separator: ", ")
        }
        return "\(cleanedAliases.count) aliases"
    }

    private static func reminderTitle(for rule: LedgerRule) -> String {
        rule.title.nilIfEmpty ?? "Saved reminder"
    }

    private static func listPreviewMetadataEntries(for event: LedgerEvent) -> [LedgerEventMetadataEntry] {
        let operationalEntries = event.metadataEntries.filter { entry in
            switch entry.key {
            case .sourceText, .identifier:
                return false
            case .location:
                return isProductFacingLocation(entry, eventType: event.eventType)
            default:
                return true
            }
        }

        return operationalEntries.isEmpty ? productFacingFallbackMetadataEntries(for: event) : operationalEntries
    }

    private static func isProductFacingLocation(
        _ entry: LedgerEventMetadataEntry,
        eventType: LedgerEventType
    ) -> Bool {
        guard entry.displayValue.nilIfEmpty != nil else { return false }
        switch eventType {
        case .appointment, .maintenance, .project, .visit:
            return true
        default:
            return false
        }
    }

    private static func productFacingFallbackMetadataEntries(for event: LedgerEvent) -> [LedgerEventMetadataEntry] {
        event.metadataEntries.filter { entry in
            entry.key == .location && isProductFacingLocation(entry, eventType: event.eventType)
        }
    }

    private static func continuityLines(
        events: [LedgerEvent],
        fallbackLastEventAt: Date?,
        latestEventMetadataSummary: String?,
        latestEventNoteSnippet: String?,
        activeReminderCount: Int,
        primaryActiveReminderTitle: String?,
        primaryActiveReminderState: String?,
        upcomingReminderTitle: String?,
        upcomingReminderKind: UpcomingReminderKind?,
        upcomingReminderRelativeDueText: String?,
        upcomingReminderDate: Date?,
        latestNoteSnippet: String?,
        detailsSnippet: String?,
        aliasSummary: String?,
        now: Date,
        calendar: Calendar
    ) -> [ContinuityLine] {
        var lines: [ContinuityLine] = []
        let latestEvent = events.first

        if let latestEvent {
            let detail = [
                DateFormatting.ledgerDateSummary(latestEvent.occurredAt, calendar: calendar, now: now),
                latestEventMetadataSummary
            ].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
            lines.append(ContinuityLine(
                label: "Last event",
                value: latestEvent.title.nilIfEmpty ?? "Saved event",
                detail: detail.nilIfEmpty,
                tone: .success
            ))
        } else if let fallbackLastEventAt {
            lines.append(ContinuityLine(
                label: "Last event",
                value: DateFormatting.ledgerDateSummary(fallbackLastEventAt, calendar: calendar, now: now),
                detail: nil,
                tone: .success
            ))
        }

        if activeReminderCount == 1,
           let title = primaryActiveReminderTitle,
           let state = primaryActiveReminderState {
            lines.append(ContinuityLine(label: "Reminder", value: title, detail: state, tone: .attention))
        } else if activeReminderCount > 1,
                  let title = primaryActiveReminderTitle,
                  let state = primaryActiveReminderState {
            lines.append(ContinuityLine(
                label: "\(activeReminderCount) reminders",
                value: title,
                detail: state,
                tone: .attention
            ))
        }

        if let title = upcomingReminderTitle,
           let kind = upcomingReminderKind,
           shouldShowUpcomingReminder(
               title: title,
               kind: kind,
               activeReminderCount: activeReminderCount,
               primaryActiveReminderTitle: primaryActiveReminderTitle
           ) {
            let detail = upcomingReminderRelativeDueText
                ?? upcomingReminderDate.map { DateFormatting.ledgerDateSummary($0, calendar: calendar, now: now) }
            lines.append(ContinuityLine(label: kind.displayTitle, value: title, detail: detail, tone: .attention))
        }

        if let continuity = inferredContinuity(
            events: events,
            existingReminderTitle: primaryActiveReminderTitle ?? upcomingReminderTitle,
            calendar: calendar
        ) {
            lines.append(continuity)
        }

        if let latestNoteSnippet {
            lines.append(ContinuityLine(label: "Recent note", value: latestNoteSnippet, detail: nil, tone: .note))
        } else if let latestEventNoteSnippet {
            lines.append(ContinuityLine(label: "Event note", value: latestEventNoteSnippet, detail: nil, tone: .neutral))
        } else if let detailsSnippet {
            lines.append(ContinuityLine(label: "Details", value: detailsSnippet, detail: nil, tone: .neutral))
        }

        if lines.isEmpty {
            lines.append(ContinuityLine(label: "History", value: "No records yet", detail: nil, tone: .muted))
        }

        return lines
    }

    private static func shouldShowUpcomingReminder(
        title: String,
        kind: UpcomingReminderKind,
        activeReminderCount: Int,
        primaryActiveReminderTitle: String?
    ) -> Bool {
        if activeReminderCount == 0 { return true }
        if kind == .expires { return true }
        return title != primaryActiveReminderTitle
    }

    private static func inferredContinuity(
        events: [LedgerEvent],
        existingReminderTitle: String?,
        calendar: Calendar
    ) -> ContinuityLine? {
        let serviceEvents = events.filter { $0.eventType == .maintenance }
        if let latest = serviceEvents.first,
           let previous = serviceEvents.dropFirst().first,
           let latestMileage = mileage(in: latest),
           let previousMileage = mileage(in: previous) {
            let mileageInterval = max(0, latestMileage - previousMileage)
            guard mileageInterval > 0 else { return nil }
            let dayInterval = calendar.dateComponents([.day], from: previous.occurredAt, to: latest.occurredAt).day
            let nextDate = dayInterval.flatMap { calendar.date(byAdding: .day, value: max($0, 1), to: latest.occurredAt) }
            let detail = [
                "Next \(LedgerDisplayFormatting.mileage(latestMileage + mileageInterval))",
                nextDate.map { DateFormatting.fullDate.string(from: $0) }
            ].compactMap { $0 }.joined(separator: " · ")
            return ContinuityLine(
                label: "Service rhythm",
                value: "About every \(LedgerDisplayFormatting.mileage(mileageInterval))",
                detail: detail.nilIfEmpty,
                tone: .info
            )
        }

        let consumableEvents = events.filter { $0.eventType == .replacement || $0.eventType == .purchase }
        guard let latest = consumableEvents.first,
              let previous = consumableEvents.dropFirst().first else {
            return nil
        }
        let dayInterval = max(1, calendar.dateComponents([.day], from: previous.occurredAt, to: latest.occurredAt).day ?? 0)
        let nextCheck = calendar.date(byAdding: .day, value: dayInterval, to: latest.occurredAt)
        return ContinuityLine(
            label: latest.eventType == .replacement ? "Replacement rhythm" : "Purchase rhythm",
            value: "About every \(dayInterval) \(dayInterval == 1 ? "day" : "days")",
            detail: existingReminderTitle.map { "Reminder already saved: \($0)" }
                ?? nextCheck.map { "Next check to review: \(DateFormatting.fullDate.string(from: $0))" },
            tone: .info
        )
    }

    private static func mileage(in event: LedgerEvent) -> Int? {
        event.metadataEntries.first { $0.key == .mileage }?.numberValue.map { Int($0.rounded()) }
    }

    private static func relativeDueText(for date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }
}
