import Foundation
import SwiftData

@MainActor
struct ChatRecallResponseService {
    let modelContext: ModelContext
    var now: Date

    func answer(for classification: ChatIntentClassification) throws -> String {
        switch classification.intent {
        case .lookupLastTime:
            let result = try lastTimeAnswer(for: classification)
            return result == noMatch ? "No matching logged event found." : result
        case .lookupRule:
            let result = try recallAnswer(for: classification)
            return result == noMatch ? "No active reminders found." : result
        case .lookupTodayAgenda:
            return try todayAgendaAnswer()
        case .lookupPriorNotes:
            return try priorNoteAnswer(for: classification)
        case .localSearch:
            return try localSearchAnswer(for: classification.targetText)
        case .webLookup, .webImport:
            return ChatResponseFormatter().unsupportedBoundary()
        case .unsupported:
            return ChatResponseFormatter().unsupportedBoundary()
        case .createEvent, .createRule, .createNote:
            return ""
        }
    }

    private func recallAnswer(for classification: ChatIntentClassification) throws -> String {
        RecallService(now: now).answer(
            query: queryText(for: classification),
            things: try modelContext.fetch(FetchDescriptor<Thing>()),
            events: try modelContext.fetch(FetchDescriptor<LedgerEvent>()),
            rules: try modelContext.fetch(FetchDescriptor<LedgerRule>()),
            notes: try modelContext.fetch(FetchDescriptor<LedgerNote>()),
            chatMessages: try modelContext.fetch(FetchDescriptor<ChatMessage>())
        ).answer
    }

    private func lastTimeAnswer(for classification: ChatIntentClassification) throws -> String {
        RecallService(now: now).answer(
            query: "last \(queryText(for: classification))",
            things: try modelContext.fetch(FetchDescriptor<Thing>()),
            events: try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        ).answer
    }

    private func priorNoteAnswer(for classification: ChatIntentClassification) throws -> String {
        let topic = queryText(for: classification)
        let query = SearchService.normalizeForLocalSearch(topic).isEmpty
            ? "what did i say"
            : "what did i say about \(topic)"

        return RecallService(now: now).answer(
            query: query,
            things: try modelContext.fetch(FetchDescriptor<Thing>()),
            events: try modelContext.fetch(FetchDescriptor<LedgerEvent>()),
            rules: try modelContext.fetch(FetchDescriptor<LedgerRule>()),
            notes: try modelContext.fetch(FetchDescriptor<LedgerNote>()),
            chatMessages: try modelContext.fetch(FetchDescriptor<ChatMessage>())
        ).answer
    }

    private func localSearchAnswer(for query: String) throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return noMatch }

        let search = SearchService()
        let records = search.records(
            things: try modelContext.fetch(FetchDescriptor<Thing>()),
            events: try modelContext.fetch(FetchDescriptor<LedgerEvent>()),
            rules: try modelContext.fetch(FetchDescriptor<LedgerRule>()),
            notes: try modelContext.fetch(FetchDescriptor<LedgerNote>()),
            messages: try modelContext.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .user }
        )
        let results = search.search(LocalSearchQuery(rawText: trimmed, limit: 10, now: now), in: records)
        guard !results.isEmpty else {
            return #"No saved records found for "\#(trimmed)"."#
        }

        return (["Local results:"] + results.map(resultLine))
            .joined(separator: "\n")
    }

    private func todayAgendaAnswer() throws -> String {
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        let statusService = RuleStatusService()
        let presentationService = ReminderContinuityPresentationService(statusService: statusService)
        let activeReminders = rules
            .filter { $0.ruleType.isReminderLike && statusService.status(for: $0, at: now) == .active }
            .sorted { lhs, rhs in
                if lhs.startsAt != rhs.startsAt {
                    return lhs.startsAt < rhs.startsAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        guard !activeReminders.isEmpty else {
            return "Nothing due today."
        }

        let lines = activeReminders.prefix(5).map { rule in
            let presentation = presentationService.presentation(for: rule, at: now)
            return "- \(rule.title). \(presentation.primaryLine)."
        }
        return (["Today:"] + lines).joined(separator: "\n")
    }

    private func queryText(for classification: ChatIntentClassification) -> String {
        classification.targetText.isEmpty ? classification.targetText : classification.targetText
    }

    private func resultLine(_ result: LocalSearchResult) -> String {
        var line = "- \(ChatResponseFormatter.date(result.date)) - \(resultDisplayText(result))"
        if let productContext = result.productContextText {
            line += " - \(productContext)"
        }
        return line
    }

    private func resultDisplayText(_ result: LocalSearchResult) -> String {
        switch result.sourceKind {
        case .chatMessage, .note:
            result.body ?? result.title
        case .rule, .event, .thing, .timelineSlice:
            result.title
        }
    }

    private let noMatch = "No saved records found."
}
