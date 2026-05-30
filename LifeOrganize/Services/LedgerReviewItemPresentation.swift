import Foundation

struct LedgerReviewItemPresentation: Identifiable {
    let item: LedgerReviewItem
    let title: String
    let detail: String?
    let primaryActionTitle: String?
    let badge: LedgerBadgePresentation
    let priority: Int
    let isHighPriority: Bool

    var id: UUID { item.id }
    var pillText: String { badge.label }
    var tone: LedgerTone { badge.tone }

    var rowLine: LedgerRowLine {
        LedgerRowLine(text: rowText, tone: tone, role: .contentPreview, lineLimit: 2)
    }

    var bannerMessage: String {
        [title, detail].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
    }

    private var rowText: String {
        [pillText, title].compactMap { $0.nilIfEmpty }.joined(separator: ": ")
    }
}

struct LedgerReviewItemPresentationService {
    func primaryPresentation(
        for targetType: LedgerReviewItemTargetType,
        targetID: UUID,
        in items: [LedgerReviewItem],
        includeResolved: Bool = false
    ) -> LedgerReviewItemPresentation? {
        presentations(
            for: targetType,
            targetID: targetID,
            in: items,
            includeResolved: includeResolved
        )
        .first
    }

    func presentations(
        for targetType: LedgerReviewItemTargetType,
        targetID: UUID,
        in items: [LedgerReviewItem],
        includeResolved: Bool = false
    ) -> [LedgerReviewItemPresentation] {
        items
            .filter { item in
                includeResolved || item.state.isAmbientlyVisible
            }
            .filter { item in
                item.matches(targetType: targetType, targetID: targetID)
            }
            .map(presentation(for:))
            .sorted(by: presentationPrecedes)
    }

    func bannerPresentation(in items: [LedgerReviewItem]) -> LedgerReviewItemPresentation? {
        items
            .map(presentation(for:))
            .filter(\.isHighPriority)
            .sorted(by: presentationPrecedes)
            .first
    }

    func presentation(for item: LedgerReviewItem) -> LedgerReviewItemPresentation {
        let priority = priority(for: item)
        let isHighPriority = item.state.isAmbientlyVisible && priority >= 80
        return LedgerReviewItemPresentation(
            item: item,
            title: title(for: item),
            detail: detail(for: item),
            primaryActionTitle: item.actionTitle,
            badge: LedgerBadgePresentation.reviewState(
                for: item.state,
                priority: priority,
                isHighPriority: isHighPriority
            ),
            priority: priority,
            isHighPriority: isHighPriority
        )
    }

    private func title(for item: LedgerReviewItem) -> String {
        switch item.state {
        case .candidate, .ready, .presented:
            return item.title
        case .accepted:
            return "Reviewed \(item.title.lowercasedFirstWord)"
        case .dismissed:
            return "Dismissed \(item.title.lowercasedFirstWord)"
        case .snoozed:
            return "Snoozed \(item.title.lowercasedFirstWord)"
        case .superseded:
            return "Updated \(item.title.lowercasedFirstWord)"
        case .expired:
            return "Expired \(item.title.lowercasedFirstWord)"
        case .failed:
            return "Review needs attention"
        }
    }

    private func detail(for item: LedgerReviewItem) -> String? {
        switch item.state {
        case .snoozed:
            if let snoozedUntil = item.snoozedUntil {
                return "Returns \(DateFormatting.shortDate.string(from: snoozedUntil))."
            }
            return item.detail.nilIfEmpty
        case .failed:
            return item.failureReason?.nilIfEmpty ?? item.detail.nilIfEmpty
        case .accepted, .dismissed, .superseded, .expired:
            return item.updatedAtText
        case .candidate, .ready, .presented:
            return item.detail.nilIfEmpty
        }
    }

    private func priority(for item: LedgerReviewItem) -> Int {
        let basePriority: Int
        switch item.kind {
        case .overdueReminderReview, .localRecovery:
            basePriority = 90
        case .extractionReview, .conflictingDate:
            basePriority = 85
        case .intervalReminder:
            basePriority = 70
        case .duplicateThing:
            basePriority = 60
        case .normalizationCandidate:
            basePriority = 50
        }

        switch item.state {
        case .failed:
            return 95
        case .ready:
            return basePriority + 4
        case .presented:
            return basePriority + 2
        case .candidate:
            return basePriority
        case .snoozed:
            return min(basePriority, 40)
        case .accepted, .dismissed, .superseded, .expired:
            return 10
        }
    }

    private func presentationPrecedes(
        _ lhs: LedgerReviewItemPresentation,
        _ rhs: LedgerReviewItemPresentation
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.item.updatedAt != rhs.item.updatedAt {
            return lhs.item.updatedAt > rhs.item.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension LedgerReviewItemState {
    var isAmbientlyVisible: Bool {
        switch self {
        case .candidate, .ready, .presented, .snoozed, .failed:
            return true
        case .accepted, .dismissed, .superseded, .expired:
            return false
        }
    }
}

private extension LedgerReviewItem {
    func matches(targetType: LedgerReviewItemTargetType, targetID: UUID) -> Bool {
        if self.targetType == targetType, self.targetID == targetID {
            return true
        }
        return evidence.contains { evidence in
            evidence.sourceType == targetType && evidence.sourceID == targetID
        }
    }

    var updatedAtText: String? {
        "Updated \(DateFormatting.shortDate.string(from: updatedAt))."
    }
}

private extension String {
    var lowercasedFirstWord: String {
        guard let first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}
