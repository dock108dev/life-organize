import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewItemPresentationTests: XCTestCase {
    func testLogRowUsesOneTargetedReviewLine() {
        let messageID = UUID()
        let newest = item(
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The original entry is saved locally.",
            actionTitle: "Review entry",
            targetType: .chatMessage,
            targetID: messageID,
            updatedAt: fixedTestNow
        )
        let older = item(
            kind: .extractionReview,
            title: "Entry needs review",
            detail: "The original entry is saved locally.",
            targetType: .chatMessage,
            targetID: messageID,
            updatedAt: fixedTestNow.addingTimeInterval(-day)
        )

        let presentation = service.primaryPresentation(
            for: .chatMessage,
            targetID: messageID,
            in: [older, newest]
        )

        XCTAssertEqual(presentation?.title, "Entry recovery is available")
        XCTAssertEqual(presentation?.rowLine.text, "Review: Entry recovery is available")
        XCTAssertEqual(presentation?.primaryActionTitle, "Review entry")
        XCTAssertEqual(service.presentations(for: .chatMessage, targetID: messageID, in: [older, newest]).count, 2)
    }

    func testThingsRowMatchesEvidenceAndLimitsPrimaryRowItem() {
        let thingID = UUID()
        let evidenceMatched = item(
            kind: .duplicateThing,
            title: "Possible duplicate Things",
            detail: "These Things share the same normalized name. No records have been merged.",
            targetType: .thing,
            targetID: UUID(),
            evidence: [evidence(.thing, thingID, "Garage remote")],
            updatedAt: fixedTestNow
        )
        let lowerPriority = item(
            kind: .normalizationCandidate,
            title: "Thing name is ready for review",
            detail: "The saved name can be reviewed.",
            targetType: .thing,
            targetID: thingID,
            updatedAt: fixedTestNow.addingTimeInterval(day)
        )

        let presentation = service.primaryPresentation(
            for: .thing,
            targetID: thingID,
            in: [lowerPriority, evidenceMatched]
        )

        XCTAssertEqual(presentation?.title, "Possible duplicate Things")
        XCTAssertEqual(presentation?.pillText, "Review")
        XCTAssertEqual(presentation?.tone, .muted)
        XCTAssertEqual(presentation?.badge.role, .action)
    }

    func testThingDetailSummaryUsesSingleHighPriorityBannerCandidate() {
        let thingID = UUID()
        let highPriority = item(
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The original entry is saved locally.",
            targetType: .thing,
            targetID: thingID
        )
        let lowerPriority = item(
            kind: .intervalReminder,
            title: "Service cadence is ready for review",
            detail: "Saved records show a cadence.",
            targetType: .thing,
            targetID: thingID,
            updatedAt: fixedTestNow.addingTimeInterval(day)
        )

        let banner = service.bannerPresentation(in: [lowerPriority, highPriority])

        XCTAssertEqual(banner?.title, "Entry recovery is available")
        XCTAssertEqual(banner?.tone, .attention)
        XCTAssertEqual(banner?.badge.semantic, .actionReview)
        XCTAssertTrue(banner?.isHighPriority == true)
        XCTAssertFalse(lowerPriorityPresentation.isHighPriority)
    }

    func testRemindersRowUsesConsistentToneForRuleTargets() {
        let ruleID = UUID()
        let reviewItem = item(
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Complete, reschedule, pause, or dismiss from the reminder record.",
            targetType: .rule,
            targetID: ruleID
        )

        let listPresentation = service.primaryPresentation(for: .rule, targetID: ruleID, in: [reviewItem])
        let queuePresentation = service.presentation(for: reviewItem)

        XCTAssertEqual(listPresentation?.tone, .attention)
        XCTAssertEqual(listPresentation?.tone, queuePresentation.tone)
        XCTAssertEqual(listPresentation?.rowLine.lineLimit, 2)
    }

    func testNoItemStateReturnsNoAmbientPresentation() {
        XCTAssertNil(service.primaryPresentation(for: .event, targetID: UUID(), in: []))
    }

    func testLifecycleStatesHaveDistinctSubduedPresentation() {
        let targetID = UUID()
        let accepted = item(state: .accepted, targetID: targetID)
        let dismissed = item(state: .dismissed, targetID: targetID)
        let snoozed = item(state: .snoozed, targetID: targetID)
        snoozed.snoozedUntil = fixedTestNow.addingTimeInterval(day)
        let expired = item(state: .expired, targetID: targetID)
        let failed = item(state: .failed, targetID: targetID)
        failed.fail(reason: "The saved record could not be updated.", at: fixedTestNow)

        let presentations = [accepted, dismissed, snoozed, expired, failed].map(service.presentation(for:))

        XCTAssertEqual(presentations.map(\.pillText), ["Reviewed", "Dismissed", "Snoozed", "Expired", "Failed"])
        XCTAssertEqual(presentations.map(\.tone), [.muted, .muted, .muted, .muted, .danger])
        XCTAssertEqual(presentations.map(\.badge.semantic), [
            .statusReviewed,
            .statusDismissed,
            .statusSnoozed,
            .statusExpired,
            .statusFailed,
        ])
        XCTAssertTrue(presentations[2].detail?.contains("Returns") == true)
        XCTAssertEqual(presentations[4].detail, "The saved record could not be updated.")
    }

    private var lowerPriorityPresentation: LedgerReviewItemPresentation {
        service.presentation(for: item(kind: .intervalReminder, targetType: .thing, targetID: UUID()))
    }

    private var service: LedgerReviewItemPresentationService {
        LedgerReviewItemPresentationService()
    }

    private let day: TimeInterval = 86_400

    private func item(
        state: LedgerReviewItemState = .candidate,
        kind: LedgerReviewItemKind = .extractionReview,
        title: String = "Entry needs review",
        detail: String = "The original entry is saved locally.",
        actionTitle: String? = nil,
        targetType: LedgerReviewItemTargetType = .event,
        targetID: UUID,
        evidence: [LedgerReviewItemEvidence] = [],
        updatedAt: Date = fixedTestNow
    ) -> LedgerReviewItem {
        let item = LedgerReviewItem(
            dedupeKey: "\(kind.rawValue)|\(targetID.uuidString)|\(updatedAt.timeIntervalSince1970)",
            kind: kind,
            state: state,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            targetType: targetType,
            targetID: targetID,
            evidence: evidence,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        item.updatedAt = updatedAt
        return item
    }

    private func evidence(
        _ sourceType: LedgerReviewItemTargetType,
        _ sourceID: UUID,
        _ summary: String
    ) -> LedgerReviewItemEvidence {
        LedgerReviewItemEvidence(sourceType: sourceType, sourceID: sourceID, summary: summary, detail: nil)
    }
}
