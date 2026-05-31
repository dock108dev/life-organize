import Foundation

struct ChatConfirmationRecords {
    var events: [LedgerEvent] = []
    var rules: [LedgerRule] = []
    var notes: [LedgerNote] = []
    var standaloneThings: [Thing] = []
}

struct ChatResponseFormatter {
    private let maxInlineRecords = 5
    private let ruleStatusService = RuleStatusService()

    func confirmation(
        for records: ChatConfirmationRecords,
        reviewLine: String? = nil,
        recallAnswer: String? = nil
    ) -> String {
        var sections: [String] = []

        if !records.events.isEmpty {
            let label = records.events.count == 1 ? "Event saved:" : "Events saved:"
            sections.append(section(label: label, lines: eventLines(records.events)))
        }
        if !records.rules.isEmpty {
            sections.append(contentsOf: ruleSections(records.rules))
        }
        if !records.notes.isEmpty {
            sections.append(noteSection(records.notes))
        }
        if !records.standaloneThings.isEmpty {
            sections.append(section(label: "Thing saved:", lines: thingLines(records.standaloneThings)))
        }
        if let reviewLine, !reviewLine.isEmpty {
            sections.append(reviewLine)
        }
        if let recallAnswer, !recallAnswer.isEmpty {
            sections.append(recallAnswer)
        }

        return sections.isEmpty ? rawOnlyFailure() : sections.joined(separator: "\n\n")
    }

    func rawOnlyFailure() -> String {
        "Saved for review.\nOpen the timeline entry to review the saved text."
    }

    func extractionFailed() -> String {
        "Saved for review.\nOpen the timeline entry to review the saved text."
    }

    func extractionUnavailable(reason: String) -> String {
        "Saved on this device. \(reason)"
    }

    func delayedOrganization(_ line: String) -> String {
        "Saved on this device.\n\(line)"
    }

    func unsupportedBoundary() -> String {
        "Add to Timeline, search saved entries, or check Carry Forward."
    }

    func webLookupUnavailable() -> String {
        "Web results:\nThe service is unavailable for current web information."
    }

    func webLookupAnswer(_ text: String?) -> String {
        guard let text, !text.isEmpty else {
            return "Web results:\nNo current web results found."
        }
        let displayText = text.replacingOccurrences(of: "Source:", with: "Link:")
        if text.hasPrefix("Web results:") {
            return displayText
        }
        return "Web results:\n\(displayText)"
    }

    func lastLogged(event: LedgerEvent, thing: Thing?) -> String {
        section(label: "Last logged:", lines: [eventLine(event, thing: thing)])
    }

    func activeRule(_ rule: LedgerRule, now: Date = Date()) -> String {
        var lines = [ruleLine(rule)]
        if let expiresAt = rule.expiresAt {
            lines.append(ruleStatusService.daysRemainingDisplay(until: expiresAt, at: now))
        }
        return section(label: rule.ruleType.isReminderLike ? "Now:" : "Active restriction:", lines: lines)
    }

    func expiredRule(_ rule: LedgerRule) -> String {
        section(label: "Last expired:", lines: [expiredRuleLine(rule)])
    }

    func reminderLookup(_ rule: LedgerRule, status: RuleStatus, now: Date = Date()) -> String {
        let presentation = ReminderContinuityPresentationService(statusService: ruleStatusService)
            .presentation(for: rule, at: now)
        return section(
            label: "\(presentation.lane.title):",
            lines: ["\(rule.title).", presentation.primaryLine]
        )
    }

    func permissionBlocked(by rules: [LedgerRule], now: Date = Date()) -> String {
        let ruleLines = rules.prefix(3).map(ruleLine)
        var sections = ["Blocked."]
        sections.append(section(label: rules.count == 1 ? "Active restriction:" : "Active restrictions:", lines: ruleLines))

        if let firstExpiration = rules.compactMap(\.expiresAt).min() {
            sections.append(ruleStatusService.daysRemainingDisplay(until: firstExpiration, at: now))
        }
        if rules.count > 3 {
            sections.append("\(rules.count - 3) more related active restrictions.")
        }

        return sections.joined(separator: "\n\n")
    }

    func noActiveRule(target: String?, expiredRule: LedgerRule?, noun: String = "reminder") -> String {
        var answer: String
        if let target, !target.isEmpty {
            answer = "No active \(noun) found for \(target)"
        } else {
            answer = "No active \(noun)s found"
        }
        answer += "."

        guard let expiredRule else { return answer }
        let expiredDate = expiredRule.expiresAt.map(Self.date) ?? "an earlier date"
        return """
        \(answer)

        The most recent related \(noun) expired on \(expiredDate):
        \(expiredRule.title).
        """
    }

    func recentNotes(_ notes: [LedgerNote]) -> String {
        section(label: "Recent notes:", lines: notes.prefix(3).map(noteBulletLine))
    }

    func found(events: [LedgerEvent], rules: [LedgerRule], notes: [LedgerNote]) -> String {
        let total = events.count + rules.count + notes.count
        if total > maxInlineRecords {
            return "\(total) related items found.\nOpen Things to review them."
        }

        let lines = events.map { "- \(eventLine($0, thing: $0.thing))" }
            + rules.map { "- \(ruleLine($0))" }
            + notes.map(noteBulletLine)
        return (["Local results:"] + lines).joined(separator: "\n")
    }

    private func section(label: String, lines: [String]) -> String {
        ([label] + lines).joined(separator: "\n")
    }

    private func eventLines(_ events: [LedgerEvent]) -> [String] {
        guard events.count <= maxInlineRecords else {
            return ["\(events.count) events saved.", "Open Things to review them."]
        }
        return events.map { eventLine($0, thing: $0.thing) }
    }

    private func eventLine(_ event: LedgerEvent, thing: Thing?) -> String {
        var firstSentence = recordName(event.title)
        if let thingName = thing?.name.nilIfEmpty {
            firstSentence += " for \(thingName)"
        }
        firstSentence += " on \(Self.date(event.occurredAt))."

        var parts = [firstSentence]
        if let metadata = EventMetadataDisplayFormatter.summary(
            for: event.metadataEntries,
            eventType: event.eventType,
            limit: 3,
            labelSeparator: " was ",
            itemSeparator: " ",
            terminator: "."
        ) {
            parts.append(metadata)
        }
        return parts.joined(separator: " ")
    }

    private func ruleLines(_ rules: [LedgerRule]) -> [String] {
        guard rules.count <= maxInlineRecords else {
            return ["\(rules.count) items saved.", "Open Carry Forward to review them."]
        }
        return rules.map(ruleLine)
    }

    private func ruleSections(_ rules: [LedgerRule]) -> [String] {
        let groupedRules = Dictionary(grouping: rules) { $0.ruleType.savedDisplayNoun }
        return groupedRules.keys.sorted().compactMap { noun in
            guard let rules = groupedRules[noun] else { return nil }
            let label = rules.count == 1 ? "\(noun) saved:" : "\(noun)s saved:"
            return section(label: label, lines: ruleLines(rules))
        }
    }

    private func ruleLine(_ rule: LedgerRule) -> String {
        if rule.continuityBehavior == .recurringText {
            return "\(rule.title).\nSaved wording only; it will not repeat automatically."
        }
        if rule.continuityBehavior == .dateBasedReminder {
            return "\(rule.title) on \(Self.date(rule.startsAt))."
        }
        if let expiresAt = rule.expiresAt {
            if !Self.utcCalendar.isDate(rule.startsAt, inSameDayAs: rule.createdAt) {
                return "\(rule.title) from \(Self.date(rule.startsAt)) until \(Self.date(expiresAt))."
            }
            return "\(rule.title) until \(Self.date(expiresAt))."
        }
        return "\(rule.title).\nNo expiration set."
    }

    private func expiredRuleLine(_ rule: LedgerRule) -> String {
        guard let expiresAt = rule.expiresAt else { return "\(rule.title)." }
        return "\(rule.title) - \(Self.date(expiresAt))."
    }

    private func noteSection(_ notes: [LedgerNote]) -> String {
        if notes.count == 1, let note = notes.first {
            return section(label: "Note saved:", lines: [noteLine(note)])
        }
        return section(label: "Notes saved:", lines: notes.prefix(maxInlineRecords).map(noteBulletLine))
    }

    private func noteLine(_ note: LedgerNote) -> String {
        if let thing = note.linkedThings.first {
            return "\(thing.name) - \(quoted(note.text))"
        }
        return quoted(note.text)
    }

    private func noteBulletLine(_ note: LedgerNote) -> String {
        "- \(quoted(note.text))"
    }

    private func thingLines(_ things: [Thing]) -> [String] {
        guard things.count <= maxInlineRecords else {
            return ["\(things.count) things saved.", "Open Things to review them."]
        }
        return things.map { "\($0.name)." }
    }

    private func recordName(_ value: String) -> String {
        let name = value
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled entry" : trimmed
    }

    private func quoted(_ text: String) -> String {
        #""\#(LedgerDisplayFormatting.ellipsized(text, maxLength: 160))""#
    }

    static func date(_ date: Date) -> String {
        RuleStatusService.date(date)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
