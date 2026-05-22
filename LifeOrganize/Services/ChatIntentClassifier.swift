import Foundation

enum ChatLedgerIntent: String, CaseIterable {
    case createEvent
    case createRule
    case createNote
    case lookupLastTime
    case lookupRule
    case lookupTodayAgenda
    case lookupPriorNotes
    case localSearch
    case webLookup
    case webImport
    case unsupported

    var needsExtraction: Bool {
        switch self {
        case .createEvent, .createRule, .createNote:
            true
        case .lookupLastTime, .lookupRule, .lookupTodayAgenda, .lookupPriorNotes, .localSearch, .webLookup, .webImport,
             .unsupported:
            false
        }
    }
}

struct ChatIntentClassification: Equatable {
    var intent: ChatLedgerIntent
    var targetText: String
}

struct ChatIntentClassifier {
    func classify(_ input: String) -> ChatIntentClassification {
        let normalized = NormalizedChatInput(input)
        guard !normalized.trimmed.isEmpty else {
            return ChatIntentClassification(intent: .unsupported, targetText: "")
        }

        if isTemporalDiffQuestion(normalized) {
            return .init(intent: .unsupported, targetText: normalized.trimmed)
        }
        if normalized.hasQuestionShape, let loggingIntent = loggingIntent(for: normalized) {
            return .init(intent: loggingIntent, targetText: normalized.trimmed)
        }
        if isLocalSearch(normalized) {
            return .init(intent: .localSearch, targetText: target(from: normalized, removing: localSearchPrefixes))
        }
        if isPriorNoteLookup(normalized) {
            return .init(intent: .lookupPriorNotes, targetText: target(from: normalized, removing: priorNotePrefixes))
        }
        if isTodayAgendaLookup(normalized) {
            return .init(intent: .lookupTodayAgenda, targetText: "today")
        }
        if isRuleLookup(normalized) {
            return .init(intent: .lookupRule, targetText: target(from: normalized, removing: ruleLookupPrefixes))
        }
        if isLastTimeLookup(normalized) {
            return .init(intent: .lookupLastTime, targetText: target(from: normalized, removing: lastTimePrefixes))
        }
        if isWebImportRequest(normalized) {
            return .init(intent: .webImport, targetText: normalized.trimmed)
        }
        if isWebLookup(normalized) {
            return .init(intent: .webLookup, targetText: normalized.trimmed)
        }

        let hasQuestionShape = normalized.hasQuestionShape
        if isUnsupportedQuestion(normalized) {
            return .init(intent: .unsupported, targetText: normalized.trimmed)
        }
        if isFutureReminderRequest(normalized) {
            return .init(intent: .createRule, targetText: normalized.trimmed)
        }
        if !hasQuestionShape, startsWithAny(normalized.lowercase, ruleMarkers) {
            return .init(intent: .createRule, targetText: normalized.trimmed)
        }
        if !hasQuestionShape, containsAny(normalized.lowercase, eventMarkers) {
            return .init(intent: .createEvent, targetText: normalized.trimmed)
        }
        if !hasQuestionShape, looksLikeNote(normalized) {
            return .init(intent: .createNote, targetText: normalized.trimmed)
        }
        return .init(intent: .unsupported, targetText: normalized.trimmed)
    }

    private func loggingIntent(for input: NormalizedChatInput) -> ChatLedgerIntent? {
        if startsWithAny(input.lowercase, ruleMarkers) {
            return .createRule
        }
        if containsAny(input.lowercase, eventMarkers) {
            return .createEvent
        }
        if startsWithAny(input.lowercase, notePrefixes) {
            return .createNote
        }
        return nil
    }

    private func isLastTimeLookup(_ input: NormalizedChatInput) -> Bool {
        containsAny(
            input.lowercase,
            [
                "when did i last",
                "when did we last",
                "when was the last",
                "when was my last",
                "last time",
                "did i already",
                "did we already",
                "have i already",
                "have we already",
            ]
        )
            || input.lowercase.hasPrefix("last ")
            || (input.lowercase.hasPrefix("have i ") && input.lowercase.contains("recently"))
            || (input.lowercase.hasPrefix("have we ") && input.lowercase.contains("recently"))
    }

    private func isRuleLookup(_ input: NormalizedChatInput) -> Bool {
        input.lowercase.hasPrefix("can i ")
            || input.lowercase.hasPrefix("can we ")
            || input.lowercase.hasPrefix("may i ")
            || input.lowercase.hasPrefix("am i allowed")
            || input.lowercase.hasPrefix("is it okay")
            || input.lowercase.hasPrefix("is it ok")
            || input.lowercase.hasPrefix("when can i ")
            || input.lowercase.hasPrefix("when am i allowed")
            || containsAny(input.lowercase, [
                "allowed to",
                "any reminder",
                "any rule",
                "active reminder",
                "active rule",
                "did i say no",
                "did i say not to",
                "did i ban",
                "did i restrict",
                "did i pause",
                "do i have a reminder",
                "do i have any reminder",
                "do i have a rule",
                "do i have any rule",
                "is there a reminder",
                "is there a rule",
                "should i still not",
                "am i still not",
                "what did i decide about",
            ])
    }

    private func isTodayAgendaLookup(_ input: NormalizedChatInput) -> Bool {
        input.hasQuestionShape
            && containsAny(input.lowercase, [
                "what do i have to do today",
                "what should i do today",
                "what is due today",
                "what's due today",
                "anything due today",
                "what do i need to do today",
            ])
    }

    private func isPriorNoteLookup(_ input: NormalizedChatInput) -> Bool {
        containsAny(
            input.lowercase,
            [
                "what did i say",
                "what did i write",
                "what did i note",
                "what was my note",
                "did i mention",
                "notes about",
                "show me notes about",
                "show me entries about",
                "anything about",
                "anything saved about",
                "what do i know about",
            ]
        )
    }

    private func isLocalSearch(_ input: NormalizedChatInput) -> Bool {
        startsWithAny(input.lowercase, ["search for ", "find ", "show all ", "look up "])
    }

    private func isWebImportRequest(_ input: NormalizedChatInput) -> Bool {
        startsWithAny(input.lowercase, ["add all ", "save all ", "import all "])
            && containsAny(input.lowercase, webScheduleMarkers)
    }

    private func isWebLookup(_ input: NormalizedChatInput) -> Bool {
        containsAny(input.lowercase, [
            "best games",
            "games to watch",
            "kickoff",
            "kick off",
            "college football games",
            "football schedule",
            "home games",
            "schedule for",
        ])
    }

    private func isUnsupportedQuestion(_ input: NormalizedChatInput) -> Bool {
        guard input.hasQuestionShape else { return false }
        return containsAny(input.lowercase, ["should i", "what should i", "how do i", "write me", "best ", "recommend"])
    }

    private func isTemporalDiffQuestion(_ input: NormalizedChatInput) -> Bool {
        input.hasQuestionShape && input.lowercase.hasPrefix("what changed")
    }

    private func isFutureReminderRequest(_ input: NormalizedChatInput) -> Bool {
        containsAny(input.lowercase, reminderRequestMarkers) && hasFutureTimeReference(input.lowercase)
    }

    private func hasFutureTimeReference(_ text: String) -> Bool {
        containsAny(text, futureTimeMarkers)
            || matches(text, #"\b(?:in|after)\s+\d{1,4}\s+(?:minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)\b"#)
            || matches(text, #"\b\d{1,4}\s+(?:minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)\s+from\s+now\b"#)
            || matches(text, #"\b(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+\d{1,2}\b"#)
            || matches(text, #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#)
            || matches(text, #"\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#)
    }

    private func looksLikeNote(_ input: NormalizedChatInput) -> Bool {
        startsWithAny(input.lowercase, notePrefixes)
            || containsAny(input.lowercase, [" is in ", " is at ", " should be ", " needs to be ", " every ", " code is ", " number is "])
            || input.tokens.count >= 3
    }

    private func target(from input: NormalizedChatInput, removing prefixes: [String]) -> String {
        var target = input.lowercase
        for prefix in prefixes where target.hasPrefix(prefix) {
            target.removeFirst(prefix.count)
            break
        }
        return target.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private func startsWithAny(_ text: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { text.hasPrefix($0) }
    }

    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private let localSearchPrefixes = ["search for ", "find ", "show all ", "look up "]
    private let priorNotePrefixes = [
        "what did i say about ", "what did i write about ", "what did i note about ",
        "what was my note about ", "what did i say ", "what did i write ",
        "what did i note ", "what was my note ", "what did i say",
        "what did i write", "what did i note", "what was my note",
        "did i mention ", "show me notes about ",
        "show me entries about ", "notes about ", "anything about ",
        "anything saved about ", "what do i know about ",
    ]
    private let ruleLookupPrefixes = [
        "can i ",
        "can we ",
        "may i ",
        "am i allowed to ",
        "am i allowed ",
        "is it okay to ",
        "is it ok to ",
        "when can i ",
        "when am i allowed to ",
        "any reminder about ",
        "any rule about ",
        "active reminder about ",
        "active rule about ",
        "do i have a reminder about ",
        "do i have any reminder about ",
        "do i have a rule about ",
        "do i have any rule about ",
        "is there a reminder about ",
        "is there a rule about ",
        "what did i decide about ",
    ]
    private let lastTimePrefixes = [
        "when did i last ",
        "when did we last ",
        "when was the last ",
        "when was my last ",
        "last time i ",
        "last time we ",
        "last time ",
        "last ",
        "did i already ",
        "did we already ",
        "have i already ",
        "have we already ",
        "have i ",
        "have we ",
    ]
    private let reminderRequestMarkers = [
        "reevaluate",
        "re-evaluate",
        "revisit",
        "review later",
        "check again",
        "check back",
        "follow up",
        "remind me",
    ]
    private let futureTimeMarkers = [
        " tomorrow",
        " tonight",
        " next ",
        " later",
        " soon",
        " by ",
        " due ",
        " on monday",
        " on tuesday",
        " on wednesday",
        " on thursday",
        " on friday",
        " on saturday",
        " on sunday",
        " this week",
        " this weekend",
        " this month",
        " this year",
    ]
    private let ruleMarkers = ["no ", "don't ", "do not ", "avoid ", "stop ", "pause ", "hold off ", "wait until ", "not buying ", "not ordering ", "not starting ", "ban "]
    private let eventMarkers = ["changed", "replaced", "cleaned", "paid", "called", "emailed", "submitted", "filed", "renewed", "bought", "ordered", "went", "visited", "started", "finished", "fixed", "installed", "checked", "scheduled", "cancelled"]
    private let notePrefixes = ["remember ", "note ", "for later "]
    private let webScheduleMarkers = [
        "schedule",
        "home games",
        "games",
        "kickoff",
        "kick off",
        "college football",
        "football",
    ]
}

private struct NormalizedChatInput {
    var trimmed: String
    var lowercase: String
    var tokens: [String]
    var hasQuestionShape: Bool

    init(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedInput = trimmedInput.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let stripped = lowercasedInput.map { $0.isPunctuation ? " " : String($0) }.joined()
        trimmed = trimmedInput
        lowercase = lowercasedInput
        tokens = stripped.split(whereSeparator: \.isWhitespace).map(String.init)
        hasQuestionShape = trimmedInput.contains("?") || Self.questionStarters.contains { lowercasedInput.hasPrefix($0) }
    }

    private static let questionStarters = [
        "when ", "what ", "where ", "which ", "who ", "how ", "can i ", "am i ",
        "did i ", "do i ", "have i ", "was i ", "is there ", "are there ", "any ",
    ]
}
