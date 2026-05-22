import SwiftUI

enum LedgerReviewPendingAction: Identifiable, Equatable {
    case retry
    case markReviewed
    case dismiss
    case snooze(Date)
    case mergeThings(UUID, String)
    case reassignRecords(UUID, String)
    case adjustReminderTiming(Date, String)
    case applyReminderLifecycle(String)
    case saveAsNote

    var id: String {
        switch self {
        case .retry:
            "retry"
        case .markReviewed:
            "mark-reviewed"
        case .dismiss:
            "dismiss"
        case .snooze(let date):
            "snooze-\(date.timeIntervalSinceReferenceDate)"
        case .mergeThings(let targetID, _):
            "merge-\(targetID.uuidString)"
        case .reassignRecords(let targetID, _):
            "reassign-\(targetID.uuidString)"
        case .adjustReminderTiming(let date, _):
            "timing-\(date.timeIntervalSinceReferenceDate)"
        case .applyReminderLifecycle(let title):
            "lifecycle-\(title)"
        case .saveAsNote:
            "save-as-note"
        }
    }

    var dialogTitle: String {
        switch self {
        case .retry:
            "Retry Entry?"
        case .markReviewed:
            "Mark Reviewed?"
        case .dismiss:
            "Dismiss Review Item?"
        case .snooze:
            "Snooze Review Item?"
        case .mergeThings(_, let targetName):
            "Merge Into \(targetName)?"
        case .reassignRecords(_, let targetName):
            "Reassign To \(targetName)?"
        case .adjustReminderTiming(_, let title):
            "\(title)?"
        case .applyReminderLifecycle(let title):
            "\(title)?"
        case .saveAsNote:
            "Save as Note?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .retry:
            "Retry Now"
        case .markReviewed:
            "Mark Reviewed"
        case .dismiss:
            "Dismiss"
        case .snooze:
            "Snooze"
        case .mergeThings:
            "Merge"
        case .reassignRecords:
            "Reassign"
        case .adjustReminderTiming(_, let title), .applyReminderLifecycle(let title):
            title
        case .saveAsNote:
            "Save as Note"
        }
    }

    var message: String {
        switch self {
        case .retry:
            "This retries extraction for the saved local entry. No ledger records are changed until retry succeeds."
        case .markReviewed:
            "This closes the review item. No ledger records are changed."
        case .dismiss:
            "This hides the review item for the same saved evidence. No ledger records are changed."
        case .snooze:
            "This moves the review item out of the current flow until tomorrow. No ledger records are changed."
        case .mergeThings(_, let targetName):
            "This moves linked records to \(targetName), keeps aliases and source links, then closes the review item."
        case .reassignRecords(_, let targetName):
            "This moves the listed records to \(targetName), refreshes links, then closes the review item."
        case .adjustReminderTiming:
            "This updates the saved reminder date through the reminder lifecycle service, then closes the review item."
        case .applyReminderLifecycle:
            "This moves the saved reminder out of the current lane, then closes the review item."
        case .saveAsNote:
            "This saves the review context as a note, then closes the review item."
        }
    }

    var role: ButtonRole? {
        switch self {
        case .dismiss, .mergeThings, .applyReminderLifecycle:
            .destructive
        case .retry, .markReviewed, .snooze, .reassignRecords, .adjustReminderTiming, .saveAsNote:
            nil
        }
    }
}
