import Foundation

struct LedgerReviewQueueRowPresentation: Equatable {
    let question: String
    let sourceHint: String?
    let suggestedHint: String
    let urgencyText: String
    let nextActionTitle: String
    let badges: [LedgerBadgePresentation]
    let isBlocked: Bool

    init(item: LedgerReviewItem, entry: LedgerReviewQueueEntry, now: Date = Date()) {
        let itemPresentation = LedgerReviewItemPresentationService().presentation(for: item)
        question = entry.title
        sourceHint = Self.sourceHint(for: item, entry: entry)
        suggestedHint = Self.suggestedHint(for: entry)
        urgencyText = Self.urgencyText(for: item, entry: entry, priority: itemPresentation.priority, now: now)
        nextActionTitle = entry.primaryActionTitle
        badges = Self.badges(for: item, entry: entry, itemPresentation: itemPresentation)
        isBlocked = entry.isActionBlocked
    }

    var accessibilityLabel: String {
        [
            question,
            sourceHint,
            suggestedHint,
            urgencyText,
            "Next: \(nextActionTitle)"
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: ". ")
    }

    private static func sourceHint(for item: LedgerReviewItem, entry: LedgerReviewQueueEntry) -> String? {
        if let originLabel = entry.origin?.label.nilIfEmpty {
            return "Source: \(originLabel)"
        }
        if let summary = item.evidence.first?.summary.nilIfEmpty {
            return "Source: \(summary)"
        }
        return nil
    }

    private static func suggestedHint(for entry: LedgerReviewQueueEntry) -> String {
        if !entry.createdRecords.isEmpty {
            let visibleTitles = entry.createdRecords.prefix(2).map(\.title)
            let remainingCount = entry.createdRecords.count - visibleTitles.count
            let suffix = remainingCount > 0 ? " + \(remainingCount) more" : ""
            return "Suggested: \(visibleTitles.joined(separator: ", "))\(suffix)"
        }
        if let detail = entry.detail.nilIfEmpty {
            return detail
        }
        return "Open details to compare the saved context."
    }

    private static func urgencyText(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        priority: Int,
        now: Date
    ) -> String {
        _ = now
        if entry.isActionBlocked {
            return entry.primaryActionTitle == "Connect Service" ? "Needs service" : "Needs review"
        }
        switch item.state {
        case .snoozed:
            if let snoozedUntil = item.snoozedUntil {
                return "Returns \(DateFormatting.shortDate.string(from: snoozedUntil))"
            }
            return "Snoozed"
        case .failed:
            return "Update failed"
        case .candidate, .ready, .presented:
            if priority >= 85 {
                return "Needs decision"
            }
            if priority >= 70 {
                return "Ready to review"
            }
            return "Review when ready"
        case .accepted, .dismissed, .superseded, .expired:
            return "Updated"
        }
    }

    private static func badges(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        itemPresentation: LedgerReviewItemPresentation
    ) -> [LedgerBadgePresentation] {
        LedgerBadgePresentation.visibleBadges(
            from: [
                LedgerBadgePresentation.reviewState(
                    for: item.state,
                    priority: itemPresentation.priority,
                    isHighPriority: itemPresentation.isHighPriority || entry.isActionBlocked
                ),
                categoryBadge(for: item, entry: entry)
            ],
            maxCount: 2
        )
    }

    private static func categoryBadge(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry
    ) -> LedgerBadgePresentation {
        switch entry.correctionClass {
        case .mergeDuplicateThings, .reassignRecordsToThing:
            return LedgerBadgePresentation(semantic: .categoryThing)
        case .adjustReminderTiming:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .quickReview:
            return badge(for: item.targetType)
        }
    }

    private static func badge(for targetType: LedgerReviewItemTargetType) -> LedgerBadgePresentation {
        switch targetType {
        case .chatMessage:
            return LedgerBadgePresentation(semantic: .categoryMessage)
        case .thing:
            return LedgerBadgePresentation(semantic: .categoryThing)
        case .event:
            return LedgerBadgePresentation(semantic: .categoryEvent)
        case .rule:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .none:
            return LedgerBadgePresentation(semantic: .categoryNote)
        }
    }
}
