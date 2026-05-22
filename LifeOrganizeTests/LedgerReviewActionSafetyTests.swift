import SwiftData
import SwiftUI
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewActionSafetyTests: XCTestCase {
    func testPendingActionsCarryConfirmationCopyForReviewMutations() {
        let targetID = UUID()
        let actions: [LedgerReviewPendingAction] = [
            .retry,
            .markReviewed,
            .dismiss,
            .snooze(fixedTestNow),
            .mergeThings(targetID, "Garage"),
            .reassignRecords(targetID, "Garage"),
            .adjustReminderTiming(fixedTestNow, "Move Due Date"),
            .applyReminderLifecycle("Mark Done"),
            .saveAsNote
        ]

        for action in actions {
            XCTAssertFalse(action.id.isEmpty)
            XCTAssertFalse(action.dialogTitle.isEmpty)
            XCTAssertFalse(action.confirmTitle.isEmpty)
            XCTAssertFalse(action.message.isEmpty)
        }
        XCTAssertEqual(LedgerReviewPendingAction.dismiss.role, .destructive)
        XCTAssertEqual(LedgerReviewPendingAction.mergeThings(targetID, "Garage").role, .destructive)
        XCTAssertEqual(LedgerReviewPendingAction.applyReminderLifecycle("Mark Done").role, .destructive)
        XCTAssertNil(LedgerReviewPendingAction.saveAsNote.role)
    }

    func testContextMenuGuidanceDoesNotOfferMutationCopy() {
        XCTAssertEqual(
            LedgerReviewItemMenuCommands.guidanceMessage,
            "Open Review to update this item. No automatic change has been made."
        )
    }

    func testNonActionableReviewStateRejectsStateOnlyMutation() throws {
        let context = makeInMemoryModelContext()
        let item = reviewItem(state: .accepted)
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).markReviewed(item)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .actionUnavailable)
        }
        XCTAssertEqual(item.state, .accepted)
        XCTAssertNil(item.failureReason)
    }

    func testUnsupportedReminderTimingActionPreservesReviewItemState() throws {
        let context = makeInMemoryModelContext()
        let rule = LedgerRule(
            title: "Every Friday checklist",
            ruleType: .reminder,
            continuityBehavior: .recurringText,
            startsAt: fixedTestNow
        )
        let item = reviewItem(
            kind: .overdueReminderReview,
            targetType: .rule,
            targetID: rule.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil)]
        )
        context.insert(rule)
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).applyReminderDateAction(for: item, date: fixedTestNow)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .unsupportedAction)
        }
        XCTAssertEqual(item.state, .candidate)
        XCTAssertNil(item.failureReason)
    }

    func testRetryBlocksPartialCreatedRecordsAndKeepsReviewOpen() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .partiallySucceeded)
        let event = LedgerEvent(title: "Changed oil", occurredAt: fixedTestNow, rawText: "Changed oil")
        let attempt = ExtractionAttempt(status: .partiallySucceeded, createdEventIDs: [event.id], sourceMessage: message)
        let item = reviewItem(targetID: message.id, evidence: [
            LedgerReviewItemEvidence(sourceType: .chatMessage, sourceID: message.id, summary: message.text, detail: nil)
        ])
        context.insert(message)
        context.insert(event)
        context.insert(attempt)
        context.insert(item)
        try context.save()

        do {
            try await queueService(context).retryEntry(item)
            XCTFail("Retry should be blocked for entries with created records.")
        } catch let error as ManualExtractionRetryError {
            XCTAssertEqual(error, .notRetryable(.createdRecordsExist))
        }

        XCTAssertEqual(item.state, .candidate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).map(\.id), [event.id])
    }

    func testFailedRetryPreservesReviewItemState() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .failed)
        let item = reviewItem(targetID: message.id, evidence: [
            LedgerReviewItemEvidence(sourceType: .chatMessage, sourceID: message.id, summary: message.text, detail: nil)
        ])
        context.insert(message)
        context.insert(item)
        try context.save()

        var service = queueService(context)
        service.extractorFactory = { _ in ThrowingMessageExtractionClient(error: AppError.networkUnavailable) }
        do {
            try await service.retryEntry(item)
            XCTFail("Retry should not close the review item when extraction still fails.")
        } catch let error as LedgerReviewQueueError {
            XCTAssertEqual(error, .retryDidNotComplete)
        }

        XCTAssertEqual(item.state, .candidate)
        XCTAssertEqual(message.extractionStatus, .pendingRetry)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEvent>()).isEmpty)
    }

    func testSaveAsNoteFailureDoesNotCreateNoteOrCloseReview() throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(role: .user, text: "Garage code changed.", extractionStatus: .needsReview)
        let item = reviewItem(targetID: message.id, evidence: [
            LedgerReviewItemEvidence(sourceType: .chatMessage, sourceID: message.id, summary: message.text, detail: nil)
        ])
        context.insert(message)
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).saveAsNote(item, body: "  \n  ")) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .noActionableRecords)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerNote>()).isEmpty)
        XCTAssertEqual(item.state, .candidate)
    }

    private func reviewItem(
        state: LedgerReviewItemState = .candidate,
        kind: LedgerReviewItemKind = .localRecovery,
        targetType: LedgerReviewItemTargetType = .chatMessage,
        targetID: UUID? = UUID(),
        evidence: [LedgerReviewItemEvidence] = []
    ) -> LedgerReviewItem {
        LedgerReviewItem(
            dedupeKey: "review-action-safety-\(UUID().uuidString)",
            kind: kind,
            state: state,
            title: "Entry recovery is available",
            detail: "The original entry is saved locally.",
            actionTitle: "Retry Now",
            targetType: targetType,
            targetID: targetID,
            evidence: evidence,
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow
        )
    }

    private func queueService(_ context: ModelContext) -> LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
    }
}
