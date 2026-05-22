import Foundation

enum ReminderContinuityLane: CaseIterable, Hashable {
    case now
    case comingUp
    case review
    case paused

    var title: String {
        switch self {
        case .now:
            "Now"
        case .comingUp:
            "Coming Up"
        case .review:
            "Review"
        case .paused:
            "Paused"
        }
    }

    var tone: LedgerTone {
        switch self {
        case .now:
            .attention
        case .comingUp:
            .info
        case .review:
            .attention
        case .paused:
            .muted
        }
    }

    var rowEmphasis: LedgerRowEmphasis {
        switch self {
        case .now, .comingUp:
            .active
        case .review:
            .attention
        case .paused:
            .inactive
        }
    }
}

struct ReminderContinuityPresentation: Equatable {
    let lane: ReminderContinuityLane
    let statusBadge: LedgerBadgePresentation
    let typeBadge: LedgerBadgePresentation
    let badges: [LedgerBadgePresentation]
    let primaryLine: String
    let dateLine: String?
    let detailTimingRows: [MetadataRowContent]

    var badge: String { statusBadge.label }
    var tone: LedgerTone { statusBadge.tone }
}

struct MetadataRowContent: Equatable {
    let label: String
    let value: String
}

struct ReminderContinuityPresentationService {
    private let statusService: RuleStatusService

    init(statusService: RuleStatusService = RuleStatusService()) {
        self.statusService = statusService
    }

    func presentation(for rule: LedgerRule, at date: Date = Date()) -> ReminderContinuityPresentation {
        let status = statusService.status(for: rule, at: date)
        let lane = lane(for: status)
        let statusBadge = LedgerBadgePresentation.reminderStatus(for: lane)
        let typeBadge = LedgerBadgePresentation.reminderType(for: rule.continuityBehavior)

        return ReminderContinuityPresentation(
            lane: lane,
            statusBadge: statusBadge,
            typeBadge: typeBadge,
            badges: LedgerBadgePresentation.visibleBadges(from: [statusBadge, typeBadge], maxCount: 2),
            primaryLine: primaryLine(for: rule, status: status, at: date),
            dateLine: dateLine(for: rule, status: status, at: date),
            detailTimingRows: detailTimingRows(for: rule, status: status, lane: lane, at: date)
        )
    }

    func lane(for status: RuleStatus) -> ReminderContinuityLane {
        switch status {
        case .active:
            .now
        case .scheduled:
            .comingUp
        case .expired:
            .review
        case .inactive:
            .paused
        }
    }

    func rules(_ rules: [LedgerRule], in lane: ReminderContinuityLane, at date: Date = Date()) -> [LedgerRule] {
        rules
            .filter { self.lane(for: statusService.status(for: $0, at: date)) == lane }
            .sorted { sortPrecedes($0, $1, lane: lane, at: date) }
    }

    func continuityTypeDisplayName(for behavior: LedgerContinuityBehavior) -> String {
        switch behavior {
        case .dateBasedReminder:
            "Due date"
        case .timeLimitedWindow:
            "Time window"
        case .ongoing:
            "Ongoing context"
        case .recurringText:
            "Recurring wording"
        }
    }

    private func primaryLine(for rule: LedgerRule, status: RuleStatus, at date: Date) -> String {
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            return dateBasedPrimaryLine(for: rule, status: status, at: date)
        case .timeLimitedWindow:
            return timeWindowPrimaryLine(for: rule, status: status)
        case .ongoing:
            return ongoingPrimaryLine(for: rule, status: status, at: date)
        case .recurringText:
            return recurringPrimaryLine(for: rule, status: status)
        }
    }

    private func dateLine(for rule: LedgerRule, status: RuleStatus, at date: Date) -> String? {
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            switch status {
            case .active:
                return rule.startsAt < date && !Self.calendar.isDate(rule.startsAt, inSameDayAs: date)
                    ? "Carried forward until completed or rescheduled"
                    : "Set for \(Self.longDate(rule.startsAt))"
            case .scheduled:
                return "Will move to Now on that date"
            case .expired:
                return "Choose whether to complete or reschedule"
            case .inactive:
                return "Original due date \(Self.shortDate(rule.startsAt))"
            }
        case .timeLimitedWindow:
            switch status {
            case .active:
                return rule.expiresAt.map { statusService.daysRemainingDisplay(until: $0, at: date).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            case .scheduled:
                return rule.expiresAt.map { "Runs through \(Self.longDate($0))" }
            case .expired:
                return "Review whether to extend or let it rest"
            case .inactive:
                return rule.expiresAt.map { "Original end date \(Self.shortDate($0))" }
            }
        case .ongoing:
            switch status {
            case .active:
                if let expiresAt = rule.expiresAt {
                    return statusService.daysRemainingDisplay(until: expiresAt, at: date).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }
                return "No planned end"
            case .scheduled:
                return rule.expiresAt.map { "Ends \(Self.longDate($0))" } ?? "No planned end"
            case .expired:
                return "Review whether this still matters"
            case .inactive:
                return rule.manuallyDeactivatedAt.map { "Paused \(Self.shortDate($0))" }
            }
        case .recurringText:
            switch status {
            case .active, .scheduled:
                return "Use the original wording as the repeat cue"
            case .expired:
                return "Update the reminder if the pattern changed"
            case .inactive:
                return "Original wording remains saved"
            }
        }
    }

    private func detailTimingRows(
        for rule: LedgerRule,
        status: RuleStatus,
        lane: ReminderContinuityLane,
        at date: Date
    ) -> [MetadataRowContent] {
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            return dateBasedTimingRows(for: rule, status: status, lane: lane)
        case .timeLimitedWindow:
            return timeWindowTimingRows(for: rule, status: status, lane: lane, at: date)
        case .ongoing:
            return ongoingTimingRows(for: rule, status: status, lane: lane, at: date)
        case .recurringText:
            return recurringTimingRows(for: rule, status: status, lane: lane)
        }
    }

    private func dateBasedPrimaryLine(for rule: LedgerRule, status: RuleStatus, at date: Date) -> String {
        switch status {
        case .active:
            if Self.calendar.isDate(rule.startsAt, inSameDayAs: date) {
                return "Due today"
            }
            if rule.startsAt < date {
                return "Due since \(Self.longDate(rule.startsAt))"
            }
            return "Due \(Self.longDate(rule.startsAt))"
        case .scheduled:
            return "Due \(Self.longDate(rule.startsAt))"
        case .expired:
            return "Date passed"
        case .inactive:
            return "No longer carried forward"
        }
    }

    private func timeWindowPrimaryLine(for rule: LedgerRule, status: RuleStatus) -> String {
        switch status {
        case .active:
            return rule.expiresAt.map { "Open until \(Self.longDate($0))" } ?? "Open window"
        case .scheduled:
            return "Opens \(Self.longDate(rule.startsAt))"
        case .expired:
            return rule.expiresAt.map { "Ended \(Self.longDate($0))" } ?? "Window ended"
        case .inactive:
            return "Window stopped"
        }
    }

    private func ongoingPrimaryLine(for rule: LedgerRule, status: RuleStatus, at date: Date) -> String {
        switch status {
        case .active:
            return rule.expiresAt.map { "Carried forward until \(Self.longDate($0))" } ?? "Carried forward"
        case .scheduled:
            return "Starts \(Self.longDate(rule.startsAt))"
        case .expired:
            return rule.expiresAt.map { "Ended \(Self.longDate($0))" } ?? "Ended"
        case .inactive:
            return "No longer carried forward"
        }
    }

    private func recurringPrimaryLine(for rule: LedgerRule, status: RuleStatus) -> String {
        switch status {
        case .active:
            return "Recurring intention saved"
        case .scheduled:
            return "Recurring intention starts \(Self.longDate(rule.startsAt))"
        case .expired:
            return "Repeat wording may need review"
        case .inactive:
            return "Recurring intention paused"
        }
    }

    private func dateBasedTimingRows(
        for rule: LedgerRule,
        status: RuleStatus,
        lane: ReminderContinuityLane
    ) -> [MetadataRowContent] {
        switch status {
        case .active:
            return [
                MetadataRowContent(label: "Due", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Next step", value: "Complete or reschedule"),
            ]
        case .scheduled:
            return [
                MetadataRowContent(label: "Due", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Moves to Now", value: Self.fullDate(rule.startsAt)),
            ]
        case .expired:
            return [
                MetadataRowContent(label: "Due", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Next step", value: "Complete, reschedule, or pause"),
            ]
        case .inactive:
            return [
                MetadataRowContent(label: "Original due date", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Paused", value: rule.manuallyDeactivatedAt.map(Self.fullDate) ?? "Stopped"),
            ]
        }
    }

    private func timeWindowTimingRows(
        for rule: LedgerRule,
        status: RuleStatus,
        lane: ReminderContinuityLane,
        at date: Date
    ) -> [MetadataRowContent] {
        switch status {
        case .active:
            return [
                MetadataRowContent(label: "Window opened", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Window closes", value: rule.expiresAt.map(Self.fullDate) ?? "No planned end"),
                MetadataRowContent(label: "Time left", value: rule.expiresAt.map { statusService.daysRemainingDisplay(until: $0, at: date) } ?? "No planned end"),
            ]
        case .scheduled:
            return [
                MetadataRowContent(label: "Window opens", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Window closes", value: rule.expiresAt.map(Self.fullDate) ?? "No planned end"),
                MetadataRowContent(label: "Current place", value: lane.title),
            ]
        case .expired:
            return [
                MetadataRowContent(label: "Window opened", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Window ended", value: rule.expiresAt.map(Self.fullDate) ?? "Ended"),
                MetadataRowContent(label: "Next step", value: "Extend or let it rest"),
            ]
        case .inactive:
            return [
                MetadataRowContent(label: "Window started", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Original end", value: rule.expiresAt.map(Self.fullDate) ?? "No planned end"),
                MetadataRowContent(label: "Current place", value: lane.title),
            ]
        }
    }

    private func ongoingTimingRows(
        for rule: LedgerRule,
        status: RuleStatus,
        lane: ReminderContinuityLane,
        at date: Date
    ) -> [MetadataRowContent] {
        switch status {
        case .active:
            var rows = [
                MetadataRowContent(label: "Started", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Planned end", value: rule.expiresAt.map(Self.fullDate) ?? "No planned end"),
            ]
            if let expiresAt = rule.expiresAt {
                rows.append(MetadataRowContent(label: "Time left", value: statusService.daysRemainingDisplay(until: expiresAt, at: date)))
            }
            return rows
        case .scheduled:
            return [
                MetadataRowContent(label: "Starts", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Planned end", value: rule.expiresAt.map(Self.fullDate) ?? "No planned end"),
                MetadataRowContent(label: "Current place", value: lane.title),
            ]
        case .expired:
            return [
                MetadataRowContent(label: "Started", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Ended", value: rule.expiresAt.map(Self.fullDate) ?? "Ended"),
                MetadataRowContent(label: "Next step", value: "Renew or let it rest"),
            ]
        case .inactive:
            return [
                MetadataRowContent(label: "Started", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Paused", value: rule.manuallyDeactivatedAt.map(Self.fullDate) ?? "Stopped"),
            ]
        }
    }

    private func recurringTimingRows(
        for rule: LedgerRule,
        status: RuleStatus,
        lane: ReminderContinuityLane
    ) -> [MetadataRowContent] {
        switch status {
        case .active:
            return [
                MetadataRowContent(label: "Pattern", value: "Saved from original wording"),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Automation", value: "Not scheduled automatically"),
            ]
        case .scheduled:
            return [
                MetadataRowContent(label: "Starts", value: Self.fullDate(rule.startsAt)),
                MetadataRowContent(label: "Pattern", value: "Saved from original wording"),
                MetadataRowContent(label: "Automation", value: "Not scheduled automatically"),
            ]
        case .expired:
            return [
                MetadataRowContent(label: "Pattern", value: "Saved from original wording"),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Next step", value: "Update wording or pause"),
            ]
        case .inactive:
            return [
                MetadataRowContent(label: "Pattern", value: "Saved from original wording"),
                MetadataRowContent(label: "Current place", value: lane.title),
                MetadataRowContent(label: "Original wording", value: "Remains saved"),
            ]
        }
    }

    private func sortPrecedes(_ lhs: LedgerRule, _ rhs: LedgerRule, lane: ReminderContinuityLane, at date: Date) -> Bool {
        switch lane {
        case .now:
            let lhsKey = nowSortKey(for: lhs)
            let rhsKey = nowSortKey(for: rhs)
            if lhsKey.priority != rhsKey.priority {
                return lhsKey.priority < rhsKey.priority
            }
            if lhsKey.date != rhsKey.date {
                return lhsKey.date < rhsKey.date
            }
        case .comingUp:
            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }
        case .review:
            let lhsDate = lhs.expiresAt ?? lhs.startsAt
            let rhsDate = rhs.expiresAt ?? rhs.startsAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        case .paused:
            let lhsDate = lhs.manuallyDeactivatedAt ?? lhs.updatedAt
            let rhsDate = rhs.manuallyDeactivatedAt ?? rhs.updatedAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func nowSortKey(for rule: LedgerRule) -> (priority: Int, date: Date) {
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            (0, rule.startsAt)
        case .timeLimitedWindow:
            (1, rule.expiresAt ?? .distantFuture)
        case .ongoing:
            (2, rule.expiresAt ?? .distantFuture)
        case .recurringText:
            (3, rule.startsAt)
        }
    }

    private static func longDate(_ date: Date) -> String {
        RuleStatusService.date(date)
    }

    private static func shortDate(_ date: Date) -> String {
        DateFormatting.shortDate.string(from: date)
    }

    private static func fullDate(_ date: Date) -> String {
        DateFormatting.fullDate.string(from: date)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
