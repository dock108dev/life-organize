import XCTest
@testable import LifeOrganize

final class LedgerCopyRestraintTests: XCTestCase {
    func testPrimaryLedgerSurfacesUseProductLanguage() throws {
        let text = try primarySurfaceText().joined(separator: " ")

        XCTAssertNoImplementationLanguage(text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("saved"))
        XCTAssertTrue(text.contains("Review"))
    }

    func testSearchAndSettingsCopyKeepTrustLanguageSeparateFromDiagnosticLanguage() throws {
        let searchText = searchPresentationText().joined(separator: " ")
        let settingsText = settingsTrustText().joined(separator: " ")

        XCTAssertNoImplementationLanguage(searchText)
        XCTAssertNoImplementationLanguage(settingsText)
        XCTAssertTrue(settingsText.localizedCaseInsensitiveContains("app connection"))
        XCTAssertTrue(settingsText.localizedCaseInsensitiveContains("local"))
        XCTAssertFalse(settingsText.localizedCaseInsensitiveContains("OpenAI"))
    }

    func testDiagnosticEscapeHatchIsExplicit() {
        let diagnosticText = "Developer Diagnostics Extraction Attempts Failed Extractions"

        XCTAssertNoImplementationLanguage(diagnosticText, isDiagnosticSurface: true)
        XCTAssertThrowsError(try requirePrimaryCopy(diagnosticText))
    }

    func testReviewTimelineSettingsAndAssistantCopyHideInternalStatusTerms() throws {
        let message = ChatMessage(
            role: .user,
            text: "Book Bogey haircut in a week or two.",
            extractionStatus: .partiallySucceeded,
            extractionError: "schema_validation_failed",
            extractionErrorCode: .partialValidationFailed
        )
        let item = LedgerReviewItem(
            dedupeKey: "copy-restraint-\(UUID().uuidString)",
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "This entry created 2 saved items. Open them to check or edit.",
            actionTitle: "Open",
            targetType: .chatMessage,
            targetID: message.id,
            confidence: 0.72,
            evidence: [
                LedgerReviewItemEvidence(
                    sourceType: .chatMessage,
                    sourceID: message.id,
                    summary: message.text,
                    detail: ExtractionErrorCode.partialValidationFailed.rawValue
                ),
                LedgerReviewItemEvidence(
                    sourceType: .thing,
                    sourceID: UUID(),
                    summary: "Bogey",
                    detail: "source: Bogey; source key: bogey; model confidence: 88%"
                )
            ]
        )
        let entry = LedgerReviewQueueEntry(
            itemID: item.id,
            title: item.title,
            detail: item.detail,
            correctionClass: .quickReview,
            primaryActionTitle: "Open",
            blockedMessage: nil,
            createdRecords: [
                LedgerReviewCreatedRecord(targetType: .thing, targetID: UUID(), title: "Bogey", subtitle: "Thing"),
                LedgerReviewCreatedRecord(targetType: .rule, targetID: UUID(), title: "Bogey haircut", subtitle: "Reminder")
            ],
            origin: LedgerReviewOrigin(targetType: .chatMessage, targetID: message.id, label: "Bogey haircut")
        )
        let reviewPresentation = LedgerReviewReconciliationPresentationBuilder().presentation(
            for: item,
            entry: entry,
            messages: [message],
            things: [],
            events: [],
            rules: [],
            notes: []
        )
        let queuePresentation = LedgerReviewQueueRowPresentation(item: item, entry: entry, now: fixedTestNow)
        let timelineText = ExtractionStatus.allCases.map { status in
            LedgerFeedRowContent(item: .message(ChatMessage(role: .user, text: "Timeline entry", extractionStatus: status)))
        }
        .flatMap(Self.feedText)
        let assistantText = [
            ChatResponseFormatter().rawOnlyFailure(),
            ChatResponseFormatter().extractionFailed(),
            ChatResponseFormatter().unsupportedBoundary()
        ]
        let composerText = try chatComposerText()
        let settingsText = settingsTrustText()

        let visibleText = (
            reconciliationText(reviewPresentation)
                + queueText(queuePresentation)
                + timelineText
                + assistantText
                + composerText
                + settingsText
        ).joined(separator: " ")

        XCTAssertNoNormalUICopyLeaks(visibleText)
        XCTAssertTrue(visibleText.contains("Needs review"))
        XCTAssertTrue(visibleText.contains("Next Step"))
        XCTAssertTrue(visibleText.contains("Saved items") || visibleText.contains("saved items"))
        XCTAssertTrue(visibleText.contains("Thing"))
        XCTAssertTrue(visibleText.contains("Reminder"))
        XCTAssertTrue(visibleText.contains("Open"))
    }

    private func primarySurfaceText() throws -> [String] {
        let now = fixedTestNow
        let thing = Thing(name: "Furnace", category: .maintenance)
        let event = LedgerEvent(
            title: "Changed filter",
            occurredAt: now,
            rawText: "Changed filter.",
            eventType: .maintenance,
            thing: thing
        )
        let reminder = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            rawText: "Replace filter in two months.",
            startsAt: now.addingTimeInterval(60 * day),
            createdAt: now,
            thing: thing
        )
        let note = LedgerNote(text: "Filter size is 16x20.", createdAt: now, updatedAt: now, linkedThings: [thing])
        thing.events = [event]
        thing.rules = [reminder]
        thing.notes = [note]

        let feedRows = [
            LedgerFeedRowContent(item: .message(ChatMessage(role: .user, text: "Changed filter.", extractionStatus: .pending))),
            LedgerFeedRowContent(item: .message(ChatMessage(role: .assistant, text: "Review:\nOne item needs a decision.", extractionStatus: .notRequired))),
            LedgerFeedRowContent(item: .event(event)),
            LedgerFeedRowContent(item: .reminder(reminder)),
            LedgerFeedRowContent(item: .note(note))
        ].flatMap(Self.feedText)
        let preview = ThingPreviewSnapshot(thing: thing, now: now, calendar: testCalendar)
        let detail = ThingDetailSnapshot(thing: thing, now: now, calendar: testCalendar)
        let reminderPresentation = ReminderContinuityPresentationService().presentation(for: reminder, at: now)
        let reviewItem = LedgerReviewItem(
            dedupeKey: "copy-restraint-\(UUID().uuidString)",
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "The entry is saved on this device.",
            targetType: .chatMessage,
            targetID: UUID(),
            evidence: []
        )
        let reviewPresentation = LedgerReviewItemPresentationService().presentation(for: reviewItem)

        let thingPreviewText = preview.continuityLines.flatMap { [$0.label, $0.value, $0.detail].compactMap(\.self) }
            + preview.footerItems
            + [preview.listSummaryLine.text, preview.savedItemSummaryLine?.text].compactMap(\.self)
        let detailText = [
            detail.statusSummary.label,
            detail.statusSummary.value,
            detail.reminderSummary.label,
            detail.reminderSummary.value
        ]
        let reminderText = [
            reminderPresentation.primaryLine,
            reminderPresentation.badges.map(\.label).joined(separator: " ")
        ]
        let reviewText = [
            reviewPresentation.title,
            reviewPresentation.detail ?? "",
            reviewPresentation.rowLine.text
        ]

        return feedRows
            + searchPresentationText()
            + settingsTrustText()
            + thingPreviewText
            + detailText
            + reminderText
            + reviewText
    }

    private func searchPresentationText() -> [String] {
        let presentation = LocalSearchResultRowPresentation(result: searchResult())
        return [
            presentation.primaryText,
            presentation.footerText,
            presentation.dateText,
            presentation.kindPillText,
            presentation.rulePillText
        ].compactMap(\.self)
            + presentation.secondaryLines.map(\.text)
            + presentation.badges.map(\.label)
    }

    private func settingsTrustText() -> [String] {
        [
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            SettingsFeedback.deviceTokenSaved.message,
            SettingsFeedback.deviceTokenRemoved.message,
            SettingsFeedback.exportReady.message,
            SettingsFeedback.localDataCleared.message
        ]
    }

    private func chatComposerText() throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("LifeOrganize/Features/Chat/ChatInputBar.swift"),
            encoding: .utf8
        )
        let expectedCopy = [
            "Add anything or ask what’s due",
            "Saved. Organizing details",
            "Send to Timeline"
        ]
        for copy in expectedCopy {
            XCTAssertTrue(source.contains(copy), "Missing composer copy: \(copy)")
        }
        XCTAssertFalse(source.contains(".submitLabel(.done)"))
        XCTAssertFalse(source.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(source.contains("Image(systemName: \"paperplane.fill\")"))
        return expectedCopy
    }

    private static func feedText(_ content: LedgerFeedRowContent) -> [String] {
        [
            content.timestampText,
            content.sourceLabel,
            content.primaryText,
            content.secondaryText,
            content.detailText,
            content.linkedThingText
        ].compactMap(\.self)
    }

    private func reconciliationText(_ presentation: LedgerReviewReconciliationPresentation) -> [String] {
        var values = [presentation.title]
        values.append(contentsOf: panelText(presentation.source))
        values.append(contentsOf: panelText(presentation.suggestion))
        if let evidence = presentation.evidence {
            values.append(contentsOf: panelText(evidence))
        }
        values.append(contentsOf: presentation.actions.all.flatMap { [$0.title, $0.detail].compactMap(\.self) })
        if let saveAsNoteBody = presentation.saveAsNoteBody {
            values.append(saveAsNoteBody)
        }
        return values
    }

    private func panelText(_ panel: LedgerReviewReconciliationPanel) -> [String] {
        [panel.title, panel.summary].compactMap(\.self)
            + panel.rows.flatMap { [$0.title, $0.detail].compactMap(\.self) }
    }

    private func queueText(_ presentation: LedgerReviewQueueRowPresentation) -> [String] {
        [
            presentation.question,
            presentation.sourceHint,
            presentation.suggestedHint,
            presentation.urgencyText,
            presentation.nextActionTitle,
            presentation.hiddenBadgeAccessibilityText,
            presentation.accessibilityLabel
        ].compactMap(\.self) + presentation.badges.map(\.label)
    }

    private func searchResult() -> LocalSearchResult {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let record = LocalSearchRecord(
            id: recordID,
            kind: .rule,
            title: "Renew registration",
            subtitle: "Due May 21, 2026",
            body: "For Honda Civic",
            searchableFields: [],
            createdAt: fixedTestNow,
            occurredAt: nil,
            updatedAt: nil,
            linkedThingId: UUID(),
            linkedThingName: "Honda Civic",
            isActiveRule: true,
            ruleBadge: "Now",
            ruleLane: .now,
            timelineDateRange: nil,
            navigationTarget: .ruleDetail(recordID)
        )
        return LocalSearchResult(record: record, matchedFields: [.title], score: 1)
    }

    private func XCTAssertNoImplementationLanguage(
        _ text: String,
        isDiagnosticSurface: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bannedTerms = isDiagnosticSurface ? ["OpenAI", "embedding", "vector", "LLM"] : [
            "OpenAI",
            "assistant",
            "AI-powered",
            "extraction",
            "extractor",
            "model",
            "JSON",
            "schema",
            "confidence",
            "embedding",
            "vector",
            "LLM",
            "raw response",
            "normalizedJSONText",
            "requestJSON",
            ExtractionErrorCode.partialValidationFailed.rawValue,
            ExtractionStatus.partiallySucceeded.rawValue,
            ExtractionStatus.failedNeedsReview.rawValue,
            ExtractionStatus.needsReview.rawValue,
            "API key",
            "Authorization",
            "Bearer"
        ]
        let lowercased = text.lowercased()
        let offenders = bannedTerms.filter { lowercased.contains($0.lowercased()) }
        XCTAssertEqual(offenders, [], file: file, line: line)
    }

    private func XCTAssertNoNormalUICopyLeaks(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoImplementationLanguage(text, file: file, line: line)
        let lowercased = text.localizedLowercase
        let rawValues = ExtractionStatus.allCases.map(\.rawValue) + ExtractionErrorCode.allCases.map(\.rawValue)
        let forbiddenPhrases = rawValues + [
            "blocked next step",
            "next step blocked",
            "source:",
            "evidence",
            "validation",
            "extraction",
            "record",
            "records"
        ]
        let phraseOffenders = forbiddenPhrases.filter { lowercased.contains($0.localizedLowercase) }
        let failedAsStatus = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains("failed")
        XCTAssertEqual(phraseOffenders, [], file: file, line: line)
        XCTAssertFalse(failedAsStatus, file: file, line: line)
    }

    private func requirePrimaryCopy(_ text: String) throws {
        let bannedTerms = ["extraction", "extractor", "model", "JSON", "schema"]
        let offenders = bannedTerms.filter { text.localizedCaseInsensitiveContains($0) }
        if !offenders.isEmpty {
            throw CopyRestraintError.implementationTerms(offenders)
        }
    }

    private enum CopyRestraintError: Error {
        case implementationTerms([String])
    }

    private let day: TimeInterval = 86_400
    private let testCalendar = Calendar(identifier: .gregorian)
}
