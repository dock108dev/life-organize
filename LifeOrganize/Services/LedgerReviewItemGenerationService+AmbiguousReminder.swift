import Foundation

extension LedgerReviewItemGenerationService {
    func ambiguousReminderDefinition(
        for message: ChatMessage,
        createdRecordEvidence: [LedgerReviewItemEvidence]
    ) -> ReviewItemDefinition? {
        guard let envelope = latestExtractionEnvelope(for: message),
              let window = ambiguousDateWindow(in: envelope, referenceDate: message.createdAt),
              let thingName = envelope.things.first?.name.nilIfEmpty else {
            return nil
        }

        let actionName = suggestedReminderAction(for: message.text, thingName: thingName)
        let detail = [
            "This sounds like a tentative \(reminderDescription(actionName: actionName, thingName: thingName)).",
            "The date phrase \"\(window.sourceText)\" means sometime from \(window.displayText), so no exact reminder date was saved."
        ].joined(separator: " ")
        let messageEvidence = LedgerReviewItemEvidence(
            sourceType: .chatMessage,
            sourceID: message.id,
            summary: message.text,
            detail: "Needs review"
        )
        let suggestionEvidence = LedgerReviewItemEvidence(
            sourceType: .chatMessage,
            sourceID: message.id,
            summary: "Suggested reminder: \(actionName)",
            detail: "Date window: \(window.displayText) from \"\(window.sourceText)\""
        )

        return ReviewItemDefinition(
            dedupeKey: [LedgerReviewItemKind.extractionReview.rawValue, message.id.uuidString, message.extractionStatus.rawValue]
                .joined(separator: "|"),
            kind: .extractionReview,
            title: "Review reminder for \(thingName)",
            detail: detail,
            actionTitle: "Choose Date",
            targetType: .chatMessage,
            targetID: message.id,
            confidence: 1,
            evidence: [messageEvidence, suggestionEvidence] + createdRecordEvidence
        )
    }

    private func ambiguousDateWindow(in envelope: ExtractionEnvelope, referenceDate: Date) -> AmbiguousDateWindow? {
        guard envelope.warnings.contains(where: { warning in
            warning.code.contains("ambiguous") || warning.code == "requires_review"
        }) else {
            return nil
        }
        guard let date = envelope.dates.first(where: { extractedDate in
            extractedDate.date == nil && extractedDate.role == "rule_starts_at"
        }) else {
            return nil
        }
        return dateWindow(for: date.sourceText, referenceDate: referenceDate)
    }

    private func dateWindow(for sourceText: String, referenceDate: Date) -> AmbiguousDateWindow? {
        let normalized = sourceText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let matchesWeekWindow = [
            "in a week or two",
            "in one or two weeks",
            "in 1 or 2 weeks",
            "in a couple weeks or so"
        ].contains(normalized)
        guard matchesWeekWindow,
              let start = calendar.date(byAdding: .day, value: 7, to: referenceDate),
              let end = calendar.date(byAdding: .day, value: 14, to: referenceDate) else {
            return nil
        }
        return AmbiguousDateWindow(
            sourceText: sourceText,
            displayText: dateWindowText(start: start, end: end)
        )
    }

    private func suggestedReminderAction(for text: String, thingName: String) -> String {
        if text.lowercased().contains("haircut") {
            return "Haircut for \(thingName)"
        }
        return "Reminder for \(thingName)"
    }

    private func reminderDescription(actionName: String, thingName: String) -> String {
        let suffix = " for \(thingName)"
        if actionName.hasSuffix(suffix) {
            return "\(String(actionName.dropLast(suffix.count)).lowercased()) reminder for \(thingName)"
        }
        return actionName.lowercased()
    }

    private func dateWindowText(start: Date, end: Date) -> String {
        let startComponents = calendar.dateComponents([.year], from: start)
        let endComponents = calendar.dateComponents([.year], from: end)
        if startComponents.year == endComponents.year {
            return "\(monthDayFormatter.string(from: start)) to \(monthDayYearFormatter.string(from: end))"
        }
        return "\(monthDayYearFormatter.string(from: start)) to \(monthDayYearFormatter.string(from: end))"
    }

    private var monthDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d"
        return formatter
    }

    private var monthDayYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }
}

private struct AmbiguousDateWindow {
    let sourceText: String
    let displayText: String
}
