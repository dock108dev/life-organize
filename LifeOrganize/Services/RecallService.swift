import Foundation

struct RecallService {
    var now: Date = Date()

    func answer(query: String) -> RecallResult {
        RecallResult(query: query, answer: "No saved records found.")
    }

    func answer(
        query: String,
        things: [Thing],
        events: [LedgerEvent] = [],
        rules: [LedgerRule] = [],
        notes: [LedgerNote] = [],
        chatMessages: [ChatMessage] = []
    ) -> RecallResult {
        if let lastTimeAnswer = answerLastTime(query: query, things: things, events: events) {
            return RecallResult(query: query, answer: lastTimeAnswer)
        }

        if isRuleQuestion(query), let ruleAnswer = RuleLookupService(now: now).answer(query: query, things: things, rules: rules) {
            return RecallResult(query: query, answer: ruleAnswer)
        }

        if isBroadRecall(query) {
            return answerPriorRecall(
                query: query,
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                chatMessages: chatMessages
            )
        }

        let search = SearchService()
        let matchingThings = things.filter { search.contains(query, in: $0) }
        let matchingThingIDs = Set(matchingThings.map(\.id))
        let matchingEvents = events
            .filter { event in
                matches(query, event: event, search: search)
                    || event.thing.map { matchingThingIDs.contains($0.id) } == true
            }
            .sorted { $0.occurredAt > $1.occurredAt }
        let matchingRules = rules
            .filter { rule in
                matches(query, rule: rule, search: search)
                    || rule.thing.map { matchingThingIDs.contains($0.id) } == true
            }
            .sorted { ($0.expiresAt ?? .distantFuture) > ($1.expiresAt ?? .distantFuture) }
        let matchingNotes = notes
            .filter { note in
                matches(query, note: note, search: search)
                    || note.linkedThings.contains { matchingThingIDs.contains($0.id) }
            }
            .sorted { $0.createdAt > $1.createdAt }

        guard !matchingEvents.isEmpty || !matchingRules.isEmpty || !matchingNotes.isEmpty || !matchingThings.isEmpty else {
            return answer(query: query)
        }

        let formatter = ChatResponseFormatter()
        let ruleStatusService = RuleStatusService()
        let activeRules = matchingRules.filter { ruleStatusService.isActive($0, at: now) }

        if let latestEvent = matchingEvents.first {
            return RecallResult(query: query, answer: formatter.lastLogged(event: latestEvent, thing: latestEvent.thing))
        }

        if let activeRule = activeRules.first {
            return RecallResult(query: query, answer: formatter.activeRule(activeRule, now: now))
        }

        if !matchingNotes.isEmpty {
            return RecallResult(query: query, answer: formatter.recentNotes(matchingNotes))
        }

        if isRuleQuestion(query) {
            let expiredRules = matchingRules.filter { ruleStatusService.status(for: $0, at: now) == .expired }
            if let expiredRule = expiredRules.first {
                let noun = isReminderQuestion(query) ? "reminder" : "restriction"
                return RecallResult(query: query, answer: formatter.noActiveRule(target: nil, expiredRule: expiredRule, noun: noun))
            }
            return RecallResult(
                query: query,
                answer: isReminderQuestion(query)
                    ? "No active reminders found."
                    : "No active restrictions found."
            )
        }

        return answer(query: query)
    }

    private func answerPriorRecall(
        query: String,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        chatMessages: [ChatMessage]
    ) -> RecallResult {
        let topic = recallTopic(from: query)
        let search = SearchService()
        let records = search.records(
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            messages: chatMessages.filter { $0.role == .user }
        )
        let results = search
            .recallSearch(topic, in: records, now: now)
            .sorted { lhs, rhs in
                let lhsPriority = recallPriority(lhs.sourceKind)
                let rhsPriority = recallPriority(rhs.sourceKind)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.score > rhs.score
            }

        guard !results.isEmpty else {
            return RecallResult(query: query, answer: recallNoMatchAnswer(topic: topic))
        }

        let lines = results.prefix(5).map(recallLine)
        return RecallResult(
            query: query,
            answer: (["Local results:"] + lines)
                .joined(separator: "\n")
        )
    }

    private func answerLastTime(query: String, things: [Thing], events: [LedgerEvent]) -> String? {
        let targetKey = lastTimeTarget(from: query)
        guard !targetKey.isEmpty else { return nil }
        guard !isBroadRecall(query) else { return nil }
        guard isLastTimeQuestion(query) || !isRuleQuestion(query) else { return nil }
        guard !events.isEmpty else {
            return isLastTimeQuestion(query) ? "No matching logged event found." : nil
        }

        let targetKeys = LedgerTextMatching.expandedTargetKeys(for: targetKey, rawQuery: query)
        let targetTokens = LedgerTextMatching.tokens(in: targetKey)
        let matchingThingIDs = Set(
            things.filter { thing in
                LedgerTextMatching.thingMatches(thing, targetKeys: targetKeys, targetTokens: targetTokens)
            }
            .map(\.id)
        )

        let matchingEvents = events
            .filter { event in
                if let thingID = event.thing?.id, matchingThingIDs.contains(thingID) {
                    return true
                }
                return eventMatches(event, targetKeys: targetKeys, targetTokens: targetTokens)
            }
            .sorted { $0.occurredAt > $1.occurredAt }

        guard let latestEvent = matchingEvents.first else {
            return isLastTimeQuestion(query) ? "No matching logged event found." : nil
        }

        return ChatResponseFormatter().lastLogged(event: latestEvent, thing: latestEvent.thing)
    }

    private func lastTimeTarget(from query: String) -> String {
        var text = LedgerTextMatching.normalizedAlphanumericText(query)

        for phrase in lastTimeBoilerplate {
            text = text.replacingOccurrences(of: phrase, with: " ")
        }

        let key = ThingNormalizer.normalizeKey(text)
            .split(separator: " ")
            .map(String.init)
            .filter { !lastTimeFillerWords.contains($0) }
            .joined(separator: " ")
        return key
    }

    private func eventMatches(_ event: LedgerEvent, targetKeys: Set<String>, targetTokens: Set<String>) -> Bool {
        let titleKey = ThingNormalizer.normalizeKey(event.title)
        let rawTextKey = ThingNormalizer.normalizeKey(event.rawText)
        return LedgerTextMatching.textMatches(titleKey, targetKeys: targetKeys, targetTokens: targetTokens)
            || LedgerTextMatching.textMatches(rawTextKey, targetKeys: targetKeys, targetTokens: targetTokens)
            || event.metadataEntries.contains { metadataMatches($0, targetKeys: targetKeys, targetTokens: targetTokens) }
            || event.note.map {
                LedgerTextMatching.textMatches(ThingNormalizer.normalizeKey($0), targetKeys: targetKeys, targetTokens: targetTokens)
            } == true
    }

    private func matches(_ query: String, event: LedgerEvent, search: SearchService) -> Bool {
        search.contains(query, in: event.title)
            || search.contains(query, in: event.rawText)
            || event.metadataEntries.contains { matches(query, metadata: $0, search: search) }
            || sharesMeaningfulToken(query, event.title)
            || event.note.map { search.contains(query, in: $0) } == true
    }

    private func metadataMatches(
        _ metadata: LedgerEventMetadataEntry,
        targetKeys: Set<String>,
        targetTokens: Set<String>
    ) -> Bool {
        metadataSearchKeys(metadata).contains { key in
            LedgerTextMatching.textMatches(key, targetKeys: targetKeys, targetTokens: targetTokens)
        }
    }

    private func matches(_ query: String, metadata: LedgerEventMetadataEntry, search: SearchService) -> Bool {
        metadataSearchKeys(metadata).contains { search.contains(query, in: $0) }
            || metadataSearchKeys(metadata).contains { sharesMeaningfulToken(query, $0) }
    }

    private func metadataSearchKeys(_ metadata: LedgerEventMetadataEntry) -> [String] {
        [
            metadata.key.rawValue,
            metadata.key.displayName,
            metadata.displayValue,
            metadata.sourceText
        ]
        .compactMap { $0?.nilIfEmpty }
        .map(ThingNormalizer.normalizeKey)
        .filter { !$0.isEmpty }
    }

    private func matches(_ query: String, rule: LedgerRule, search: SearchService) -> Bool {
        search.contains(query, in: rule.title)
            || search.contains(query, in: rule.rawText)
            || sharesMeaningfulToken(query, rule.title)
            || rule.reason.map { search.contains(query, in: $0) } == true
    }

    private func matches(_ query: String, note: LedgerNote, search: SearchService) -> Bool {
        search.contains(query, in: note.text) || sharesMeaningfulToken(query, note.text)
    }

    private func sharesMeaningfulToken(_ query: String, _ candidate: String) -> Bool {
        let queryTokens = meaningfulTokens(in: query)
        guard !queryTokens.isEmpty else { return false }
        return !queryTokens.isDisjoint(with: meaningfulTokens(in: candidate))
    }

    private func meaningfulTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "about",
            "another",
            "buy",
            "buying",
            "can",
            "did",
            "for",
            "have",
            "last",
            "may",
            "new",
            "say",
            "show",
            "the",
            "what",
            "when"
        ]
        return Set(
            ThingNormalizer.normalizeKey(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private func isRuleQuestion(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        return lowercased.contains("can i")
            || lowercased.contains("can we")
            || lowercased.contains("may i")
            || lowercased.contains("allowed")
            || lowercased.contains("reminder")
            || lowercased.contains("rule")
            || lowercased.contains("buy")
            || lowercased.contains("did i say no")
            || lowercased.contains("did i ban")
            || lowercased.contains("when can i")
    }

    private func isReminderQuestion(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        return lowercased.contains("reminder")
            || lowercased.contains("remember")
            || lowercased.contains("due")
    }

    private func isBroadRecall(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        return lowercased.contains("what do i have")
            || lowercased.contains("what do i know about")
            || lowercased.contains("what did i say")
            || lowercased.contains("what did i write")
            || lowercased.contains("what did i note")
            || lowercased.contains("what was my note")
            || lowercased.contains("did i mention")
            || lowercased.contains("notes about")
            || lowercased.contains("anything about")
            || lowercased.contains("anything saved about")
            || lowercased.contains("show")
            || lowercased.contains("find")
    }

    private func recallTopic(from query: String) -> String {
        var topic = query.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        for prefix in priorRecallPrefixes where topic.hasPrefix(prefix) {
            topic.removeFirst(prefix.count)
            break
        }

        var trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for article in ["the ", "a ", "an "] where trimmed.hasPrefix(article) {
            trimmed.removeFirst(article.count)
            break
        }
        return trimmed
    }

    private func recallPriority(_ kind: LocalSearchEntityKind) -> Int {
        switch kind {
        case .note:
            0
        case .chatMessage:
            1
        case .timelineSlice:
            2
        case .event:
            3
        case .rule:
            4
        case .thing:
            5
        }
    }

    private func recallLine(_ result: LocalSearchResult) -> String {
        let date = ChatResponseFormatter.date(result.date)
        var text = "- \(date) - \(quoted(recallDisplayText(for: result)))"
        if let linkedThingName = result.linkedThingName, result.sourceKind != .thing {
            text += " Related to \(linkedThingName)."
        }
        if result.sourceKind == .rule, result.record.isActiveRule == true {
            text += " Still active."
        }
        return text
    }

    private func recallDisplayText(for result: LocalSearchResult) -> String {
        switch result.sourceKind {
        case .chatMessage, .note, .rule:
            result.body ?? result.title
        case .event, .thing:
            result.title
        case .timelineSlice:
            [result.title, result.body].compactMap { $0?.nilIfEmpty }.joined(separator: ": ")
        }
    }

    private func recallNoMatchAnswer(topic: String) -> String {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No saved records found." }
        return #"No saved records found for "\#(trimmed)"."#
    }

    private func quoted(_ text: String) -> String {
        #""\#(LedgerDisplayFormatting.ellipsized(text, maxLength: 120))""#
    }

    private func isLastTimeQuestion(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        return lowercased.contains("last")
            || lowercased.contains("did i already")
            || lowercased.contains("did we already")
            || lowercased.contains("have i already")
            || lowercased.contains("have we already")
            || (lowercased.contains("have i") && lowercased.contains("recently"))
            || (lowercased.contains("have we") && lowercased.contains("recently"))
    }

    private let lastTimeBoilerplate = [
        "what was the last time i",
        "what was the last time we",
        "when did i last",
        "when did we last",
        "when was the last",
        "when was my last",
        "last time i",
        "last time we",
        "last time",
        "did i already",
        "did we already",
        "have i already",
        "have we already",
        "have i",
        "have we",
        "recently",
        "last"
    ]

    private let lastTimeFillerWords: Set<String> = [
        "about",
        "already",
        "before",
        "did",
        "ever",
        "for",
        "have",
        "i",
        "my",
        "of",
        "on",
        "our",
        "recently",
        "time",
        "to",
        "was",
        "we",
        "when"
    ]

    private let priorRecallPrefixes = [
        "what did i say about ",
        "what did i write about ",
        "what did i note about ",
        "what was my note about ",
        "what did i say ",
        "what did i write ",
        "what did i note ",
        "what was my note ",
        "what did i say",
        "what did i write",
        "what did i note",
        "what was my note",
        "did i mention ",
        "find ",
        "search for ",
        "show me notes about ",
        "show me entries about ",
        "show all ",
        "show ",
        "look up ",
        "what was that thing about ",
        "notes about ",
        "anything about ",
        "anything saved about ",
        "what do i know about ",
        "what do i have about "
    ]

}

private extension SearchService {
    func recallSearch(_ rawText: String, in records: [LocalSearchRecord], now: Date) -> [LocalSearchResult] {
        let query = LocalSearchQuery(rawText: rawText, limit: 50, now: now)
        if !query.normalizedText.isEmpty || query.dateRange != nil {
            return search(query, in: records)
        }
        return records.compactMap { result(for: $0, query: query) }
    }
}
