import SwiftUI

enum LedgerBadgeRole: String, CaseIterable, Equatable {
    case category
    case source
    case status
    case action
    case timing

    var sortOrder: Int {
        switch self {
        case .action:
            return 0
        case .status:
            return 1
        case .timing:
            return 2
        case .category:
            return 3
        case .source:
            return 4
        }
    }
}

enum LedgerBadgeSemantic: String, Equatable {
    case categoryThing
    case categoryEvent
    case categoryReminder
    case categoryNote
    case categoryMessage
    case categoryTimeline

    case sourceUser
    case sourceApp
    case sourceLog

    case statusSaved
    case statusSaving
    case statusSavedLocal
    case statusRetryPending
    case statusUpcoming
    case statusNow
    case statusPaused
    case statusReviewed
    case statusFailed
    case statusDismissed
    case statusSnoozed
    case statusExpired
    case statusUpdated

    case actionReview
    case collectionReview
    case collectionUpcoming

    case reminderDueDate
    case reminderWindow
    case reminderOngoing
    case reminderRepeating

    var role: LedgerBadgeRole {
        switch self {
        case .categoryThing, .categoryEvent, .categoryReminder, .categoryNote, .categoryMessage, .categoryTimeline:
            return .category
        case .sourceUser, .sourceApp, .sourceLog:
            return .source
        case .statusSaved, .statusSaving, .statusSavedLocal, .statusRetryPending, .statusUpcoming, .statusNow,
             .statusPaused, .statusReviewed, .statusFailed, .statusDismissed, .statusSnoozed, .statusExpired,
             .statusUpdated:
            return .status
        case .actionReview:
            return .action
        case .collectionReview, .collectionUpcoming, .reminderDueDate, .reminderWindow, .reminderOngoing,
             .reminderRepeating:
            return .timing
        }
    }

    var defaultLabel: String {
        switch self {
        case .categoryThing:
            return "Thing"
        case .categoryEvent:
            return "Event"
        case .categoryReminder:
            return "Reminder"
        case .categoryNote:
            return "Note"
        case .categoryMessage:
            return "Message"
        case .categoryTimeline:
            return "Timeline"
        case .sourceUser:
            return "You"
        case .sourceApp:
            return "App"
        case .sourceLog:
            return "Timeline"
        case .statusSaved, .statusSavedLocal:
            return "Saved"
        case .statusSaving:
            return "Saving"
        case .statusRetryPending:
            return "Retry later"
        case .statusUpcoming, .collectionUpcoming:
            return "Upcoming"
        case .statusNow:
            return "Now"
        case .statusPaused:
            return "Paused"
        case .statusReviewed:
            return "Reviewed"
        case .statusFailed:
            return "Failed"
        case .statusDismissed:
            return "Dismissed"
        case .statusSnoozed:
            return "Snoozed"
        case .statusExpired:
            return "Expired"
        case .statusUpdated:
            return "Updated"
        case .actionReview, .collectionReview:
            return "Review"
        case .reminderDueDate:
            return "Due date"
        case .reminderWindow:
            return "Window"
        case .reminderOngoing:
            return "Ongoing"
        case .reminderRepeating:
            return "Repeating"
        }
    }

    var defaultTone: LedgerTone {
        switch self {
        case .statusFailed:
            return .danger
        case .statusNow:
            return .attention
        case .statusUpcoming, .collectionUpcoming:
            return .info
        case .categoryNote:
            return .note
        default:
            return .muted
        }
    }

    var defaultPriority: Int {
        switch role {
        case .action:
            return 80
        case .status:
            return 70
        case .timing:
            return 50
        case .category:
            return 30
        case .source:
            return 20
        }
    }
}

struct LedgerBadgePresentation: Equatable, Identifiable {
    let role: LedgerBadgeRole
    let semantic: LedgerBadgeSemantic
    let label: String
    let tone: LedgerTone
    let priority: Int

    var id: String {
        "\(role.rawValue)-\(semantic.rawValue)-\(label)"
    }

    init(
        semantic: LedgerBadgeSemantic,
        label: String? = nil,
        tone: LedgerTone? = nil,
        priority: Int? = nil
    ) {
        self.role = semantic.role
        self.semantic = semantic
        self.label = label ?? semantic.defaultLabel
        self.tone = tone ?? semantic.defaultTone
        self.priority = priority ?? semantic.defaultPriority
    }

    static func visibleBadges(from badges: [LedgerBadgePresentation], maxCount: Int) -> [LedgerBadgePresentation] {
        guard maxCount > 0 else { return [] }
        return badges
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                if lhs.role.sortOrder != rhs.role.sortOrder {
                    return lhs.role.sortOrder < rhs.role.sortOrder
                }
                return lhs.label < rhs.label
            }
            .prefix(maxCount)
            .map(\.self)
    }
}

struct LedgerBadgePill: View {
    let badge: LedgerBadgePresentation
    var size: LedgerPillSize = .small

    var body: some View {
        LedgerPill(text: badge.label, tone: badge.tone, size: size)
    }
}

extension LedgerBadgePresentation {
    static func feedSource(for source: LedgerFeedRowContent.Source) -> LedgerBadgePresentation {
        switch source {
        case .user:
            return LedgerBadgePresentation(semantic: .sourceUser)
        case .status:
            return LedgerBadgePresentation(semantic: .sourceLog)
        case .system:
            return LedgerBadgePresentation(semantic: .sourceApp)
        case .event:
            return LedgerBadgePresentation(semantic: .categoryEvent)
        case .reminder:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .note:
            return LedgerBadgePresentation(semantic: .categoryNote)
        }
    }

    static func searchCategory(for kind: LocalSearchEntityKind) -> LedgerBadgePresentation {
        switch kind {
        case .thing:
            return LedgerBadgePresentation(semantic: .categoryThing)
        case .event:
            return LedgerBadgePresentation(semantic: .categoryEvent)
        case .rule:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .note:
            return LedgerBadgePresentation(semantic: .categoryNote)
        case .chatMessage:
            return LedgerBadgePresentation(semantic: .categoryMessage)
        case .timelineSlice:
            return LedgerBadgePresentation(semantic: .categoryTimeline)
        }
    }

    static func relatedCategory(for type: EntityLinkType) -> LedgerBadgePresentation {
        switch type {
        case .chatMessage:
            return LedgerBadgePresentation(semantic: .categoryMessage)
        case .event:
            return LedgerBadgePresentation(semantic: .categoryEvent)
        case .note:
            return LedgerBadgePresentation(semantic: .categoryNote)
        case .rule:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .thing:
            return LedgerBadgePresentation(semantic: .categoryThing)
        }
    }

    static func timelineCategory(for kind: TimelineSliceRecordKind) -> LedgerBadgePresentation {
        switch kind {
        case .message:
            return LedgerBadgePresentation(semantic: .categoryMessage)
        case .event:
            return LedgerBadgePresentation(semantic: .categoryEvent)
        case .reminder:
            return LedgerBadgePresentation(semantic: .categoryReminder)
        case .note:
            return LedgerBadgePresentation(semantic: .categoryNote)
        case .thing:
            return LedgerBadgePresentation(semantic: .categoryThing)
        }
    }

    static func reminderStatus(for lane: ReminderContinuityLane) -> LedgerBadgePresentation {
        switch lane {
        case .now:
            return LedgerBadgePresentation(semantic: .statusNow, priority: 90)
        case .comingUp:
            return LedgerBadgePresentation(semantic: .statusUpcoming, priority: 75)
        case .review:
            return LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 85)
        case .paused:
            return LedgerBadgePresentation(semantic: .statusPaused, priority: 65)
        }
    }

    static func reminderType(for behavior: LedgerContinuityBehavior) -> LedgerBadgePresentation {
        switch behavior {
        case .dateBasedReminder:
            return LedgerBadgePresentation(semantic: .reminderDueDate)
        case .timeLimitedWindow:
            return LedgerBadgePresentation(semantic: .reminderWindow)
        case .ongoing:
            return LedgerBadgePresentation(semantic: .reminderOngoing)
        case .recurringText:
            return LedgerBadgePresentation(semantic: .reminderRepeating)
        }
    }

    static func reviewState(
        for state: LedgerReviewItemState,
        priority: Int,
        isHighPriority: Bool
    ) -> LedgerBadgePresentation {
        switch state {
        case .candidate, .ready, .presented:
            return LedgerBadgePresentation(
                semantic: .actionReview,
                tone: isHighPriority ? .attention : .muted,
                priority: priority
            )
        case .accepted:
            return LedgerBadgePresentation(semantic: .statusReviewed, priority: priority)
        case .dismissed:
            return LedgerBadgePresentation(semantic: .statusDismissed, priority: priority)
        case .snoozed:
            return LedgerBadgePresentation(semantic: .statusSnoozed, priority: priority)
        case .superseded:
            return LedgerBadgePresentation(semantic: .statusUpdated, priority: priority)
        case .expired:
            return LedgerBadgePresentation(semantic: .statusExpired, priority: priority)
        case .failed:
            return LedgerBadgePresentation(semantic: .statusFailed, priority: priority)
        }
    }
}
