import Foundation

struct TimelineSliceProjection {
    let calendar: Calendar
    let now: Date
    private let statusService: RuleStatusService
    private let reminderPresentationService: ReminderContinuityPresentationService

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = Date(), statusService: RuleStatusService = RuleStatusService()) {
        self.calendar = calendar
        self.now = now
        self.statusService = statusService
        self.reminderPresentationService = ReminderContinuityPresentationService(statusService: statusService)
    }

    func rows(
        query: TimelineSliceQuery = TimelineSliceQuery(),
        messages: [ChatMessage] = [],
        things: [Thing] = [],
        events: [LedgerEvent] = [],
        reminders: [LedgerRule] = [],
        notes: [LedgerNote] = [],
        entityLinks: [EntityLink] = []
    ) -> [TimelineSliceRow] {
        let relationshipIndex = TimelineSliceRelationshipIndex(things: things, entityLinks: entityLinks)
        let rows = messageRows(messages, relationshipIndex: relationshipIndex)
            + thingRows(things, relationshipIndex: relationshipIndex)
            + eventRows(events, relationshipIndex: relationshipIndex)
            + reminderRows(reminders, relationshipIndex: relationshipIndex)
            + noteRows(notes, relationshipIndex: relationshipIndex)

        return rows
            .filter { includes($0, query: query) }
            .sorted(by: Self.newestFirst)
    }

    private func messageRows(
        _ messages: [ChatMessage],
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> [TimelineSliceRow] {
        messages.filter(\.requiresPrimaryFeedAttention).map { message in
            row(
                sourceID: message.id,
                sourceKind: .message,
                dateKind: .attention,
                timelineDate: message.createdAt,
                createdAt: message.createdAt,
                updatedAt: nil,
                navigationTarget: .chatMessage(message.id),
                displayLabel: "You",
                summaryText: clean(message.text) ?? "Entry needs review",
                hasDisplayTime: true,
                linkedThings: relationshipIndex.thingContexts(for: .chatMessage(message.id)),
                relationshipContext: relationshipIndex.relationshipContext(for: .chatMessage(message.id)),
                textValues: [message.text, message.extractionStatus.rawValue]
            )
        }
    }

    private func thingRows(
        _ things: [Thing],
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> [TimelineSliceRow] {
        things.flatMap { thing in
            let contexts = [TimelineSliceThingContext(id: thing.id, name: thing.name, aliases: thing.aliases, relationshipSourceLabel: nil)]
            var rows = [
                row(
                    sourceID: thing.id,
                    sourceKind: .thing,
                    dateKind: .created,
                    timelineDate: thing.createdAt,
                    createdAt: thing.createdAt,
                    updatedAt: thing.updatedAt,
                    navigationTarget: .thingDetail(thing.id),
                    displayLabel: clean(thing.name) ?? "Untitled Thing",
                    summaryText: clean(thing.details) ?? thing.category?.displayName ?? "Thing created",
                    hasDisplayTime: true,
                    linkedThings: contexts,
                    relationshipContext: relationshipIndex.relationshipContext(for: .thing(thing.id)),
                    textValues: [thing.name, thing.details, thing.category?.displayName].compactMap { $0 } + thing.aliases
                )
            ]

            if thing.updatedAt != thing.createdAt {
                rows.append(
                    row(
                        sourceID: thing.id,
                        sourceKind: .thing,
                        dateKind: .updated,
                        timelineDate: thing.updatedAt,
                        createdAt: thing.createdAt,
                        updatedAt: thing.updatedAt,
                        navigationTarget: .thingDetail(thing.id),
                        displayLabel: clean(thing.name) ?? "Untitled Thing",
                        summaryText: clean(thing.details) ?? "Thing updated",
                        hasDisplayTime: true,
                        linkedThings: contexts,
                        relationshipContext: relationshipIndex.relationshipContext(for: .thing(thing.id)),
                        textValues: [thing.name, thing.details, thing.category?.displayName].compactMap { $0 } + thing.aliases
                    )
                )
            }
            return rows
        }
    }

    private func eventRows(
        _ events: [LedgerEvent],
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> [TimelineSliceRow] {
        events.map { event in
            let contextText = eventTextValues(event).joined(separator: " ")
            return row(
                sourceID: event.id,
                sourceKind: .event,
                dateKind: .occurred,
                timelineDate: event.occurredAt,
                createdAt: event.createdAt,
                updatedAt: event.updatedAt,
                navigationTarget: .eventDetail(event.id),
                displayLabel: clean(event.title) ?? "Untitled Event",
                summaryText: eventSummary(event),
                hasDisplayTime: DateFormatting.shouldDisplayTime(for: event.occurredAt, contextText: contextText, calendar: calendar),
                linkedThings: relationshipIndex.thingContexts(for: .event(event.id), fallback: event.thing.map { [$0] } ?? []),
                relationshipContext: relationshipIndex.relationshipContext(for: .event(event.id)),
                textValues: eventTextValues(event)
            )
        }
    }

    private func reminderRows(
        _ reminders: [LedgerRule],
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> [TimelineSliceRow] {
        reminders.flatMap { reminder in
            var rows = [
                reminderRow(
                    reminder,
                    dateKind: .dueStart,
                    timelineDate: reminder.startsAt,
                    relationshipIndex: relationshipIndex
                )
            ]

            if let manuallyDeactivatedAt = reminder.manuallyDeactivatedAt {
                rows.append(
                    reminderRow(
                        reminder,
                        dateKind: .completedDeactivated,
                        timelineDate: manuallyDeactivatedAt,
                        relationshipIndex: relationshipIndex
                    )
                )
            } else if let expiresAt = reminder.expiresAt, statusService.status(for: reminder, at: now) == .expired {
                rows.append(
                    reminderRow(
                        reminder,
                        dateKind: .attention,
                        timelineDate: expiresAt,
                        relationshipIndex: relationshipIndex
                    )
                )
            }
            return rows
        }
    }

    private func noteRows(
        _ notes: [LedgerNote],
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> [TimelineSliceRow] {
        notes.flatMap { note in
            let sharedValues = noteTextValues(note)
            var rows = [
                row(
                    sourceID: note.id,
                    sourceKind: .note,
                        dateKind: .created,
                        timelineDate: note.createdAt,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        navigationTarget: .noteDetail(note.id),
                        displayLabel: LedgerDisplayFormatting.noteTitle(for: note.text),
                        summaryText: clean(note.text) ?? "Note created",
                        hasDisplayTime: true,
                        linkedThings: relationshipIndex.thingContexts(for: .note(note.id), fallback: note.linkedThings),
                        relationshipContext: relationshipIndex.relationshipContext(for: .note(note.id)),
                    textValues: sharedValues
                )
            ]

            if note.updatedAt != note.createdAt {
                rows.append(
                    row(
                        sourceID: note.id,
                        sourceKind: .note,
                        dateKind: .updated,
                        timelineDate: note.updatedAt,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        navigationTarget: .noteDetail(note.id),
                        displayLabel: LedgerDisplayFormatting.noteTitle(for: note.text),
                        summaryText: clean(note.text) ?? "Note updated",
                        hasDisplayTime: true,
                        linkedThings: relationshipIndex.thingContexts(for: .note(note.id), fallback: note.linkedThings),
                        relationshipContext: relationshipIndex.relationshipContext(for: .note(note.id)),
                        textValues: sharedValues
                    )
                )
            }
            return rows
        }
    }

    private func reminderRow(
        _ reminder: LedgerRule,
        dateKind: TimelineSliceDateKind,
        timelineDate: Date,
        relationshipIndex: TimelineSliceRelationshipIndex
    ) -> TimelineSliceRow {
        let presentation = reminderPresentationService.presentation(for: reminder)
        let behaviorDisplay = reminderPresentationService.continuityTypeDisplayName(for: reminder.continuityBehavior)
        return row(
            sourceID: reminder.id,
            sourceKind: .reminder,
            dateKind: dateKind,
            timelineDate: timelineDate,
            createdAt: reminder.createdAt,
            updatedAt: reminder.updatedAt,
            navigationTarget: .ruleDetail(reminder.id),
            displayLabel: clean(reminder.title) ?? "Untitled Reminder",
            summaryText: [behaviorDisplay, presentation.primaryLine, reminder.reason, reminder.rawText]
                .compactMap { clean($0) }
                .joined(separator: " · "),
            hasDisplayTime: dateKind == .completedDeactivated
                || DateFormatting.shouldDisplayTime(
                    for: timelineDate,
                    contextText: [reminder.rawText, reminder.title, reminder.reason].compactMap { $0 }.joined(separator: " "),
                    calendar: calendar
                ),
            linkedThings: relationshipIndex.thingContexts(for: .rule(reminder.id), fallback: reminder.thing.map { [$0] } ?? []),
            relationshipContext: relationshipIndex.relationshipContext(for: .rule(reminder.id)),
            textValues: [reminder.title, reminder.reason, reminder.rawText, behaviorDisplay, presentation.lane.title, presentation.badge, reminder.thing?.name]
                .compactMap { $0 } + (reminder.thing?.aliases ?? [])
        )
    }

    private func row(
        sourceID: UUID,
        sourceKind: TimelineSliceRecordKind,
        dateKind: TimelineSliceDateKind,
        timelineDate: Date,
        createdAt: Date,
        updatedAt: Date?,
        navigationTarget: LocalSearchNavigationTarget,
        displayLabel: String,
        summaryText: String,
        hasDisplayTime: Bool,
        linkedThings: [TimelineSliceThingContext],
        relationshipContext: TimelineSliceRelationshipContext?,
        textValues: [String]
    ) -> TimelineSliceRow {
        let baseTextValues = [
            displayLabel,
            summaryText,
            sourceKind.displayName,
            dateKind.displayName,
            relationshipContext?.sourceLabel
        ].compactMap { $0 }
        let linkedThingTextValues = linkedThings.flatMap { context in
            [context.name] + context.aliases + [context.relationshipSourceLabel].compactMap { $0 }
        }
        let searchableText = (baseTextValues + textValues + linkedThingTextValues)
            .compactMap { clean($0) }
            .joined(separator: " ")

        return TimelineSliceRow(
            sourceID: sourceID,
            sourceKind: sourceKind,
            dateKind: dateKind,
            timelineDate: timelineDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            navigationTarget: navigationTarget,
            displayLabel: displayLabel,
            summaryText: clean(summaryText) ?? displayLabel,
            hasDisplayTime: hasDisplayTime,
            linkedThings: linkedThings,
            relationshipContext: relationshipContext,
            searchableText: searchableText
        )
    }

    private func includes(_ row: TimelineSliceRow, query: TimelineSliceQuery) -> Bool {
        if let dateRange = query.dateRange, !dateRange.contains(row.timelineDate) {
            return false
        }

        if let normalizedText = query.normalizedTextFilter,
           !SearchService.normalizeForLocalSearch(row.searchableText).contains(normalizedText) {
            return false
        }

        guard let filter = query.linkedThingFilter else { return true }
        switch filter {
        case .id(let id):
            return row.linkedThings.contains { $0.id == id }
        case .text:
            guard let normalizedText = filter.normalizedText else { return true }
            return row.linkedThings.contains { context in
                let candidates = [context.name] + context.aliases
                return candidates.contains { SearchService.normalizeForLocalSearch($0).contains(normalizedText) }
            }
        }
    }

    private static func newestFirst(_ lhs: TimelineSliceRow, _ rhs: TimelineSliceRow) -> Bool {
        if lhs.timelineDate != rhs.timelineDate {
            return lhs.timelineDate > rhs.timelineDate
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.sourceKind.sortRank != rhs.sourceKind.sortRank {
            return lhs.sourceKind.sortRank < rhs.sourceKind.sortRank
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID.uuidString < rhs.sourceID.uuidString
        }
        return lhs.dateKind.sortRank < rhs.dateKind.sortRank
    }

    private func eventSummary(_ event: LedgerEvent) -> String {
        let metadataSummary = EventMetadataDisplayFormatter.summary(
            for: event.metadataEntries,
            eventType: event.eventType,
            limit: 3,
            labelSeparator: " "
        )
        return [event.note, metadataSummary, event.rawText]
            .compactMap { clean($0) }
            .first ?? "Event recorded"
    }

    private func eventTextValues(_ event: LedgerEvent) -> [String] {
        [event.title, event.rawText, event.note, event.eventType.displayName, event.eventType.rawValue, event.thing?.name]
            .compactMap { $0 }
            + (event.thing?.aliases ?? [])
            + event.metadataEntries.flatMap { [$0.key.displayName, $0.key.rawValue, $0.displayValue, $0.sourceText].compactMap { $0 } }
    }

    private func noteTextValues(_ note: LedgerNote) -> [String] {
        [note.text] + note.linkedThings.flatMap { [$0.name] + $0.aliases }
    }

    private func clean(_ value: String?) -> String? {
        value?.nilIfEmpty
    }
}
