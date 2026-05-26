extension LedgerReviewReconciliationAction {
    var accessibilityIdentifier: String {
        switch kind {
        case .dismiss:
            return "review-queue-dismiss-button"
        case .openRecord, .mergeThing, .reassignRecords, .buildReminderDraft, .adjustReminderTiming:
            return "review-queue-edit-button"
        case .connectService, .retry, .confirm, .saveAsNote, .snooze:
            return "review-queue-accept-button"
        case .blocked:
            return "review-queue-blocked-action"
        }
    }
}
