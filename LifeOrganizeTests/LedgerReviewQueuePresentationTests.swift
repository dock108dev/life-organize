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
            detail: "Open the saved items to check the entry.",
            actionTitle: "Open",
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
            primaryActionTitle: "Open",
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
        XCTAssertEqual(presentation.sourceHint, "Changed cabin filter.")
        XCTAssertEqual(presentation.suggestedHint, "Saved items include Car, Cabin filter")
        XCTAssertEqual(presentation.urgencyText, "Ready for decision")
        XCTAssertEqual(presentation.nextActionTitle, "Open")
        XCTAssertEqual(presentation.badges.map(\.semantic), [.actionReview])
        XCTAssertEqual(presentation.badges.map(\.role), [.action])
        XCTAssertEqual(presentation.hiddenBadgeAccessibilityText, "Context: Message")
        XCTAssertTrue(presentation.accessibilityLabel.contains("Context: Message"))
    }

    func testPendingTokenRecoveryKeepsRetryActionForDetailRouting() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "Changed car oil.",
            extractionStatus: .pendingToken,
            extractionErrorCode: .missingServiceToken
        )
        context.insert(message)
        try context.save()

        let items = try LedgerReviewItemGenerationService(modelContext: context, now: { fixedTestNow }).refresh()
        let item = try XCTUnwrap(items.first { $0.kind == .localRecovery })
        let entry = try LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore()
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
        XCTAssertEqual(row.urgencyText, "Ready for decision")
        XCTAssertEqual(detail.actions.primary?.kind, .retry)
    }
}
