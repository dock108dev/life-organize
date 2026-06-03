import Foundation

struct LedgerReviewReconciliationPresentation: Equatable {
    let itemID: UUID
    let title: String
    let source: LedgerReviewReconciliationPanel
    let suggestion: LedgerReviewReconciliationPanel
    let evidence: LedgerReviewReconciliationPanel?
    let actions: LedgerReviewReconciliationActions
    let saveAsNoteBody: String?
}

struct LedgerReviewReconciliationPanel: Equatable {
    let title: String
    let summary: String?
    let rows: [LedgerReviewReconciliationRow]
}

struct LedgerReviewReconciliationRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let targetType: LedgerReviewItemTargetType?
    let targetID: UUID?
    let isMissing: Bool

    init(
        id: String,
        title: String,
        detail: String? = nil,
        targetType: LedgerReviewItemTargetType? = nil,
        targetID: UUID? = nil,
        isMissing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.targetType = targetType
        self.targetID = targetID
        self.isMissing = isMissing
    }
}

struct LedgerReviewReconciliationActions: Equatable {
    let primary: LedgerReviewReconciliationAction?
    let contextual: [LedgerReviewReconciliationAction]
    let reviewState: [LedgerReviewReconciliationAction]
    let destructive: [LedgerReviewReconciliationAction]

    var all: [LedgerReviewReconciliationAction] {
        [primary].compactMap { $0 } + contextual + reviewState + destructive
    }
}

struct LedgerReviewReconciliationAction: Identifiable, Equatable {
    let kind: LedgerReviewReconciliationActionKind
    let title: String
    let detail: String?
    let role: LedgerReviewReconciliationActionRole
    let isEnabled: Bool

    var id: String {
        "\(role.rawValue)-\(kind.id)"
    }
}

enum LedgerReviewReconciliationActionKind: Equatable {
    case retry
    case confirm
    case openRecord(LedgerReviewItemTargetType, UUID)
    case mergeThing(UUID)
    case reassignRecords(UUID)
    case adjustReminderTiming
    case buildReminderDraft
    case saveAsNote
    case snooze
    case dismiss
    case blocked

    var id: String {
        switch self {
        case .retry:
            return "retry"
        case .confirm:
            return "confirm"
        case .openRecord(let type, let id):
            return "open-\(type.rawValue)-\(id.uuidString)"
        case .mergeThing(let id):
            return "merge-\(id.uuidString)"
        case .reassignRecords(let id):
            return "reassign-\(id.uuidString)"
        case .adjustReminderTiming:
            return "adjust-reminder-timing"
        case .buildReminderDraft:
            return "build-reminder-draft"
        case .saveAsNote:
            return "save-as-note"
        case .snooze:
            return "snooze"
        case .dismiss:
            return "dismiss"
        case .blocked:
            return "blocked"
        }
    }
}

enum LedgerReviewReconciliationActionRole: String, Equatable {
    case primary
    case edit
    case contextual
    case note
    case reviewState
    case destructive
    case blocked
}
