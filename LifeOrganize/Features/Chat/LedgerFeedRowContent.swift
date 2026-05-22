import Foundation

struct LedgerFeedRowContent {
    enum Source: Equatable {
        case user
        case status
        case system
        case event
        case reminder
        case note
    }

    enum SecondaryTone: Equatable {
        case neutral
        case muted
        case info
        case attention
        case danger

        init(tone: LedgerTone) {
            switch tone {
            case .neutral:
                self = .neutral
            case .link, .muted, .success, .note:
                self = .muted
            case .info:
                self = .info
            case .attention:
                self = .attention
            case .danger:
                self = .danger
            }
        }
    }

    let timestampText: String
    let source: Source
    let sourceLabel: String
    let sourceBadge: LedgerBadgePresentation
    let primaryText: String
    let secondaryText: String?
    let secondaryTone: SecondaryTone
    let secondaryBadge: LedgerBadgePresentation?
    let detailText: String?
    let linkedThingText: String?

    init(
        item: LedgerFeedItem,
        timeFormatter: DateFormatter = DateFormatting.ledgerTime,
        dateFormatter: DateFormatter = DateFormatting.fullDate,
        ruleStatus: RuleStatusService = RuleStatusService()
    ) {
        timestampText = timeFormatter.string(from: item.timelineDate)
        let continuityService = ReminderContinuityPresentationService(statusService: ruleStatus)

        switch item {
        case .message(let message):
            source = Self.source(for: message.role)
            sourceBadge = Self.sourceBadge(for: message)
            sourceLabel = sourceBadge.label
            primaryText = message.text.nilIfEmpty ?? "No message text"
            let status = Self.statusBadge(for: message)
            secondaryBadge = status
            secondaryText = status?.label
            secondaryTone = status.map { SecondaryTone(tone: $0.tone) } ?? .neutral
            detailText = nil
            linkedThingText = nil
        case .event(let event):
            source = .event
            sourceBadge = LedgerBadgePresentation.feedSource(for: .event)
            sourceLabel = sourceBadge.label
            primaryText = event.title.nilIfEmpty ?? "Untitled event"
            secondaryText = event.eventType.displayName
            secondaryTone = .neutral
            secondaryBadge = nil
            detailText = Self.detailText(event.note?.nilIfEmpty, primaryText: primaryText)
            linkedThingText = event.thing?.name.nilIfEmpty
        case .reminder(let reminder):
            let presentation = continuityService.presentation(for: reminder)
            source = .reminder
            sourceBadge = LedgerBadgePresentation.feedSource(for: .reminder)
            sourceLabel = sourceBadge.label
            primaryText = reminder.title.nilIfEmpty ?? "Untitled reminder"
            secondaryText = presentation.primaryLine
            secondaryTone = presentation.lane == .review ? .attention : .neutral
            secondaryBadge = nil
            detailText = Self.reminderDetailText(
                reminder,
                primaryText: primaryText,
                dateFormatter: dateFormatter
            )
            linkedThingText = reminder.thing?.name.nilIfEmpty
        case .note(let note):
            source = .note
            sourceBadge = LedgerBadgePresentation.feedSource(for: .note)
            sourceLabel = sourceBadge.label
            primaryText = note.text.firstLine.nilIfEmpty ?? "Note"
            let names = note.linkedThings.map(\.name).filter { !$0.isEmpty }
            secondaryText = nil
            secondaryTone = .neutral
            secondaryBadge = nil
            detailText = Self.detailText(note.text.nilIfEmpty, primaryText: primaryText)
            linkedThingText = names.isEmpty ? nil : names.joined(separator: ", ")
        }
    }

    private static func source(for role: ChatRole) -> Source {
        switch role {
        case .user:
            return .user
        case .assistant:
            return .status
        case .system:
            return .system
        }
    }

    private static func sourceLabel(for message: ChatMessage) -> String {
        sourceBadge(for: message).label
    }

    private static func sourceBadge(for message: ChatMessage) -> LedgerBadgePresentation {
        switch message.role {
        case .user:
            return LedgerBadgePresentation(semantic: .sourceUser)
        case .assistant:
            return assistantSourceBadge(for: message.text)
        case .system:
            return LedgerBadgePresentation(semantic: .sourceApp)
        }
    }

    private static func assistantSourceBadge(for text: String) -> LedgerBadgePresentation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Event saved:")
            || trimmed.hasPrefix("Events saved:")
            || trimmed.hasPrefix("Reminder saved:")
            || trimmed.hasPrefix("Reminders saved:")
            || trimmed.hasPrefix("Restriction saved:")
            || trimmed.hasPrefix("Restrictions saved:")
            || trimmed.hasPrefix("Note saved:")
            || trimmed.hasPrefix("Notes saved:")
            || trimmed.hasPrefix("Thing saved:")
            || trimmed.hasPrefix("Saved") {
            return LedgerBadgePresentation(semantic: .statusSaved)
        }
        if trimmed.hasPrefix("Coming Up:") {
            return LedgerBadgePresentation(semantic: .collectionUpcoming)
        }
        if trimmed.hasPrefix("Review:") {
            return LedgerBadgePresentation(semantic: .collectionReview)
        }
        if trimmed.hasPrefix("Last logged:")
            || trimmed.hasPrefix("Now:")
            || trimmed.hasPrefix("Paused:")
            || trimmed.hasPrefix("Recent notes:")
            || trimmed.hasPrefix("Local results:")
            || trimmed.hasPrefix("Web results:")
            || trimmed.contains(" related items found.") {
            return LedgerBadgePresentation(semantic: .sourceLog, label: "Found")
        }
        return LedgerBadgePresentation(semantic: .sourceLog)
    }

    private static func detailText(_ text: String?, primaryText: String) -> String? {
        guard let text, text != primaryText else { return nil }
        return text
    }

    private static func reminderDetailText(
        _ reminder: LedgerRule,
        primaryText: String,
        dateFormatter: DateFormatter
    ) -> String? {
        let reason = detailText(reminder.reason?.nilIfEmpty, primaryText: primaryText)
        let captureText = "Captured \(dateFormatter.string(from: reminder.createdAt))"
        guard !dateFormatter.calendar.isDate(reminder.createdAt, inSameDayAs: reminder.startsAt) else {
            return reason
        }
        return [reason, captureText].compactMap(\.self).joined(separator: " · ").nilIfEmpty
    }

    private static func statusBadge(for message: ChatMessage) -> LedgerBadgePresentation? {
        guard message.role == .user else { return nil }
        switch message.extractionStatus {
        case .pending, .extracting:
            return LedgerBadgePresentation(semantic: .statusSaving)
        case .pendingToken:
            return LedgerBadgePresentation(semantic: .statusSavedLocal)
        case .pendingRetry:
            return LedgerBadgePresentation(semantic: .statusRetryPending, tone: .info)
        case .partiallySucceeded:
            return LedgerBadgePresentation(semantic: .actionReview, tone: .attention)
        case .failed:
            return LedgerBadgePresentation(semantic: .statusFailed)
        case .failedNeedsReview, .needsReview:
            return LedgerBadgePresentation(semantic: .actionReview, tone: .attention)
        case .notRequired, .succeeded:
            return nil
        }
    }
}

private extension String {
    var firstLine: String {
        components(separatedBy: .newlines).first ?? self
    }
}
