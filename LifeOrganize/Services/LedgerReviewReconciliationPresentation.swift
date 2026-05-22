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
            evidence: evidencePanel(for: item, things: things, events: events, rules: rules, notes: notes, messages: messages),
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
            return panel(title: "Source Records", summary: nil, rows: rows, fallback: item.detail)
        }

        if let targetRow = targetRow(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes) {
            return LedgerReviewReconciliationPanel(title: sourceTitle(for: item.targetType), summary: nil, rows: [targetRow])
        }

        let rows = item.evidence.map {
            evidenceRow($0, things: things, events: events, rules: rules, notes: notes, messages: messages)
        }
        return panel(title: rows.count > 1 ? "Source Records" : sourceTitle(for: item.targetType), summary: nil, rows: rows, fallback: item.detail)
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
        let summary = [entry.detail.nilIfEmpty, confidenceText(for: item)].compactMap { $0 }.joined(separator: " ")
        return panel(
            title: "Suggested Interpretation",
            summary: summary.nilIfEmpty,
            rows: createdRows,
            fallback: item.title
        )
    }

    private func evidencePanel(
        for item: LedgerReviewItem,
        things: [Thing],
        events: [LedgerEvent],
        rules: [LedgerRule],
        notes: [LedgerNote],
        messages: [ChatMessage]
    ) -> LedgerReviewReconciliationPanel? {
        let rows = item.evidence.map {
            evidenceRow($0, things: things, events: events, rules: rules, notes: notes, messages: messages)
        }
        guard !rows.isEmpty else { return nil }
        return LedgerReviewReconciliationPanel(title: "Evidence", summary: nil, rows: rows)
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
            contextual.append(action(.saveAsNote, "Save as Note", role: .note, detail: "Keep this review context as a note and close the item."))
        }
        let reviewState = primary?.kind == .confirm ? [] : [action(.confirm, "Mark Reviewed", role: .reviewState)]
        return LedgerReviewReconciliationActions(
            primary: primary,
            contextual: contextual,
            reviewState: reviewState + [action(.snooze, "Snooze Until Tomorrow", role: .reviewState)],
            destructive: [action(.dismiss, "Dismiss", role: .destructive)]
        )
    }

    private func primaryAction(
        for item: LedgerReviewItem,
        entry: LedgerReviewQueueEntry,
        rules: [LedgerRule]
    ) -> LedgerReviewReconciliationAction? {
        if let blockedMessage = entry.blockedMessage {
            if entry.primaryActionTitle == "Connect Service" {
                return action(.connectService, "Connect Service", role: .primary, detail: blockedMessage)
            }
            return action(.blocked, "Next Step Blocked", role: .blocked, detail: blockedMessage, isEnabled: false)
        }

        if entry.primaryActionTitle == "Retry Now" {
            return action(.retry, "Retry Now", role: .primary)
        }
        if item.kind == .intervalReminder {
            return action(.buildReminderDraft, entry.primaryActionTitle, role: .primary)
        }
        if item.kind == .overdueReminderReview {
            let hasRule = targetRule(for: item, rules: rules) != nil
            return action(
                hasRule ? .adjustReminderTiming : .blocked,
                hasRule ? "Adjust Timing" : "Saved Reminder Missing",
                role: hasRule ? .primary : .blocked,
                detail: hasRule ? nil : "The saved reminder is no longer available. Use the evidence below, then dismiss or mark reviewed.",
                isEnabled: hasRule
            )
        }
        return action(.confirm, "Confirm", role: .primary)
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
                action(.mergeThing($0.id), "Merge into \($0.name)", role: .contextual, detail: "Move linked records, then close the review.")
            }
        }

        if item.kind == .normalizationCandidate {
            return openTargetAction(for: item, messages: messages, things: things, events: events, rules: rules, notes: notes).map { [$0] } ?? []
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
        return action(.openRecord(item.targetType, targetID), "Open \(sourceNoun(for: item.targetType))", role: .edit)
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
                "Suggested interpretation:",
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
                    detail: evidence.detail ?? $0.detail,
                    targetType: evidence.sourceType,
                    targetID: evidence.sourceID,
                    isMissing: false
                )
            }
            ?? LedgerReviewReconciliationRow(
                id: "evidence-missing-\(evidence.sourceType.rawValue)-\(evidence.sourceID.uuidString)",
                title: evidence.summary,
                detail: evidence.detail ?? "\(sourceNoun(for: evidence.sourceType)) is no longer available.",
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
                LedgerReviewReconciliationRow(id: "message-\(id.uuidString)", title: $0.text, detail: $0.extractionError, targetType: type, targetID: id)
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
        case .event:
            return "Saved Event"
        case .thing:
            return "Saved Thing"
        case .rule:
            return "Saved Reminder"
        case .none:
            return "Source Records"
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

    private func confidenceText(for item: LedgerReviewItem) -> String? {
        guard item.confidence < 0.99 else { return nil }
        return "Confidence \(Int((item.confidence * 100).rounded()))%."
    }
}
