import Foundation

struct ReminderDetailSummaryPresentation: Equatable {
    let title: String
    let stateSentence: String
    let scheduleSentence: String
    let contextSentence: String
    let reasonSentence: String
    let sourceSentence: String
    let actionSentence: String?
    let actionTitles: [String]
}

struct ReminderDetailSummaryService {
    private let continuityService: ReminderContinuityPresentationService
    private let statusService: RuleStatusService

    init(
        continuityService: ReminderContinuityPresentationService = ReminderContinuityPresentationService(),
        statusService: RuleStatusService = RuleStatusService()
    ) {
        self.continuityService = continuityService
        self.statusService = statusService
    }

    func presentation(for rule: LedgerRule, at date: Date = Date()) -> ReminderDetailSummaryPresentation {
        let status = statusService.status(for: rule, at: date)
        let continuity = continuityService.presentation(for: rule, at: date)
        let actionTitles = [
            ReminderDetailActionPolicy.dateAction(for: rule, status: status)?.title,
            ReminderDetailActionPolicy.lifecycleAction(for: rule, status: status)?.title,
        ].compactMap(\.self)

        return ReminderDetailSummaryPresentation(
            title: rule.title,
            stateSentence: stateSentence(from: continuity),
            scheduleSentence: scheduleSentence(for: rule),
            contextSentence: contextSentence(for: rule),
            reasonSentence: reasonSentence(for: rule),
            sourceSentence: sourceSentence(for: rule),
            actionSentence: actionSentence(for: actionTitles),
            actionTitles: actionTitles
        )
    }

    private func stateSentence(from continuity: ReminderContinuityPresentation) -> String {
        [continuity.primaryLine, continuity.dateLine]
            .compactMap { $0?.nilIfEmpty }
            .map(Self.sentence)
            .joined(separator: " ")
    }

    private func scheduleSentence(for rule: LedgerRule) -> String {
        let start = Self.longDate(rule.startsAt)
        switch rule.continuityBehavior {
        case .dateBasedReminder:
            return "Planned for \(start)."
        case .timeLimitedWindow:
            return "Planned from \(start)\(endDatePhrase(for: rule))."
        case .ongoing:
            return "Carried from \(start)\(endDatePhrase(for: rule))."
        case .recurringText:
            return "Pattern starts \(start)\(endDatePhrase(for: rule))."
        }
    }

    private func endDatePhrase(for rule: LedgerRule) -> String {
        if let expiresAt = rule.expiresAt {
            return " through \(Self.longDate(expiresAt))"
        }
        return " with no planned end"
    }

    private func contextSentence(for rule: LedgerRule) -> String {
        guard let thingName = rule.thing?.name.nilIfEmpty else {
            return "Not connected to a thing yet."
        }
        return "Connected to \(thingName)."
    }

    private func reasonSentence(for rule: LedgerRule) -> String {
        guard let reason = rule.reason?.nilIfEmpty else {
            return "No reason was saved with this reminder."
        }
        return Self.sentence(reason)
    }

    private func sourceSentence(for rule: LedgerRule) -> String {
        if rule.sourceMessage != nil {
            return "Added from your timeline."
        }
        return "Added manually on \(DateFormatting.shortDate.string(from: rule.createdAt))."
    }

    private func actionSentence(for titles: [String]) -> String? {
        guard !titles.isEmpty else { return nil }
        return "Available next actions: \(Self.joinedList(titles))."
    }

    private static func sentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        return "\(trimmed)."
    }

    private static func joinedList(_ values: [String]) -> String {
        if values.count <= 2 {
            return values.joined(separator: " and ")
        }
        return values.dropLast().joined(separator: ", ") + ", and \(values.last ?? "")"
    }

    private static func longDate(_ date: Date) -> String {
        RuleStatusService.date(date)
    }
}
