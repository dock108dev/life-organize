import Foundation

struct LedgerReviewReconciliationPresentationBuilder {
    func presentation(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationPresentation {
        let source = sourcePanel(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes)
        let suggestion = suggestionPanel(for: item, entry: entry, things: things, events: events, rules: rules, notes: notes)
        let noteBody = saveAsNoteBody(for: item, entry: entry, source: source, suggestion: suggestion)
        return LedgerReviewReconciliationPresentation(
            itemID: item.id,
            title: item.title,
            source: source,
            suggestion: suggestion,
            evidence: nil,
            actions: actions(
                for: item,
                entry: entry,
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                messages: messages,
                canSaveAsNote: noteBody != nil
            ),
            saveAsNoteBody: noteBody
        )
    }

    private func sourcePanel(
        for item: LedgerReviewItem,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationPanel {
        if item.kind == .duplicateThing {
            let rows = item.evidence
                .filter { $0.sourceType == .thing }
                .map { evidenceRow($0, things: things, events: events, rules: rules, notes: notes, messages: messages) }
            return panel(title: "Saved Items", summary: nil, rows: rows, fallback: item.detail)
        }

        if item.targetType == .chatMessage,
           let targetRow = targetRow(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes) {
            return LedgerReviewReconciliationPanel(title: "Original Entry", summary: nil, rows: [targetRow])
        }

        var rows = [LedgerReviewReconciliationRow]()
        if let targetRow = targetRow(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes) {
            rows.append(targetRow)
        }
        rows += item.evidence.map {
            evidenceRow($0, things: things, events: events, rules: rules, notes: notes, messages: messages)
        }
        rows = rows.reduce(into: [LedgerReviewReconciliationRow]()) { uniqueRows, row in
            guard !uniqueRows.contains(where: { $0.targetType == row.targetType && $0.targetID == row.targetID }) else { return }
            uniqueRows.append(row)
        }
        return panel(title: sourceTitle(for: item.targetType), summary: nil, rows: rows, fallback: item.detail)
    }

    private func suggestionPanel(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationPanel {
        let createdRows = entry.createdRecords.map { createdRecordRow($0, things: things, events: events, rules: rules, notes: notes) }
        if createdRows.isEmpty {
            return LedgerReviewReconciliationPanel(
                title: "Next Step",
                summary: confirmationSummary(for: item, entry: entry),
                rows: []
            )
        }
        return LedgerReviewReconciliationPanel(title: "Saved Items", summary: nil, rows: createdRows)
    }

    private func actions(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage],
        canSaveAsNote: Bool
    ) -> LedgerReviewReconciliationActions {
        let primary = primaryAction(for: item, entry: entry, rules: rules)
        var contextual = editActions(for: item, entry: entry, things: things, events: events, rules: rules, notes: notes, messages: messages)
        if canSaveAsNote {
            contextual.append(action(.saveAsNote, "Keep as Note", role: .note, detail: "Save the entry as a note, then close this review."))
        }
        let canMarkReviewed = primary?.kind != .confirm && primary?.kind != .blocked
        let reviewState = canMarkReviewed ? [action(.confirm, "Done", role: .reviewState)] : []
        return LedgerReviewReconciliationActions(
            primary: primary,
            contextual: contextual,
            reviewState: reviewState + [action(.snooze, "Snooze", role: .reviewState)],
            destructive: [action(.dismiss, "Dismiss", role: .destructive)]
        )
    }

    private func primaryAction(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        rules: [LedgerRule]
    ) -> LedgerReviewReconciliationAction? {
        if let blockedMessage = entry.blockedMessage {
            return action(.blocked, "Needs Attention", role: .blocked, detail: blockedActionDetail(for: item, fallback: blockedMessage), isEnabled: false)
        }

        if entry.primaryActionTitle == "Retry Now" || entry.primaryActionTitle == "Try Again" {
            return action(.retry, "Try Again", role: .primary)
        }
        if item.kind == .intervalReminder {
            return action(.buildReminderDraft, entry.primaryActionTitle, role: .primary)
        }
        if item.kind == .overdueReminderReview {
            let hasRule = targetRule(for: item, rules: rules) != nil
            return action(
                hasRule ? .adjustReminderTiming : .blocked,
                hasRule ? "Adjust Timing" : "Needs Attention",
                role: hasRule ? .primary : .blocked,
                detail: hasRule ? nil : "This reminder is not available. Dismiss this review if you no longer need it, or restore the reminder first.",
                isEnabled: hasRule
            )
        }
        return action(.confirm, "Done", role: .primary)
    }

    private func editActions(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) -> [LedgerReviewReconciliationAction] {
        if !entry.createdRecords.isEmpty {
            return entry.createdRecords.map {
                action(.openRecord($0.targetType, $0.targetID), "Edit \($0.subtitle)", role: .edit, detail: $0.title)
            }
        }

        if item.kind == .duplicateThing {
            return candidateThings(for: item, things: things).map {
                action(.mergeThing($0.id), "Merge into \($0.name)", role: .contextual, detail: "Move linked items, then close the review.")
            }
        }

        return openTargetAction(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes).map { [$0] } ?? []
    }

    private func openTargetAction(
        for item: LedgerReviewItem,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationAction? {
        guard let targetID = item.targetID,
              targetExists(item.targetType, id: targetID, messages: messages, things: things, events: events, rules: rules, notes: notes) else {
            return nil
        }
        return action(.openRecord(item.targetType, targetID), editActionTitle(for: item.targetType), role: .edit)
    }

    private func saveAsNoteBody(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        source: LedgerReviewReconciliationPanel,
        suggestion: LedgerReviewReconciliationPanel
    ) -> String? {
        guard entry.createdRecords.isEmpty else { return nil }
        switch item.kind {
        case .localRecovery, .extractionReview, .conflictingDate:
            let sourceText = source.rows.map(\.title).joined(separator: "\n")
            let suggestionText = [suggestion.summary, item.title].compactMap { $0?.nilIfEmpty }.joined(separator: "\n")
            let body = [
                source.title + ":",
                sourceText,
                "",
                "Next Step:",
                suggestionText
            ].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return body.nilIfEmpty
        case .duplicateThing, .normalizationCandidate, .intervalReminder, .overdueReminderReview:
            return nil
        }
    }

    private func panel(
        title: String,
        summary: String?,
        rows: [LedgerReviewReconciliationRow],
        fallback: String
    ) -> LedgerReviewReconciliationPanel {
        if rows.isEmpty {
            return LedgerReviewReconciliationPanel(
                title: title,
                summary: summary,
                rows: [LedgerReviewReconciliationRow(id: "fallback", title: fallback)]
            )
        }
        return LedgerReviewReconciliationPanel(title: title, summary: summary, rows: rows)
    }

    private func targetRow(
        for item: LedgerReviewItem,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationRow? {
        guard let targetID = item.targetID else { return nil }
        return resolvedRow(item.targetType, id: targetID, messages: messages, things: things, events: events, rules: rules, notes: notes)
            ?? LedgerReviewReconciliationRow(
                id: "missing-\(item.targetType.rawValue)-\(targetID.uuidString)",
                title: "\(sourceNoun(for: item.targetType)) no longer exists",
                detail: item.evidence.first?.summary ?? item.detail,
                targetType: item.targetType,
                targetID: targetID,
                isMissing: true
            )
    }

    private func evidenceRow(
        _ evidence: LedgerReviewItemEvidence,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) -> LedgerReviewReconciliationRow {
        resolvedRow(evidence.sourceType, id: evidence.sourceID, messages: messages, things: things, events: events, rules: rules, notes: notes)
            .map {
                LedgerReviewReconciliationRow(
                    id: "evidence-\($0.id)",
                    title: $0.title,
                    detail: productFacingDetail(evidence.detail ?? $0.detail, fallbackType: evidence.sourceType),
                    targetType: evidence.sourceType,
                    targetID: evidence.sourceID,
                    isMissing: false
                )
            }
            ?? LedgerReviewReconciliationRow(
                id: "evidence-missing-\(evidence.sourceType.rawValue)-\(evidence.sourceID.uuidString)",
                title: evidence.summary,
                detail: productFacingDetail(
                    evidence.detail,
                    fallbackType: evidence.sourceType
                ) ?? "\(sourceNoun(for: evidence.sourceType)) is no longer available.",
                targetType: evidence.sourceType,
                targetID: evidence.sourceID,
                isMissing: true
            )
    }

    private func createdRecordRow(
        _ record: LedgerReviewCreatedRecord,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationRow {
        let exists = targetExists(record.targetType, id: record.targetID, messages: [], things: things, events: events, rules: rules, notes: notes)
        return LedgerReviewReconciliationRow(
            id: "created-\(record.id)",
            title: record.title,
            detail: exists ? record.subtitle : "\(record.subtitle) no longer exists.",
            targetType: record.targetType,
            targetID: record.targetID,
            isMissing: !exists
        )
    }

    private func resolvedRow(
        _ type: LedgerReviewItemTargetType,
        id: UUID,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> LedgerReviewReconciliationRow? {
        switch type {
        case .chatMessage:
            return messages.first { $0.id == id }.map {
                LedgerReviewReconciliationRow(
                    id: "message-\(id.uuidString)",
                    title: $0.text,
                    detail: messageDetail(for: $0),
                    targetType: type,
                    targetID: id
                )
            }
        case .thing:
            return things.first { $0.id == id }.map {
                LedgerReviewReconciliationRow(id: "thing-\(id.uuidString)", title: $0.name, detail: $0.details.nilIfEmpty, targetType: type, targetID: id)
            }
        case .event:
            return events.first { $0.id == id }.map {
                LedgerReviewReconciliationRow(id: "event-\(id.uuidString)", title: $0.title, detail: $0.rawText.nilIfEmpty, targetType: type, targetID: id)
            }
        case .rule:
            return rules.first { $0.id == id }.map {
                LedgerReviewReconciliationRow(id: "rule-\(id.uuidString)", title: $0.title, detail: $0.rawText.nilIfEmpty, targetType: type, targetID: id)
            }
        case .none:
            return notes.first { $0.id == id }.map {
                LedgerReviewReconciliationRow(id: "note-\(id.uuidString)", title: $0.text, detail: nil, targetType: type, targetID: id)
            }
        }
    }

    private func targetExists(
        _ type: LedgerReviewItemTargetType,
        id: UUID,
        messages: [ChatMessage],
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote]
    ) -> Bool {
        resolvedRow(type, id: id, messages: messages, things: things, events: events, rules: rules, notes: notes) != nil
    }

    private func candidateThings(for item: LedgerReviewItem, things: [Thing]) -> [Thing] {
        item.evidence
            .filter { $0.sourceType == .thing }
            .compactMap { evidence in things.first { $0.id == evidence.sourceID } }
    }

    private func targetRule(for item: LedgerReviewItem, rules: [LedgerRule]) -> LedgerRule? {
        if item.targetType == .rule, let targetID = item.targetID {
            return rules.first { $0.id == targetID }
        }
        guard let ruleEvidence = item.evidence.first(where: { $0.sourceType == .rule }) else { return nil }
        return rules.first { $0.id == ruleEvidence.sourceID }
    }

    private func action(
        _ kind: LedgerReviewReconciliationActionKind,
        _ title: String,
        role: LedgerReviewReconciliationActionRole,
        detail: String? = nil,
        isEnabled: Bool = true
    ) -> LedgerReviewReconciliationAction {
        LedgerReviewReconciliationAction(kind: kind, title: title, detail: detail, role: role, isEnabled: isEnabled)
    }

    private func sourceTitle(for type: LedgerReviewItemTargetType) -> String {
        switch type {
        case .chatMessage:
            return "Original Entry"
        case .event, .thing, .rule, .none:
            return "Saved Items"
        }
    }

    private func editActionTitle(for type: LedgerReviewItemTargetType) -> String {
        switch type {
        case .chatMessage:
            return "Open Entry"
        case .event:
            return "Edit Event"
        case .thing:
            return "Edit Thing"
        case .rule:
            return "Edit Reminder"
        case .none:
            return "Edit Note"
        }
    }

    private func sourceNoun(for type: LedgerReviewItemTargetType) -> String {
        switch type {
        case .chatMessage:
            return "Entry"
        case .event:
            return "Event"
        case .thing:
            return "Thing"
        case .rule:
            return "Reminder"
        case .none:
            return "Note"
        }
    }

    private func confirmationSummary(for item: LedgerReviewItem, entry: LedgerReviewQueueEntry) -> String {
        if entry.blockedMessage != nil {
            return blockedActionDetail(for: item, fallback: entry.blockedMessage)
        }
        switch item.kind {
        case .localRecovery:
            return "Try again, or keep this entry as a note."
        case .extractionReview:
            return entry.createdRecords.isEmpty
                ? "Try again, keep this as a note, or mark it done."
                : "Check the saved items, edit anything that needs attention, then mark it done."
        case .conflictingDate:
            return "Check the date, edit the event if needed, then mark it done."
        case .duplicateThing:
            return "Choose the item to keep, or dismiss this if both should stay."
        case .normalizationCandidate:
            return "Edit the name if needed, then mark it done."
        case .intervalReminder:
            return "Review the reminder setup, then mark it done when the timing looks right."
        case .overdueReminderReview:
            return "Update the reminder date or status, then mark it done."
        }
    }

    private func blockedActionDetail(for item: LedgerReviewItem, fallback: String?) -> String {
        if item.kind == .overdueReminderReview {
            return "Update or restore the reminder before closing this review."
        }
        if fallback?.localizedCaseInsensitiveContains("service") == true {
            return fallback ?? "Reconnect the service before continuing."
        }
        return "Check the saved items before closing this review."
    }

    private func messageDetail(for message: ChatMessage) -> String? {
        switch message.extractionStatus {
        case .pending, .extracting:
            return "Saving"
        case .pendingToken:
            return "Waiting for service"
        case .pendingRetry:
            return "Retry later"
        case .partiallySucceeded, .failedNeedsReview, .needsReview, .failed:
            return "Needs review"
        case .notRequired, .succeeded:
            return nil
        }
    }

    private func productFacingDetail(_ detail: String?, fallbackType: LedgerReviewItemTargetType) -> String? {
        guard let detail = detail?.nilIfEmpty else { return nil }
        if isInternalStatusText(detail) {
            return fallbackType == .chatMessage ? "Needs review" : "Needs confirmation"
        }
        return detail
    }

    private func isInternalStatusText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ExtractionStatus.allCases.map(\.rawValue).contains(normalized) {
            return true
        }
        if ExtractionErrorCode.allCases.map(\.rawValue).contains(normalized) {
            return true
        }
        return normalized.contains("validation")
            || normalized.contains("extraction")
            || normalized.contains("schema_")
            || normalized.contains("invalid_json")
            || normalized == "failed"
            || normalized.contains("_failed")
            || normalized.contains("blocked next step")
            || normalized.contains("next step blocked")
            || normalized.contains("source:")
            || normalized.contains("source key:")
            || normalized.contains("matched key:")
            || normalized.contains("model confidence:")
    }
}
