import Foundation

struct RuleLookupService {
    var now: Date

    func answer(query: String, things: [Thing], rules: [LedgerRule]) -> String? {
        let targetKey = ruleTarget(from: query)
        let targetDisplay = displayTarget(from: targetKey)
        let targetKeys = LedgerTextMatching.expandedTargetKeys(for: targetKey, rawQuery: query)
        let targetTokens = LedgerTextMatching.tokens(in: targetKey)
        let thingMatches = scoredThingMatches(things, targetKeys: targetKeys, targetTokens: targetTokens)
        let matchingThingIDs = Set(thingMatches.map(\.thing.id))

        let matches = rules
            .compactMap { ruleMatch(for: $0, targetKeys: targetKeys, targetTokens: targetTokens, matchingThingIDs: matchingThingIDs) }
            .sorted(by: sortRuleMatches)

        let formatter = ChatResponseFormatter()
        if isReminderLookup(query) {
            let reminderMatches = matches
                .filter { $0.rule.ruleType.isReminderLike }
                .sorted(by: sortReminderMatches)

            if let reminderMatch = reminderMatches.first {
                return formatter.reminderLookup(reminderMatch.rule, status: reminderMatch.status, now: now)
            }

            if !matches.isEmpty || !targetKey.isEmpty {
                return formatter.noActiveRule(target: targetDisplay, expiredRule: nil, noun: "reminder")
            }

            return "No active reminders found."
        }

        let activeRules = matches
            .filter { $0.status == .active && $0.isBlocking }
            .map(\.rule)

        if !activeRules.isEmpty {
            return formatter.permissionBlocked(by: activeRules, now: now)
        }

        let expiredRule = matches
            .first { $0.status == .expired && $0.isBlocking }?
            .rule

        if !matches.isEmpty || !targetKey.isEmpty {
            return formatter.noActiveRule(target: targetDisplay, expiredRule: expiredRule, noun: "restriction")
        }

        if rules.contains(where: { RuleStatusService().status(for: $0, at: now) == .active }) {
            return formatter.noActiveRule(target: nil, expiredRule: nil, noun: "restriction")
        }

        return "No active restrictions found."
    }

    private func ruleMatch(
        for rule: LedgerRule,
        targetKeys: Set<String>,
        targetTokens: Set<String>,
        matchingThingIDs: Set<UUID>
    ) -> RuleMatch? {
        let linkedMatch = rule.thing.map { matchingThingIDs.contains($0.id) } == true
        let textScore = ruleTextScore(rule, targetKeys: targetKeys, targetTokens: targetTokens)
        guard linkedMatch || textScore > 0 else { return nil }

        let status = RuleStatusService().status(for: rule, at: now)
        let linkScore = linkedMatch ? 50 : 0
        let statusScore: Int
        switch status {
        case .active:
            statusScore = 100
        case .expired:
            statusScore = 20
        case .scheduled:
            statusScore = 10
        case .inactive:
            statusScore = 0
        }

        let isBlocking = isBlockingRule(rule)
        let polarityScore = isBlocking ? 30 : 10
        return RuleMatch(
            rule: rule,
            status: status,
            score: linkScore + textScore + statusScore + polarityScore,
            isLinked: linkedMatch,
            isBlocking: isBlocking
        )
    }

    private func sortRuleMatches(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
        if lhs.statusRank != rhs.statusRank { return lhs.statusRank > rhs.statusRank }
        if lhs.isBlocking != rhs.isBlocking { return lhs.isBlocking }
        if lhs.isLinked != rhs.isLinked { return lhs.isLinked }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.expirationRank != rhs.expirationRank { return lhs.expirationRank < rhs.expirationRank }
        return lhs.rule.createdAt > rhs.rule.createdAt
    }

    private func sortReminderMatches(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
        if lhs.reminderStatusRank != rhs.reminderStatusRank {
            return lhs.reminderStatusRank > rhs.reminderStatusRank
        }
        if lhs.isLinked != rhs.isLinked { return lhs.isLinked }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.rule.startsAt != rhs.rule.startsAt { return lhs.rule.startsAt < rhs.rule.startsAt }
        return lhs.rule.createdAt > rhs.rule.createdAt
    }

    private func ruleTextScore(_ rule: LedgerRule, targetKeys: Set<String>, targetTokens: Set<String>) -> Int {
        let titleKey = ThingNormalizer.normalizeKey(rule.title)
        let rawTextKey = ThingNormalizer.normalizeKey(rule.rawText)

        if LedgerTextMatching.textMatches(titleKey, targetKeys: targetKeys, targetTokens: targetTokens) {
            return 40
        }
        if LedgerTextMatching.textMatches(rawTextKey, targetKeys: targetKeys, targetTokens: targetTokens) {
            return 30
        }
        if let reason = rule.reason,
           LedgerTextMatching.textMatches(ThingNormalizer.normalizeKey(reason), targetKeys: targetKeys, targetTokens: targetTokens) {
            return 20
        }
        return 0
    }

    private func scoredThingMatches(
        _ things: [Thing],
        targetKeys: Set<String>,
        targetTokens: Set<String>
    ) -> [ThingMatch] {
        things.compactMap { thing in
            let score = thingMatchScore(thing, targetKeys: targetKeys, targetTokens: targetTokens)
            return score >= 63 ? ThingMatch(thing: thing, score: score) : nil
        }
        .sorted { $0.score > $1.score }
    }

    private func thingMatchScore(_ thing: Thing, targetKeys: Set<String>, targetTokens: Set<String>) -> Int {
        let nameKey = ThingNormalizer.normalizeKey(thing.name)
        let aliasKeys = thing.aliases.map(ThingNormalizer.normalizeKey)
        if targetKeys.contains(nameKey) { return 100 }
        if aliasKeys.contains(where: targetKeys.contains) { return 95 }
        if targetKeys.contains(where: { key in
            LedgerTextMatching.containsWholePhrase(nameKey, key)
                || LedgerTextMatching.containsWholePhrase(key, nameKey)
        }) {
            return 70
        }
        if aliasKeys.contains(where: { alias in
            targetKeys.contains { key in
                LedgerTextMatching.containsWholePhrase(alias, key)
                    || LedgerTextMatching.containsWholePhrase(key, alias)
            }
        }) {
            return 68
        }
        if LedgerTextMatching.thingMatches(thing, targetKeys: targetKeys, targetTokens: targetTokens) {
            return 63
        }
        return 0
    }

    private func ruleTarget(from query: String) -> String {
        var target = LedgerTextMatching.normalizedAlphanumericText(query)
        for phrase in ruleLookupBoilerplate {
            target = target.replacingOccurrences(of: phrase, with: " ")
        }
        return ThingNormalizer.normalizeKey(target)
    }

    private func displayTarget(from targetKey: String) -> String? {
        let display = targetKey
            .split(separator: " ")
            .filter { !ruleTargetFillerWords.contains(String($0)) }
            .joined(separator: " ")
        return display.nilIfEmpty
    }

    private func isBlockingRule(_ rule: LedgerRule) -> Bool {
        guard rule.ruleType.isRestrictive else { return false }
        let text = LedgerTextMatching.normalizedAlphanumericText("\(rule.title) \(rule.rawText)")
        return blockingRuleMarkers.contains { marker in
            text == marker || text.hasPrefix("\(marker) ") || text.contains(" \(marker) ")
        }
    }

    private func isReminderLookup(_ query: String) -> Bool {
        let text = query.lowercased()
        return text.contains("reminder")
            || text.contains("remember")
            || text.contains("due")
    }

    private let ruleLookupBoilerplate = [
        "what did i decide about",
        "when is my reminder for",
        "when am i allowed to",
        "do i have any reminder about",
        "do i have a reminder about",
        "do i have any rule about",
        "do i have a rule about",
        "is there a reminder about",
        "is there a rule about",
        "am i allowed to",
        "did i say not to",
        "did i say no more",
        "did i say no",
        "should i still not",
        "am i still not",
        "is it okay to",
        "is it ok to",
        "when can i",
        "can i",
        "can we",
        "may i",
        "allowed to",
    ]

    private let ruleTargetFillerWords: Set<String> = [
        "buy",
        "get",
        "order",
        "purchase",
        "replace",
        "start",
        "upgrade",
    ]

    private let blockingRuleMarkers = [
        "no",
        "do not",
        "don t",
        "dont",
        "avoid",
        "stop",
        "pause",
        "hold off",
        "wait on",
        "wait until",
        "not buying",
        "not ordering",
        "ban",
    ]
}

private struct RuleMatch {
    var rule: LedgerRule
    var status: RuleStatus
    var score: Int
    var isLinked: Bool
    var isBlocking: Bool

    var statusRank: Int {
        switch status {
        case .active:
            return 3
        case .expired:
            return 2
        case .scheduled:
            return 1
        case .inactive:
            return 0
        }
    }

    var expirationRank: Date {
        if status == .active {
            return rule.expiresAt ?? .distantFuture
        }
        return rule.expiresAt.map { Date(timeIntervalSinceReferenceDate: -$0.timeIntervalSinceReferenceDate) } ?? .distantFuture
    }

    var reminderStatusRank: Int {
        switch status {
        case .active:
            return 4
        case .scheduled:
            return 3
        case .expired:
            return 2
        case .inactive:
            return 1
        }
    }
}

private struct ThingMatch {
    var thing: Thing
    var score: Int
}
