import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewQueuePresentationTests: XCTestCase {
    func testQueueRowPresentationPrioritizesDecisionHintAndSemanticBadges() {
        let messageID = UUID()
        let thingID = UUID()
        let eventID = UUID()
        let item = LedgerReviewItem(
            dedupeKey: "queue-presentation-\(UUID().uuidString)",
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "Open the saved records to check the entry.",
            actionTitle: "Open Records",
            targetType: .chatMessage,
            targetID: messageID,
            evidence: [
                LedgerReviewItemEvidence(
                    sourceType: .chatMessage,
                    sourceID: messageID,
                    summary: "Changed cabin filter.",
                    detail: nil
                )
            ]
        )
        let entry = LedgerReviewQueueEntry(
            itemID: item.id,
            title: item.title,
            detail: item.detail,
            correctionClass: .quickReview,
            primaryActionTitle: "Open Records",
            blockedMessage: nil,
            createdRecords: [
                LedgerReviewCreatedRecord(targetType: .thing, targetID: thingID, title: "Car", subtitle: "Thing"),
                LedgerReviewCreatedRecord(
                    targetType: .event,
                    targetID: eventID,
                    title: "Cabin filter",
                    subtitle: "Event"
                )
            ],
            origin: nil
        )

        let presentation = LedgerReviewQueueRowPresentation(item: item, entry: entry, now: fixedTestNow)

        XCTAssertEqual(presentation.question, "Entry needs review")
        XCTAssertEqual(presentation.sourceHint, "Source: Changed cabin filter.")
        XCTAssertEqual(presentation.suggestedHint, "Suggested: Car, Cabin filter")
        XCTAssertEqual(presentation.urgencyText, "Needs decision")
        XCTAssertEqual(presentation.nextActionTitle, "Open Records")
        XCTAssertEqual(presentation.badges.map(\.semantic), [.actionReview, .categoryMessage])
        XCTAssertEqual(presentation.badges.map(\.role), [.action, .category])
    }

    func testPendingKeyRecoveryKeepsRetryActionForDetailRouting() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Changed car oil.",
            extractionStatus: .pendingKey,
            extractionErrorCode: .missingAPIKey
        )
        context.insert(message)
        try context.save()

        let items = try LedgerReviewItemGenerationService(modelContext: context, now: { fixedTestNow }).refresh()
        let item = try XCTUnwrap(items.first { $0.kind == .localRecovery })
        let entry = try LedgerReviewQueueService(
            modelContext: context,
            apiKeyStore: InMemoryAPIKeyStore()
        ).entry(for: item)

        let row = LedgerReviewQueueRowPresentation(item: item, entry: entry, now: fixedTestNow)
        let detail = LedgerReviewReconciliationPresentationBuilder().presentation(
            for: item,
            entry: entry,
            messages: [message],
            things: [],
            events: [],
            rules: [],
            notes: []
        )

        XCTAssertEqual(entry.primaryActionTitle, "Retry Now")
        XCTAssertNil(entry.blockedMessage)
        XCTAssertEqual(row.nextActionTitle, "Retry Now")
        XCTAssertEqual(row.urgencyText, "Needs decision")
        XCTAssertEqual(detail.actions.primary?.kind, .retry)
    }
}
