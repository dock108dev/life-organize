import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewReconciliationPresentationTests: XCTestCase {
    func testExtractionReviewElevatesOriginalEntryAndCreatedRecords() {
        let message = ChatMessage(role: .user, text: "Changed the cabin filter.", extractionStatus: .partiallySucceeded)
        let thingID = UUID()
        let eventID = UUID()
        let item = reviewItem(
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "This entry created 2 saved items. Open them to check or edit.",
            actionTitle: "Open",
            targetType: .chatMessage,
            targetID: message.id,
            evidence: [evidence(.chatMessage, message.id, message.text)]
        )
        let entry = queueEntry(
            for: item,
            primaryActionTitle: "Open",
            createdRecords: [
                LedgerReviewCreatedRecord(targetType: .thing, targetID: thingID, title: "Car", subtitle: "Thing"),
                LedgerReviewCreatedRecord(targetType: .event, targetID: eventID, title: "Changed cabin filter", subtitle: "Event")
            ]
        )

        let presentation = builder.presentation(
            for: item,
            entry: entry,
            messages: [message],
            things: [Thing(id: thingID, name: "Car")],
            events: [LedgerEvent(id: eventID, title: "Changed cabin filter", occurredAt: fixedTestNow, rawText: "Changed the cabin filter.")],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.source.title, "Original Entry")
        XCTAssertEqual(presentation.source.rows.first?.title, "Changed the cabin filter.")
        XCTAssertEqual(presentation.suggestion.title, "Saved Items")
        XCTAssertEqual(presentation.suggestion.rows.map(\.title), ["Car", "Changed cabin filter"])
        XCTAssertNil(presentation.evidence)
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .openRecord(.thing, thingID) && $0.title == "Edit Thing" })
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .openRecord(.event, eventID) && $0.title == "Edit Event" })
        XCTAssertEqual(presentation.actions.primary?.title, "Done")
        XCTAssertFalse(presentation.actions.all.contains { $0.kind == .saveAsNote })
        XCTAssertFalse(Self.visibleText(in: presentation).contains("Suggested Interpretation"))
    }

    func testLocalRecoverySupportsRetryAndSaveAsNote() {
        let message = ChatMessage(role: .user, text: "Remember the paint color.", extractionStatus: .failed)
        let item = reviewItem(
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The entry is saved on this device. Try again or mark it done.",
            actionTitle: "Try Again",
            targetType: .chatMessage,
            targetID: message.id,
            evidence: [evidence(.chatMessage, message.id, message.text)]
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item, primaryActionTitle: "Try Again"),
            messages: [message],
            things: [],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.actions.primary?.kind, .retry)
        XCTAssertEqual(presentation.actions.reviewState.first?.title, "Done")
        XCTAssertEqual(presentation.suggestion.title, "Next Step")
        XCTAssertEqual(presentation.suggestion.summary, "Try again, or keep this entry as a note.")
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .saveAsNote })
        XCTAssertTrue(presentation.saveAsNoteBody?.contains("Remember the paint color.") == true)
        XCTAssertFalse(presentation.saveAsNoteBody?.contains("Suggested interpretation") == true)
    }

    func testExtractionReviewSanitizesRawEvidenceWithoutChangingStoredEvidence() {
        let message = ChatMessage(
            role: .user,
            text: "Book Bogey haircut in a week or two.",
            extractionStatus: .needsReview,
            extractionError: "schema_validation_failed",
            extractionErrorCode: .partialValidationFailed
        )
        let detailID = UUID()
        let item = reviewItem(
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "The entry is saved on this device. Try again or review details.",
            targetType: .chatMessage,
            targetID: message.id,
            confidence: 0.72,
            evidence: [
                evidence(.chatMessage, message.id, message.text, ExtractionErrorCode.partialValidationFailed.rawValue),
                evidence(.thing, detailID, "Bogey", "source: Bogey; source key: bogey; model confidence: 88%")
            ]
        )
        let originalEvidenceJSON = item.evidenceJSONText

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item),
            messages: [message],
            things: [],
            events: [],
            rules: [],
            notes: []
        )
        let visibleText = Self.visibleText(in: presentation)

        XCTAssertEqual(item.evidenceJSONText, originalEvidenceJSON)
        XCTAssertEqual(presentation.source.rows.first?.detail, "Needs review")
        XCTAssertTrue(visibleText.contains("Needs review"))
        XCTAssertTrue(visibleText.contains("Next Step"))
        XCTAssertFalse(visibleText.contains(ExtractionErrorCode.partialValidationFailed.rawValue))
        XCTAssertFalse(visibleText.contains(ExtractionStatus.needsReview.rawValue))
        XCTAssertFalse(visibleText.localizedCaseInsensitiveContains("schema"))
        XCTAssertFalse(visibleText.localizedCaseInsensitiveContains("model confidence"))
        XCTAssertEqual(message.extractionErrorCodeRawValue, ExtractionErrorCode.partialValidationFailed.rawValue)
    }

    func testDuplicateThingShowsCandidatesWithoutSaveAsNote() {
        let target = Thing(name: "Printer Paper")
        let source = Thing(name: "printer paper", details: "Office shelf")
        let item = reviewItem(
            kind: .duplicateThing,
            title: "Possible duplicate Things",
            detail: "These Things share a saved name. No items have been merged.",
            actionTitle: "Review Things",
            targetType: .thing,
            targetID: target.id,
            confidence: 0.8,
            evidence: [
                evidence(.thing, target.id, target.name),
                evidence(.thing, source.id, source.name, source.details)
            ]
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item, primaryActionTitle: "Review Things"),
            messages: [],
            things: [target, source],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.source.title, "Saved Items")
        XCTAssertEqual(presentation.source.rows.map(\.title), ["Printer Paper", "printer paper"])
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .mergeThing(target.id) })
        XCTAssertEqual(presentation.suggestion.title, "Next Step")
        XCTAssertEqual(presentation.suggestion.summary, "Choose the item to keep, or dismiss this if both should stay.")
        XCTAssertNil(presentation.saveAsNoteBody)
    }

    func testNormalizationCandidateOpensThingWithoutDeadReassignAction() {
        let thing = Thing(name: "nws", normalizedKey: "nws")
        let item = reviewItem(
            kind: .normalizationCandidate,
            title: "Thing name is ready for review",
            detail: "nws can be reviewed against saved naming rules as NWS. No name has been changed.",
            actionTitle: "Review Thing",
            targetType: .thing,
            targetID: thing.id,
            confidence: 0.75,
            evidence: [evidence(.thing, thing.id, thing.name, "Normalized key: nws")]
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item, primaryActionTitle: "Review Thing"),
            messages: [],
            things: [thing],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.actions.contextual.map(\.kind), [.openRecord(.thing, thing.id)])
        XCTAssertEqual(presentation.actions.contextual.map(\.title), ["Edit Thing"])
        XCTAssertFalse(presentation.actions.all.contains { action in
            if case .reassignRecords = action.kind { return true }
            return false
        })
    }

    func testConflictingDateCanBeSavedAsNote() {
        let event = LedgerEvent(title: "Dentist", occurredAt: fixedTestNow, rawText: "Dentist next Friday")
        let item = reviewItem(
            kind: .conflictingDate,
            title: "Event has conflicting dates",
            detail: "Dentist is dated one day, while saved metadata includes another.",
            actionTitle: "Review event",
            targetType: .event,
            targetID: event.id,
            confidence: 0.85,
            evidence: [evidence(.event, event.id, event.title, event.rawText)]
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item, primaryActionTitle: "Review event"),
            messages: [],
            things: [],
            events: [event],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.source.title, "Saved Items")
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .openRecord(.event, event.id) && $0.title == "Edit Event" })
        XCTAssertTrue(presentation.actions.contextual.contains { $0.kind == .saveAsNote })
    }

    func testReminderReviewsUseStructuredReminderActions() {
        let thing = Thing(name: "HVAC")
        let event = LedgerEvent(title: "Changed filter", occurredAt: fixedTestNow, rawText: "Changed filter", thing: thing)
        let interval = reviewItem(
            kind: .intervalReminder,
            title: "HVAC cadence is ready for review",
            detail: "Saved items show about every 90 days. No reminder has been created or changed.",
            actionTitle: "Review reminder setup",
            targetType: .thing,
            targetID: thing.id,
            evidence: [evidence(.event, event.id, event.title, "90-day interval")]
        )
        let rule = LedgerRule(title: "Renew license", ruleType: .deadline, startsAt: fixedTestNow)
        let overdue = reviewItem(
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Date passed.",
            targetType: .rule,
            targetID: rule.id,
            evidence: [evidence(.rule, rule.id, rule.title)]
        )

        let intervalPresentation = builder.presentation(
            for: interval,
            entry: queueEntry(for: interval, primaryActionTitle: "Review reminder setup"),
            messages: [],
            things: [thing],
            events: [event],
            rules: [],
            notes: []
        )
        let overduePresentation = builder.presentation(
            for: overdue,
            entry: queueEntry(for: overdue, primaryActionTitle: "Adjust Timing"),
            messages: [],
            things: [],
            events: [],
            rules: [rule],
            notes: []
        )

        XCTAssertEqual(intervalPresentation.actions.primary?.kind, .buildReminderDraft)
        XCTAssertEqual(overduePresentation.actions.primary?.kind, .adjustReminderTiming)
        XCTAssertEqual(intervalPresentation.source.title, "Saved Items")
        XCTAssertEqual(overduePresentation.actions.contextual.first?.title, "Edit Reminder")
        XCTAssertFalse(intervalPresentation.actions.all.contains { $0.kind == .saveAsNote })
    }

    func testBlockedAndMissingTargetsRemainExplainable() {
        let missingID = UUID()
        let item = reviewItem(
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Date passed.",
            targetType: .rule,
            targetID: missingID,
            evidence: [evidence(.rule, missingID, "Renew registration")]
        )
        let blocked = queueEntry(for: item, primaryActionTitle: "Review Details", blockedMessage: "The saved item could not be found.")

        let presentation = builder.presentation(
            for: item,
            entry: blocked,
            messages: [],
            things: [],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.source.rows.first?.title, "Reminder no longer exists")
        XCTAssertEqual(presentation.actions.primary?.kind, .blocked)
        XCTAssertEqual(presentation.actions.primary?.isEnabled, false)
        XCTAssertEqual(presentation.actions.primary?.title, "Needs Attention")
        XCTAssertEqual(presentation.actions.primary?.detail, "Update or restore the reminder before closing this review.")
        XCTAssertFalse(presentation.actions.reviewState.contains { $0.kind == .confirm })
    }

    func testEmptyEvidenceStillShowsMinimumReviewShape() {
        let item = reviewItem(
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "The entry is saved on this device.",
            targetType: .chatMessage,
            targetID: nil,
            evidence: []
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(for: item),
            messages: [],
            things: [],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.source.rows.first?.title, "The entry is saved on this device.")
        XCTAssertNil(presentation.evidence)
        XCTAssertEqual(presentation.actions.primary?.kind, .confirm)
        XCTAssertEqual(presentation.actions.primary?.title, "Done")
        XCTAssertEqual(presentation.suggestion.title, "Next Step")
    }

    func testDeletedCreatedRecordIsCalledOut() {
        let recordID = UUID()
        let item = reviewItem(
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "This entry created saved items.",
            targetType: .chatMessage,
            targetID: nil,
            evidence: []
        )

        let presentation = builder.presentation(
            for: item,
            entry: queueEntry(
                for: item,
                primaryActionTitle: "Open",
                createdRecords: [LedgerReviewCreatedRecord(targetType: .event, targetID: recordID, title: "Changed filter", subtitle: "Event")]
            ),
            messages: [],
            things: [],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(presentation.suggestion.rows.first?.title, "Changed filter")
        XCTAssertEqual(presentation.suggestion.rows.first?.isMissing, true)
        XCTAssertTrue(presentation.suggestion.rows.first?.detail?.contains("no longer exists") == true)
        XCTAssertNil(presentation.evidence)
    }

    func testSaveAsNoteCreatesNoteAndAcceptsReviewItem() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Garage code changed.", extractionStatus: .needsReview)
        let thing = Thing(name: "Garage")
        let item = reviewItem(
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The entry is saved on this device.",
            targetType: .chatMessage,
            targetID: message.id,
            evidence: [
                evidence(.chatMessage, message.id, message.text),
                evidence(.thing, thing.id, thing.name)
            ]
        )
        context.insert(message)
        context.insert(thing)
        context.insert(item)
        try context.save()

        let note = try LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        .saveAsNote(item, body: "Original Entry:\nGarage code changed.")

        let savedNotes = try context.fetch(FetchDescriptor<LedgerNote>())
        XCTAssertEqual(savedNotes.map(\.id), [note.id])
        XCTAssertEqual(note.sourceMessage?.id, message.id)
        XCTAssertEqual(note.linkedThingIDs, [thing.id])
        XCTAssertEqual(item.state, .accepted)
    }

    private var builder: LedgerReviewReconciliationPresentationBuilder {
        LedgerReviewReconciliationPresentationBuilder()
    }

    private static func visibleText(in presentation: LedgerReviewReconciliationPresentation) -> String {
        var values = [presentation.title]
        values += panelText(presentation.source)
        values += panelText(presentation.suggestion)
        if let evidence = presentation.evidence {
            values += panelText(evidence)
        }
        values += presentation.actions.all.flatMap { [$0.title, $0.detail].compactMap(\.self) }
        return values.joined(separator: " ")
    }

    private static func panelText(_ panel: LedgerReviewReconciliationPanel) -> [String] {
        [panel.title, panel.summary].compactMap(\.self)
            + panel.rows.flatMap { [$0.title, $0.detail].compactMap(\.self) }
    }

    private func queueEntry(
        for item: LedgerReviewItem,
        primaryActionTitle: String = "Confirm",
        blockedMessage: String? = nil,
        createdRecords: [LedgerReviewCreatedRecord] = []
    ) -> LedgerReviewQueueEntry {
        LedgerReviewQueueEntry(
            itemID: item.id,
            title: item.title,
            detail: item.detail,
            correctionClass: correctionClass(for: item.kind),
            primaryActionTitle: primaryActionTitle,
            blockedMessage: blockedMessage,
            createdRecords: createdRecords,
            origin: nil
        )
    }

    private func reviewItem(
        kind: LedgerReviewItemKind,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        targetType: LedgerReviewItemTargetType,
        targetID: UUID?,
        confidence: Double = 1,
        evidence: [LedgerReviewItemEvidence]
    ) -> LedgerReviewItem {
        LedgerReviewItem(
            dedupeKey: "\(kind.rawValue)|\(UUID().uuidString)",
            kind: kind,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            targetType: targetType,
            targetID: targetID,
            confidence: confidence,
            evidence: evidence,
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow
        )
    }

    private func evidence(
        _ sourceType: LedgerReviewItemTargetType,
        _ sourceID: UUID,
        _ summary: String,
        _ detail: String? = nil
    ) -> LedgerReviewItemEvidence {
        LedgerReviewItemEvidence(sourceType: sourceType, sourceID: sourceID, summary: summary, detail: detail)
    }

    private func correctionClass(for kind: LedgerReviewItemKind) -> LedgerReviewCorrectionClass {
        switch kind {
        case .duplicateThing:
            return .mergeDuplicateThings
        case .normalizationCandidate:
            return .reassignRecordsToThing
        case .overdueReminderReview, .intervalReminder:
            return .adjustReminderTiming
        case .localRecovery, .extractionReview, .conflictingDate:
            return .quickReview
        }
    }
}
