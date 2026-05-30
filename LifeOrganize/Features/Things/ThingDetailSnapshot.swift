import Foundation

struct ThingDetailSnapshot {
    let events: [LedgerEvent]
    let notes: [LedgerNote]
    let activeReminders: [LedgerRule]
    let upcomingReminders: [LedgerRule]
    let inactiveReminders: [LedgerRule]
    let status: OperationalStatus
    let nextReminder: LedgerRule?
    let latestActivity: Activity?
    let statusSummary: SummaryMetric
    let reminderSummary: SummaryMetric
    let latestEventSummary: SummaryMetric?
    let latestNoteSummary: SummaryMetric?
    let primaryOperationalSummary: SummaryMetric?
    let continuitySummary: SummaryMetric?
    let recentActivitySummary: SummaryMetric?
    let reminderHistorySummary: SummaryMetric?
    let timelineEntryPoints: [TimelineEntryPoint]
    let identityRows: [SummaryMetric]
    let diagnosticRows: [SummaryMetric]

    enum OperationalStatus: String {
        case active = "Active"
        case quiet = "Quiet"
        case historical = "Historical"
    }

    struct Activity {
        let title: String
        let date: Date
    }

    struct SummaryMetric: Equatable {
        let label: String
        let value: String
        let detail: String?
    }

    struct TimelineEntryPoint: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
        let detail: String?
        let navigationTarget: LocalSearchNavigationTarget
    }

    init(
        thing: Thing,
        now: Date = Date(),
        calendar: Calendar = .current,
        ruleStatus: RuleStatusService = RuleStatusService()
    ) {
        let continuityService = ReminderContinuityPresentationService(statusService: ruleStatus)
        events = Self.sortedEvents(thing.events)
        notes = Self.sortedNotes(thing.notes)
        let active = continuityService.rules(thing.rules, in: .now, at: now)
        let scheduled = continuityService.rules(thing.rules, in: .comingUp, at: now)
        activeReminders = active
        upcomingReminders = active + scheduled
        inactiveReminders = continuityService.rules(thing.rules, in: .review, at: now)
            + continuityService.rules(thing.rules, in: .paused, at: now)
        nextReminder = active.first ?? scheduled.first
        latestActivity = Self.latestActivity(events: events, notes: notes, reminders: thing.rules)
        status = Self.status(
            activeReminderCount: activeReminders.count,
            latestActivityDate: latestActivity?.date,
            now: now,
            calendar: calendar
        )
        statusSummary = Self.statusSummary(status: status, activeReminderCount: active.count, latestActivity: latestActivity)
        reminderSummary = Self.reminderSummary(
            activeReminders: active,
            scheduledReminders: scheduled,
            inactiveReminderCount: inactiveReminders.count,
            ruleStatus: ruleStatus,
            now: now
        )
        latestEventSummary = Self.latestEventSummary(events.first)
        latestNoteSummary = Self.latestNoteSummary(notes.first)
        primaryOperationalSummary = Self.primaryOperationalSummary(events: events, now: now, calendar: calendar)
        continuitySummary = Self.continuitySummary(
            events: events,
            activeReminders: active,
            scheduledReminders: scheduled,
            calendar: calendar
        )
        recentActivitySummary = Self.recentActivitySummary(latestActivity, now: now, calendar: calendar)
        reminderHistorySummary = Self.reminderHistorySummary(
            inactiveReminders: inactiveReminders,
            ruleStatus: ruleStatus,
            now: now
        )
        timelineEntryPoints = Self.timelineEntryPoints(events: events, notes: notes, reminders: thing.rules, now: now, calendar: calendar)
        identityRows = Self.identityRows(thing)
        diagnosticRows = Self.diagnosticRows(thing)
    }

    var countSummary: String {
        let parts = [
            events.isEmpty ? nil : LedgerDisplayFormatting.count(events.count, singular: "event", plural: "events"),
            notes.isEmpty ? nil : LedgerDisplayFormatting.count(notes.count, singular: "note", plural: "notes"),
            activeReminders.isEmpty ? nil : LedgerDisplayFormatting.count(activeReminders.count, singular: "active reminder", plural: "active reminders")
        ].compactMap(\.self)
        return parts.isEmpty ? "No saved activity" : parts.joined(separator: " · ")
    }

    var hasHistory: Bool {
        !events.isEmpty || !notes.isEmpty || !upcomingReminders.isEmpty || !inactiveReminders.isEmpty
    }

    private static func sortedEvents(_ events: [LedgerEvent]) -> [LedgerEvent] {
        events.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func sortedNotes(_ notes: [LedgerNote]) -> [LedgerNote] {
        notes.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func latestActivity(
        events: [LedgerEvent],
        notes: [LedgerNote],
        reminders: [LedgerRule]
    ) -> Activity? {
        var activities: [Activity] = []
        if let event = events.first {
            activities.append(Activity(title: event.title, date: event.occurredAt))
        }
        if let note = notes.first {
            activities.append(Activity(title: "Note updated", date: note.updatedAt))
        }
        if let reminder = reminders.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            activities.append(Activity(title: reminder.title, date: reminder.updatedAt))
        }
        return activities.sorted { lhs, rhs in
            lhs.date > rhs.date
        }.first
    }

    private static func status(
        activeReminderCount: Int,
        latestActivityDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> OperationalStatus {
        if activeReminderCount > 0 {
            return .active
        }
        guard let latestActivityDate,
              let quietThreshold = calendar.date(byAdding: .day, value: -90, to: now) else {
            return .historical
        }
        return latestActivityDate >= quietThreshold ? .quiet : .historical
    }

    private static func statusSummary(
        status: OperationalStatus,
        activeReminderCount: Int,
        latestActivity: Activity?
    ) -> SummaryMetric {
        switch status {
        case .active:
            return SummaryMetric(
                label: "Status",
                value: "Active",
                detail: LedgerDisplayFormatting.count(activeReminderCount, singular: "reminder currently applies", plural: "reminders currently apply")
            )
        case .quiet:
            return SummaryMetric(
                label: "Status",
                value: "Quiet",
                detail: latestActivity.map { "Latest activity: \($0.title)" } ?? "No active reminders"
            )
        case .historical:
            return SummaryMetric(
                label: "Status",
                value: "Historical",
                detail: latestActivity.map { "Last activity: \($0.title)" } ?? "No activity recorded yet"
            )
        }
    }

    private static func reminderSummary(
        activeReminders: [LedgerRule],
        scheduledReminders: [LedgerRule],
        inactiveReminderCount: Int,
        ruleStatus: RuleStatusService,
        now: Date
    ) -> SummaryMetric {
        if activeReminders.count > 1, let first = activeReminders.first {
            return SummaryMetric(
                label: "Active reminders",
                value: LedgerDisplayFormatting.count(activeReminders.count, singular: "reminder currently applies", plural: "reminders currently apply"),
                detail: "\(first.title) · \(ruleStatus.expirationDisplay(for: first, at: now))"
            )
        }
        if let active = activeReminders.first {
            return SummaryMetric(
                label: "Active reminder",
                value: active.title,
                detail: ruleStatus.expirationDisplay(for: active, at: now)
            )
        }
        if let scheduled = scheduledReminders.first {
            return SummaryMetric(
                label: "Scheduled reminder",
                value: scheduled.title,
                detail: ruleStatus.expirationDisplay(for: scheduled, at: now)
            )
        }
        if inactiveReminderCount > 0 {
            return SummaryMetric(
                label: "Reminders",
                value: "No active reminders",
                detail: LedgerDisplayFormatting.count(inactiveReminderCount, singular: "inactive reminder", plural: "inactive reminders")
            )
        }
        return SummaryMetric(label: "Reminders", value: "No reminders", detail: nil)
    }

    private static func latestEventSummary(_ event: LedgerEvent?) -> SummaryMetric? {
        guard let event else { return nil }
        let metadata = EventMetadataDisplayFormatter.summary(
            for: event.metadataEntries,
            eventType: event.eventType,
            limit: 3
        )
        return SummaryMetric(
            label: "Last event",
            value: event.title,
            detail: [DateFormatting.fullDate.string(from: event.occurredAt), metadata].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
        )
    }

    private static func primaryOperationalSummary(events: [LedgerEvent], now: Date, calendar: Calendar) -> SummaryMetric? {
        guard let event = events.first else { return nil }
        let label: String
        switch event.eventType {
        case .maintenance:
            label = "Latest service"
        case .replacement:
            label = "Last replacement"
        case .purchase:
            label = "Last purchase"
        default:
            label = "Latest activity"
        }

        return SummaryMetric(
            label: label,
            value: event.title,
            detail: eventDetail(event, now: now, calendar: calendar)
        )
    }

    private static func continuitySummary(
        events: [LedgerEvent],
        activeReminders: [LedgerRule],
        scheduledReminders: [LedgerRule],
        calendar: Calendar
    ) -> SummaryMetric? {
        if let service = serviceContinuity(events: events, calendar: calendar) {
            return service
        }
        return consumableContinuity(
            events: events,
            reminder: (activeReminders + scheduledReminders).first,
            calendar: calendar
        )
    }

    private static func serviceContinuity(events: [LedgerEvent], calendar: Calendar) -> SummaryMetric? {
        let serviceEvents = events.filter { $0.eventType == .maintenance }
        guard let latest = serviceEvents.first else { return nil }
        let latestMileage = mileage(in: latest)
        let explicitNextDate = dueDate(in: latest, calendar: calendar)

        if let previous = serviceEvents.dropFirst().first,
           let latestMileage,
           let previousMileage = mileage(in: previous) {
            let mileageInterval = max(0, latestMileage - previousMileage)
            let dayInterval = calendar.dateComponents([.day], from: previous.occurredAt, to: latest.occurredAt).day
            let nextMileage = mileageInterval > 0 ? latestMileage + mileageInterval : nil
            let nextDate = explicitNextDate ?? dayInterval.flatMap { calendar.date(byAdding: .day, value: max($0, 1), to: latest.occurredAt) }
            return SummaryMetric(
                label: "Service continuity",
                value: "About every \(LedgerDisplayFormatting.mileage(mileageInterval))",
                detail: estimatedNextDetail(mileage: nextMileage, date: nextDate)
            )
        }

        if let latestMileage {
            return SummaryMetric(
                label: "Service mileage",
                value: LedgerDisplayFormatting.mileage(latestMileage),
                detail: explicitNextDate.map { "Next date: \(DateFormatting.fullDate.string(from: $0))" }
            )
        }
        return explicitNextDate.map {
            SummaryMetric(label: "Next service", value: DateFormatting.fullDate.string(from: $0), detail: nil)
        }
    }

    private static func consumableContinuity(
        events: [LedgerEvent],
        reminder: LedgerRule?,
        calendar: Calendar
    ) -> SummaryMetric? {
        let consumableEvents = events.filter { $0.eventType == .replacement || $0.eventType == .purchase }
        guard let latest = consumableEvents.first,
              let previous = consumableEvents.dropFirst().first else {
            return nil
        }

        let dayInterval = max(1, calendar.dateComponents([.day], from: previous.occurredAt, to: latest.occurredAt).day ?? 0)
        let nextCheck = calendar.date(byAdding: .day, value: dayInterval, to: latest.occurredAt)
        let label = latest.eventType == .replacement ? "Replacement rhythm" : "Purchase rhythm"
        let detail = reminder.map { "Reminder already saved: \($0.title)" }
            ?? nextCheck.map { "Next check to review: \(DateFormatting.fullDate.string(from: $0))" }
        return SummaryMetric(
            label: label,
            value: "About every \(dayInterval) \(dayInterval == 1 ? "day" : "days")",
            detail: detail
        )
    }

    private static func recentActivitySummary(_ activity: Activity?, now: Date, calendar: Calendar) -> SummaryMetric? {
        guard let activity else { return nil }
        return SummaryMetric(
            label: "Recent timeline activity",
            value: activity.title,
            detail: DateFormatting.ledgerDateSummary(activity.date, calendar: calendar, now: now)
        )
    }

    private static func reminderHistorySummary(
        inactiveReminders: [LedgerRule],
        ruleStatus: RuleStatusService,
        now: Date
    ) -> SummaryMetric? {
        guard let latest = inactiveReminders.first else { return nil }
        let completed = inactiveReminders.filter { $0.manuallyDeactivatedAt != nil }
        let value = completed.isEmpty
            ? LedgerDisplayFormatting.count(inactiveReminders.count, singular: "historical reminder", plural: "historical reminders")
            : LedgerDisplayFormatting.count(completed.count, singular: "completed reminder", plural: "completed reminders")
        return SummaryMetric(
            label: "Reminder history",
            value: value,
            detail: "\(latest.title) · \(ruleStatus.expirationDisplay(for: latest, at: now))"
        )
    }

    private static func timelineEntryPoints(
        events: [LedgerEvent],
        notes: [LedgerNote],
        reminders: [LedgerRule],
        now: Date,
        calendar: Calendar
    ) -> [TimelineEntryPoint] {
        let eventRows = events.map {
            TimelineEntryPoint(
                id: "event-\($0.id)",
                label: "Event",
                value: $0.title,
                detail: DateFormatting.ledgerDateSummary($0.occurredAt, calendar: calendar, now: now),
                navigationTarget: .eventDetail($0.id)
            )
        }
        let noteRows = notes.map {
            TimelineEntryPoint(
                id: "note-\($0.id)",
                label: "Note",
                value: $0.text,
                detail: DateFormatting.ledgerDateSummary($0.updatedAt, calendar: calendar, now: now),
                navigationTarget: .noteDetail($0.id)
            )
        }
        let reminderRows = reminders.sorted { $0.updatedAt > $1.updatedAt }.map {
            TimelineEntryPoint(
                id: "rule-\($0.id)",
                label: "Reminder",
                value: $0.title,
                detail: DateFormatting.ledgerDateSummary($0.updatedAt, calendar: calendar, now: now),
                navigationTarget: .ruleDetail($0.id)
            )
        }
        return (eventRows + noteRows + reminderRows).prefix(5).map { $0 }
    }

    private static func latestNoteSummary(_ note: LedgerNote?) -> SummaryMetric? {
        guard let note else { return nil }
        return SummaryMetric(
            label: "Latest note",
            value: note.text,
            detail: DateFormatting.fullDate.string(from: note.updatedAt)
        )
    }

    private static func identityRows(_ thing: Thing) -> [SummaryMetric] {
        var rows: [SummaryMetric] = []
        if let category = thing.category {
            rows.append(SummaryMetric(label: "Category", value: category.displayName, detail: nil))
        }
        if let details = thing.details.nilIfEmpty {
            rows.append(SummaryMetric(label: "Details", value: details, detail: nil))
        }
        if !thing.aliases.isEmpty {
            rows.append(SummaryMetric(label: "Aliases", value: thing.aliases.joined(separator: ", "), detail: nil))
        }
        return rows
    }

    private static func diagnosticRows(_ thing: Thing) -> [SummaryMetric] {
        [
            SummaryMetric(label: "Created", value: DateFormatting.fullDate.string(from: thing.createdAt), detail: nil),
            SummaryMetric(label: "Updated", value: DateFormatting.fullDate.string(from: thing.updatedAt), detail: nil),
            SummaryMetric(
                label: "Extraction records",
                value: LedgerDisplayFormatting.count(
                    thing.sourceMessageIDs.count + thing.sourceExtractionAttemptIDs.count,
                    singular: "record",
                    plural: "records"
                ),
                detail: nil
            )
        ]
    }

    private static func eventDetail(_ event: LedgerEvent, now: Date, calendar: Calendar) -> String? {
        let metadata = EventMetadataDisplayFormatter.summary(for: event.metadataEntries, eventType: event.eventType, limit: 3)
        return [DateFormatting.ledgerDateSummary(event.occurredAt, calendar: calendar, now: now), metadata]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    private static func metadataEntry(in event: LedgerEvent, key: LedgerEventMetadataKey) -> LedgerEventMetadataEntry? {
        event.metadataEntries.first { $0.key == key }
    }

    private static func mileage(in event: LedgerEvent) -> Int? {
        metadataEntry(in: event, key: .mileage)?.numberValue.map { Int($0.rounded()) }
    }

    private static func dueDate(in event: LedgerEvent, calendar: Calendar) -> Date? {
        guard let dateText = metadataEntry(in: event, key: .dueDate)?.dateValue else { return nil }
        return DateFormatting.parseDateOnly(dateText, calendar: calendar)
    }

    private static func estimatedNextDetail(mileage: Int?, date: Date?) -> String? {
        let parts = [
            mileage.map { "Next mileage to review: \(LedgerDisplayFormatting.mileage($0))" },
            date.map { "around \(DateFormatting.fullDate.string(from: $0))" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
