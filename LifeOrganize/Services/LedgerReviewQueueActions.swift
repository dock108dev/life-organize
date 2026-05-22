import Foundation
import SwiftData

struct LedgerReviewReminderDraft: Equatable {
    let title: String
    let reason: String
    let startsAt: Date
    let expiresAt: Date?
    let thingID: UUID?
    let sourceContext: String
}

@MainActor
extension LedgerReviewQueueService {
    func snooze(_ item: LedgerReviewItem, until date: Date) throws {
        try ensureActionable(item)
        item.snooze(until: date, at: dateProvider.now)
        try modelContext.save()
    }

    func supersede(_ item: LedgerReviewItem) throws {
        try ensureActionable(item)
        item.supersede(at: dateProvider.now)
        try modelContext.save()
    }

    func expire(_ item: LedgerReviewItem) throws {
        try ensureActionable(item)
        item.expire(at: dateProvider.now)
        try modelContext.save()
    }

    func reminderDraft(for item: LedgerReviewItem) throws -> LedgerReviewReminderDraft {
        try ensureActionable(item)
        guard item.kind == .intervalReminder else {
            throw LedgerReviewQueueError.unsupportedAction
        }
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        let targetThing = item.targetID.flatMap { id in things.first { $0.id == id } }
        guard let targetThing else {
            throw LedgerReviewQueueError.missingTarget
        }
        let intervalEvidence = sourceContext(for: item)
        let reason = [
            item.detail.nilIfEmpty,
            intervalEvidence.nilIfEmpty,
            "No automatic recurrence has been scheduled."
        ].compactMap { $0 }.joined(separator: "\n\n")
        return LedgerReviewReminderDraft(
            title: "\(targetThing.name) reminder",
            reason: reason,
            startsAt: Self.firstDate(in: item.detail).map { DateFormatting.normalizedDateOnly($0) }
                ?? DateFormatting.normalizedDateOnly(dateProvider.now),
            expiresAt: nil,
            thingID: targetThing.id,
            sourceContext: intervalEvidence
        )
    }

    func applyReminderDateAction(for item: LedgerReviewItem, date: Date) throws {
        try ensureActionable(item)
        guard let rule = try targetRule(for: item) else {
            throw LedgerReviewQueueError.missingTarget
        }
        let status = RuleStatusService().status(for: rule, at: dateProvider.now)
        guard let dateAction = ReminderDetailActionPolicy.dateAction(for: rule, status: status) else {
            throw LedgerReviewQueueError.unsupportedAction
        }
        let updatedAt = dateProvider.now
        let maintenance = DerivedFieldMaintenanceService(modelContext: modelContext, now: { updatedAt })
        switch dateAction.sheet {
        case .reschedule:
            try ReminderRuleLifecycleMutation.moveDueDate(rule, to: date, at: updatedAt, maintenance: maintenance)
        case .endDate:
            try ReminderRuleLifecycleMutation.setEndDate(rule, to: date, at: updatedAt, maintenance: maintenance)
        case .edit:
            throw LedgerReviewQueueError.unsupportedAction
        }
        item.accept(at: updatedAt)
        try modelContext.save()
    }

    func applyReminderLifecycleAction(for item: LedgerReviewItem) throws {
        try ensureActionable(item)
        guard let rule = try targetRule(for: item) else {
            throw LedgerReviewQueueError.missingTarget
        }
        let status = RuleStatusService().status(for: rule, at: dateProvider.now)
        guard ReminderDetailActionPolicy.lifecycleAction(for: rule, status: status) != nil else {
            throw LedgerReviewQueueError.unsupportedAction
        }
        let updatedAt = dateProvider.now
        ReminderRuleLifecycleMutation.deactivate(
            rule,
            at: updatedAt,
            maintenance: DerivedFieldMaintenanceService(modelContext: modelContext, now: { updatedAt })
        )
        item.accept(at: updatedAt)
        try modelContext.save()
    }

    func ensureActionable(_ item: LedgerReviewItem) throws {
        guard item.state.isActionable else {
            throw LedgerReviewQueueError.actionUnavailable
        }
    }

    private func sourceContext(for item: LedgerReviewItem) -> String {
        item.evidence
            .map { evidence in
                [evidence.summary.nilIfEmpty, evidence.detail?.nilIfEmpty]
                    .compactMap { $0 }
                    .joined(separator: ": ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func firstDate(in text: String) -> Date? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return DateFormatting.parseDateOnly(String(text[range]))
    }
}

private extension LedgerReviewItemState {
    var isActionable: Bool {
        switch self {
        case .candidate, .ready, .presented, .snoozed, .failed:
            true
        case .accepted, .dismissed, .superseded, .expired:
            false
        }
    }
}
