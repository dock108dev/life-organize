import Foundation

struct LedgerReviewQueueRowPresentation: Equatable {
    let question: String
    let sourceHint: String?
    let suggestedHint: String
    let urgencyText: String
    let nextActionTitle: String
    let badges: [LedgerBadgePresentation]
    let hiddenBadgeAccessibilityText: String?
    let isBlocked: Bool

    init(item: LedgerReviewItem, entry: LedgerReviewQueueEntry, now: Date = Date()) {
        let itemPresentation = LedgerReviewItemPresentationService().presentation(for: item)
        let rowQuestion = entry.title
        let rowSourceHint = Self.sourceHint(for: item, entry: entry)
        let rowSuggestedHint = Self.suggestedHint(for: entry)
        let rowUrgencyText = Self.urgencyText(for: item, entry: entry, priority: itemPresentation.priority, now: now)
        let rowNextActionTitle = entry.primaryActionTitle
        let candidateBadges = Self.badgeCandidates(for: item, entry: entry, itemPresentation: itemPresentation)
        let visibleBadges = LedgerBadgePresentation.primaryBadges(from: candidateBadges)

        question = rowQuestion
        sourceHint = rowSourceHint
        suggestedHint = rowSuggestedHint
        urgencyText = rowUrgencyText
        nextActionTitle = rowNextActionTitle
        badges = visibleBadges
        hiddenBadgeAccessibilityText = Self.hiddenBadgeAccessibilityText(
            from: candidateBadges,
            visibleBadges: visibleBadges,
            visibleText: [rowQuestion, rowSourceHint, rowSuggestedHint, rowUrgencyText, rowNextActionTitle]
        )
        isBlocked = entry.isActionBlocked
    }

    var accessibilityLabel: String {
        [
            question,
            sourceHint,
            suggestedHint,
            urgencyText,
            hiddenBadgeAccessibilityText,
            "Next: \(nextActionTitle)"
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: ". ")
    }

    private static func sourceHint(for item: LedgerReviewItem, entry: LedgerReviewQueueEntry) -> String? {
        if let originLabel = entry.origin?.label.nilIfEmpty {
            return originLabel
        }
        if let summary = item.evidence.first?.summary.nilIfEmpty {
            return summary
        }
        return nil
    }

    private static func suggestedHint(for entry: LedgerReviewQueueEntry) -> String {
        if !entry.createdRecords.isEmpty {
            let visibleTitles = entry.createdRecords.prefix(2).map(\.title)
            let remainingCount = entry.createdRecords.count - visibleTitles.count
            let suffix = remainingCount > 0 ? " + \(remainingCount) more" : ""
            return "Saved items include \(visibleTitles.joined(separator: ", "))\(suffix)"
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
            return entry.primaryActionTitle == "Connect Service" ? "Service connection needed" : "Review in detail"
        }
        switch item.state {
        case .snoozed:
            if let snoozedUntil = item.snoozedUntil {
                return "Returns \(DateFormatting.shortDate.string(from: snoozedUntil))"
            }
            return "Snoozed"
        case .failed:
            return "Review needed"
        case .candidate, .ready, .presented:
            if priority >= 85 {
                return "Ready for decision"
            }
            if priority >= 70 {
                return "Ready to review"
            }
            return "Review when ready"
        case .accepted, .dismissed, .superseded, .expired:
            return "Updated"
        }
    }

    private static func badgeCandidates(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        itemPresentation: LedgerReviewItemPresentation
    ) -> [LedgerBadgePresentation] {
        [
            LedgerBadgePresentation.reviewState(
                for: item.state,
                priority: itemPresentation.priority,
                isHighPriority: itemPresentation.isHighPriority || entry.isActionBlocked
            ),
            categoryBadge(for: item, entry: entry)
        ]
    }

    private static func hiddenBadgeAccessibilityText(
        from candidateBadges: [LedgerBadgePresentation],
        visibleBadges: [LedgerBadgePresentation],
        visibleText: [String?]
    ) -> String? {
        let visibleSummary = visibleText
            .compactMap(\.self)
            .joined(separator: " ")
            .localizedLowercase
        let hiddenLabels = LedgerBadgePresentation.hiddenBadges(from: candidateBadges, visibleBadges: visibleBadges)
            .map(\.label)
            .filter { !visibleSummary.contains($0.localizedLowercase) }
        guard !hiddenLabels.isEmpty else { return nil }
        return "Context: \(hiddenLabels.joined(separator: ", "))"
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
