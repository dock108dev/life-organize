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
            "Try Again?"
        case .markReviewed:
            "Mark Reviewed?"
        case .dismiss:
            "Dismiss?"
        case .snooze:
            "Snooze?"
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
            "This tries again from the original entry. Saved items stay as they are unless the retry succeeds."
        case .markReviewed:
            "This closes the review after you decide no more follow-up is needed."
        case .dismiss:
            "This removes it from Review. Choose Dismiss only when you do not need to see it again."
        case .snooze:
            "This hides it until tomorrow so you can decide later. Saved items stay as they are."
        case .mergeThings(_, let targetName):
            "This keeps \(targetName), moves related items there, then closes the review."
        case .reassignRecords(_, let targetName):
            "This moves the listed items to \(targetName), refreshes links, then closes the review."
        case .adjustReminderTiming:
            "This updates the reminder date, then closes the review."
        case .applyReminderLifecycle:
            "This updates the reminder status, then closes the review."
        case .saveAsNote:
            "This saves the original entry as a note, then closes the review."
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
