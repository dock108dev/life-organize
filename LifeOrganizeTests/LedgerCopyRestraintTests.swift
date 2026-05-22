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
        XCTAssertTrue(settingsText.localizedCaseInsensitiveContains("service token"))
        XCTAssertTrue(settingsText.localizedCaseInsensitiveContains("local"))
        XCTAssertFalse(settingsText.localizedCaseInsensitiveContains("OpenAI"))
    }

    func testDiagnosticEscapeHatchIsExplicit() {
        let diagnosticText = "Developer Diagnostics Extraction Attempts Failed Extractions"

        XCTAssertNoImplementationLanguage(diagnosticText, isDiagnosticSurface: true)
        XCTAssertThrowsError(try requirePrimaryCopy(diagnosticText))
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
            LedgerFeedRowContent(item: .note(note)),
        ].flatMap(Self.feedText)
        let preview = ThingPreviewSnapshot(thing: thing, now: now, calendar: testCalendar)
        let detail = ThingDetailSnapshot(thing: thing, now: now, calendar: testCalendar)
        let reminderPresentation = ReminderContinuityPresentationService().presentation(for: reminder, at: now)
        let reviewItem = LedgerReviewItem(
            dedupeKey: "copy-restraint-\(UUID().uuidString)",
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "The original entry is saved locally.",
            targetType: .chatMessage,
            targetID: UUID(),
            evidence: []
        )
        let reviewPresentation = LedgerReviewItemPresentationService().presentation(for: reviewItem)

        let thingPreviewText = preview.continuityLines.flatMap { [$0.label, $0.value, $0.detail].compactMap(\.self) }
            + preview.footerItems
        let detailText = [
            detail.statusSummary.label,
            detail.statusSummary.value,
            detail.reminderSummary.label,
            detail.reminderSummary.value,
        ]
        let reminderText = [
            reminderPresentation.primaryLine,
            reminderPresentation.badges.map(\.label).joined(separator: " "),
        ]
        let reviewText = [
            reviewPresentation.title,
            reviewPresentation.detail ?? "",
            reviewPresentation.rowLine.text,
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
            presentation.rulePillText,
        ].compactMap(\.self)
            + presentation.secondaryLines.map(\.text)
            + presentation.badges.map(\.label)
    }

    private func settingsTrustText() -> [String] {
        [
            SettingsTrustCopy.deviceTokenTitle,
            SettingsTrustCopy.deviceTokenBody,
            SettingsTrustCopy.noTokenDetail,
            SettingsTrustCopy.savedTokenDetail,
            SettingsTrustCopy.exportTitle,
            SettingsTrustCopy.exportBody,
            SettingsTrustCopy.clearTitle,
            SettingsTrustCopy.clearBody,
            SettingsTrustCopy.clearDeletes,
            SettingsTrustCopy.clearKeeps,
            SettingsFeedback.deviceTokenSaved.message,
            SettingsFeedback.deviceTokenRemoved.message,
            SettingsFeedback.exportReady.message,
            SettingsFeedback.localDataCleared.message,
        ]
    }

    private static func feedText(_ content: LedgerFeedRowContent) -> [String] {
        [
            content.timestampText,
            content.sourceLabel,
            content.primaryText,
            content.secondaryText,
            content.detailText,
            content.linkedThingText,
        ].compactMap(\.self)
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
        ]
        let lowercased = text.lowercased()
        let offenders = bannedTerms.filter { lowercased.contains($0.lowercased()) }
        XCTAssertEqual(offenders, [], file: file, line: line)
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
