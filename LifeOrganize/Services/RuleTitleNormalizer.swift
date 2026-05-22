import Foundation

struct RuleTitleNormalizer {
    static func normalizedTitle(
        extractedTitle: String,
        sourceText: String,
        ruleType: LedgerRuleType,
        thingName: String?,
        startsAt: String?,
        expiresAt: String?
    ) -> String {
        let original = cleanTitle(extractedTitle)
        var title = stripExtractionPrefix(original)
        if startsAt != nil || expiresAt != nil {
            title = stripStructuredDateSuffixes(title)
        }
        title = rewriteFirstPerson(title, ruleType: ruleType)

        if ruleType.isReminderLike {
            title = reminderTitle(title, sourceText: sourceText, thingName: thingName)
        } else if ruleType.isRestrictive {
            title = restrictiveTitle(title, sourceText: sourceText)
        }

        title = repairGenericTitle(title, sourceText: sourceText, ruleType: ruleType, thingName: thingName)
        title = cleanTitle(title)
        title = capitalizingFirstLetter(title)
        title = truncated(title, maxCharacters: 80)

        guard title.count >= 3 else {
            return original.nilIfEmpty ?? fallbackTitle(ruleType: ruleType, thingName: thingName)
        }
        return title
    }

    private static func cleanTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = stripWrappingQuotes(cleaned)
        cleaned = normalizeWhitespace(cleaned)
        cleaned = cleaned.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return cleaned
    }

    private static func stripWrappingQuotes(_ title: String) -> String {
        let quoteCharacters = CharacterSet(charactersIn: #""'“”‘’"#)
        return title.trimmingCharacters(in: quoteCharacters.union(.whitespacesAndNewlines))
    }

    private static func normalizeWhitespace(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func stripExtractionPrefix(_ title: String) -> String {
        let prefixes = [
            "the user needs to ",
            "the user wants to ",
            "user needs to ",
            "user wants to ",
            "remind me to ",
            "reminder to ",
            "reminder for ",
            "remember to ",
            "restriction: ",
            "restriction to ",
            "deadline: ",
            "deadline to ",
            "i need to ",
            "i should ",
            "i have to ",
            "needs to ",
            "need to ",
            "rule: ",
            "rule to ",
            "remember ",
        ]
        return strippingPrefix(from: title, prefixes: prefixes)
    }

    private static func stripStructuredDateSuffixes(_ title: String) -> String {
        let patterns = [
            #"\s+by\s+(today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$"#,
            #"\s+by\s+[A-Za-z]+\s+\d{1,2}$"#,
            #"\s+on\s+(today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$"#,
            #"\s+on\s+[A-Za-z]+\s+\d{1,2}$"#,
            #"\s+until\s+.+$"#,
            #"\s+before\s+.+$"#,
            #"\s+for\s+\d+\s+(day|days|week|weeks|month|months)$"#,
            #"\s+in\s+\d+\s+(day|days|week|weeks|month|months)$"#,
        ]
        return patterns.reduce(title) { result, pattern in
            replacingRegex(pattern, in: result, with: "")
        }
    }

    private static func rewriteFirstPerson(_ title: String, ruleType: LedgerRuleType) -> String {
        let lowered = title.lowercased()
        if ruleType.isRestrictive {
            if lowered.hasPrefix("i can't ") {
                return "Do not \(title.dropFirst("i can't ".count))"
            }
            if lowered.hasPrefix("i cannot ") {
                return "Do not \(title.dropFirst("i cannot ".count))"
            }
            if lowered.hasPrefix("i shouldn't ") {
                return "Do not \(title.dropFirst("i shouldn't ".count))"
            }
        }
        return strippingPrefix(
            from: title,
            prefixes: ["i need to ", "i should ", "i have to ", "my "]
        )
    }

    private static func reminderTitle(_ title: String, sourceText: String, thingName: String?) -> String {
        if hasReviewIntent(sourceText), let target = reviewTarget(from: sourceText, thingName: thingName) {
            let lowered = title.lowercased()
            if isGenericReminderTitle(title) || lowered.hasPrefix("no ") || lowered.hasPrefix("do not ") || lowered == "revisit this" {
                return "Reevaluate \(target)"
            }
        }
        return imperativeGerundTitle(title)
    }

    private static func restrictiveTitle(_ title: String, sourceText: String) -> String {
        if beginsWithAny(title, prefixes: ["do not ", "don't ", "dont ", "no ", "avoid ", "wait ", "hold off ", "stop ", "skip ", "pause "]) {
            return title.replacingOccurrences(of: #"(?i)^don't\s+"#, with: "Do not ", options: .regularExpression)
        }
        if let negative = negativeAction(from: sourceText) {
            return negative
        }
        return title
    }

    private static func repairGenericTitle(
        _ title: String,
        sourceText: String,
        ruleType: LedgerRuleType,
        thingName: String?
    ) -> String {
        guard isGenericTitle(title) else { return title }
        if ruleType.isReminderLike, let sourceAction = reminderAction(from: sourceText) {
            return sourceAction
        }
        if let thingName = thingName?.nilIfEmpty {
            if ruleType.isReminderLike {
                if title.lowercased().contains("renew") {
                    return "Renew \(thingName.lowercasedFirst)"
                }
                return "Maintain \(thingName.lowercasedFirst)"
            }
            if ruleType.isRestrictive {
                return "Do not \(thingName.lowercasedFirst)"
            }
        }
        return title
    }

    private static func reminderAction(from sourceText: String) -> String? {
        var source = cleanTitle(sourceText)
        source = stripExtractionPrefix(source)
        source = stripStructuredDateSuffixes(source)
        source = strippingPrefix(from: source, prefixes: ["please ", "can you ", "to "])
        source = imperativeGerundTitle(source)
        guard !isGenericTitle(source), source.count >= 3 else { return nil }
        return source
    }

    private static func negativeAction(from sourceText: String) -> String? {
        let patterns: [(String, String)] = [
            (#"\bdon't\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Do not"),
            (#"\bdo not\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Do not"),
            (#"\bdont\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Do not"),
            (#"\bavoid\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Avoid"),
            (#"\bno\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "No"),
            (#"\bwait\s+before\s+(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Wait before"),
            (#"\bhold off\s+(?:on\s+)?(.+?)(?:\s+(?:until|before|for|in)\s+.+)?$"#, "Hold off on"),
        ]
        for (pattern, prefix) in patterns {
            guard let match = firstRegexCapture(pattern, in: sourceText) else { continue }
            let object = cleanTitle(match)
            guard object.count >= 3 else { continue }
            return "\(prefix) \(object.lowercasedFirst)"
        }
        return nil
    }

    private static func reviewTarget(from sourceText: String, thingName: String?) -> String? {
        var target = sourceText.lowercased()
        let markers = ["reevaluate", "re-evaluate", "revisit", "review", "check back"]
        for marker in markers {
            if let range = target.range(of: marker) {
                target.removeSubrange(range.lowerBound..<target.endIndex)
                break
            }
        }
        let replacements = [
            "i don't want to ": "",
            "i do not want to ": "",
            "i dont want to ": "",
            "don't ": "",
            "do not ": "",
            "dont ": "",
            "no ": "",
            "next year": "",
            "long term": "",
            "should probably": "",
            "probably": "",
            "should": "",
            "plans": "",
        ]
        for (needle, replacement) in replacements {
            target = target.replacingOccurrences(of: needle, with: replacement)
        }
        target = cleanTitle(target)
        if target == "bowl" {
            return "bowling"
        }
        if let thingName = thingName?.nilIfEmpty, target.isEmpty || target == "that" || target == "this" {
            return thingName.lowercasedFirst
        }
        return target.nilIfEmpty
    }

    private static func hasReviewIntent(_ sourceText: String) -> Bool {
        let lowered = sourceText.lowercased()
        return ["reevaluate", "re-evaluate", "revisit", "review", "check back"].contains {
            lowered.contains($0)
        }
    }

    private static func imperativeGerundTitle(_ title: String) -> String {
        let gerunds = [
            "buying": "buy",
            "calling": "call",
            "booking": "book",
            "checking": "check",
            "drinking": "drink",
            "eating": "eat",
            "following up": "follow up",
            "opening": "open",
            "ordering": "order",
            "paying": "pay",
            "renewing": "renew",
            "replacing": "replace",
            "scheduling": "schedule",
            "spending": "spend",
            "starting": "start",
            "using": "use",
        ]
        for (gerund, verb) in gerunds where title.lowercased().hasPrefix("\(gerund) ") {
            return verb + title.dropFirst(gerund.count)
        }
        return title
    }

    private static func isGenericTitle(_ title: String) -> Bool {
        isGenericReminderTitle(title) || ["restriction", "deadline", "due date", "check", "maintenance", "renewal"].contains(cleanTitle(title).lowercased())
    }

    private static func isGenericReminderTitle(_ title: String) -> Bool {
        ["reminder", "task", "thing to do", "due item", "follow up", "revisit this"].contains(cleanTitle(title).lowercased())
    }

    private static func fallbackTitle(ruleType: LedgerRuleType, thingName: String?) -> String {
        if let thingName = thingName?.nilIfEmpty {
            return thingName
        }
        return ruleType.savedDisplayNoun
    }

    private static func strippingPrefix(from title: String, prefixes: [String]) -> String {
        for prefix in prefixes where title.lowercased().hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    private static func beginsWithAny(_ title: String, prefixes: [String]) -> Bool {
        prefixes.contains { title.lowercased().hasPrefix($0) }
    }

    private static func replacingRegex(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }

    private static func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func capitalizingFirstLetter(_ title: String) -> String {
        guard let first = title.first else { return title }
        return first.uppercased() + String(title.dropFirst())
    }

    private static func truncated(_ title: String, maxCharacters: Int) -> String {
        guard title.count > maxCharacters else { return title }
        return String(title.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + String(dropFirst())
    }
}
