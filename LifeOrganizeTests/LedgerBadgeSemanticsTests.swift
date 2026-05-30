import XCTest
@testable import LifeOrganize

final class LedgerBadgeSemanticsTests: XCTestCase {
    func testSemanticBadgesKeepRoleToneAndTextSeparate() {
        let source = LedgerBadgePresentation(semantic: .sourceUser)
        let saved = LedgerBadgePresentation(semantic: .statusSaved)
        let reminder = LedgerBadgePresentation(semantic: .categoryReminder)
        let note = LedgerBadgePresentation(semantic: .categoryNote)
        let window = LedgerBadgePresentation(semantic: .reminderWindow)

        XCTAssertEqual(source.role, .source)
        XCTAssertEqual(source.label, "You")
        XCTAssertEqual(source.tone, .muted)
        XCTAssertEqual(saved.role, .status)
        XCTAssertEqual(saved.label, "Saved")
        XCTAssertEqual(saved.tone, .muted)
        XCTAssertEqual(reminder.role, .category)
        XCTAssertEqual(reminder.label, "Reminder")
        XCTAssertEqual(reminder.tone, .muted)
        XCTAssertEqual(note.role, .category)
        XCTAssertEqual(note.tone, .note)
        XCTAssertEqual(window.role, .timing)
        XCTAssertEqual(window.label, "Window")
    }

    func testBadgeDefaultsReserveProductionColorRoles() {
        let attentionSemantics: [LedgerBadgeSemantic] = [.statusNow]
        let temporalSemantics: [LedgerBadgeSemantic] = [.statusUpcoming, .collectionUpcoming]
        let annotationSemantics: [LedgerBadgeSemantic] = [.categoryNote]
        let criticalSemantics: [LedgerBadgeSemantic] = [.statusFailed]
        let mutedSemantics: [LedgerBadgeSemantic] = [
            .categoryThing,
            .categoryEvent,
            .categoryReminder,
            .categoryMessage,
            .categoryTimeline,
            .sourceUser,
            .sourceApp,
            .sourceLog,
            .statusSaved,
            .statusSaving,
            .statusSavedLocal,
            .statusRetryPending,
            .statusPaused,
            .statusReviewed,
            .statusDismissed,
            .statusSnoozed,
            .statusExpired,
            .statusUpdated,
            .actionReview,
            .collectionReview,
            .reminderDueDate,
            .reminderWindow,
            .reminderOngoing,
            .reminderRepeating
        ]

        XCTAssertEqual(attentionSemantics.map { $0.defaultTone.semanticColorRole }, [.attention])
        XCTAssertEqual(temporalSemantics.map { $0.defaultTone.semanticColorRole }, [.temporal, .temporal])
        XCTAssertEqual(annotationSemantics.map { $0.defaultTone.semanticColorRole }, [.annotation])
        XCTAssertEqual(criticalSemantics.map { $0.defaultTone.semanticColorRole }, [.critical])
        XCTAssertTrue(mutedSemantics.allSatisfy { $0.defaultTone.semanticColorRole == .muted })
    }

    func testVisibleBadgesCapCountAndOrderByPriorityThenRole() {
        let category = LedgerBadgePresentation(semantic: .categoryThing, priority: 50)
        let source = LedgerBadgePresentation(semantic: .sourceLog, priority: 50)
        let timing = LedgerBadgePresentation(semantic: .reminderRepeating, priority: 50)
        let status = LedgerBadgePresentation(semantic: .statusSaved, priority: 50)
        let action = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 90)

        let visible = LedgerBadgePresentation.visibleBadges(
            from: [source, category, timing, status, action],
            maxCount: 3
        )

        XCTAssertEqual(visible.map(\.semantic), [.actionReview, .statusSaved, .reminderRepeating])
        XCTAssertEqual(visible.map(\.role), [.action, .status, .timing])
        XCTAssertEqual(LedgerBadgePresentation.visibleBadges(from: [action], maxCount: 0), [])
    }

    func testPrimaryBadgesEnforceSingleSemanticRowBadge() {
        let category = LedgerBadgePresentation(semantic: .categoryThing, label: "Home")
        let review = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 85)
        let repeating = LedgerBadgePresentation(semantic: .reminderRepeating)
        let duplicateReview = LedgerBadgePresentation(semantic: .actionReview, tone: .attention, priority: 85)
        let upcoming = LedgerBadgePresentation(semantic: .statusUpcoming, priority: 75)

        XCTAssertEqual(LedgerBadgePresentation.primaryBadges(from: [category, review]).map(\.semantic), [.actionReview])
        XCTAssertEqual(
            LedgerBadgePresentation.primaryBadges(from: [repeating, duplicateReview, review]).map(\.semantic),
            [.actionReview]
        )
        XCTAssertEqual(
            LedgerBadgePresentation.hiddenBadges(from: [upcoming, category], visibleBadges: [upcoming]).map(\.semantic),
            [.categoryThing]
        )
    }

    func testSearchReminderAndRelatedContextBadgesUseMutedSemanticRoles() {
        let searchPresentation = LocalSearchResultRowPresentation(result: searchResult())
        let reminder = LedgerRule(
            title: "Replace filter",
            ruleType: .reminder,
            continuityBehavior: .timeLimitedWindow,
            startsAt: fixedTestNow.addingTimeInterval(day),
            expiresAt: fixedTestNow.addingTimeInterval(3 * day),
            createdAt: fixedTestNow
        )
        let reminderPresentation = ReminderContinuityPresentationService().presentation(for: reminder, at: fixedTestNow)
        let event = LedgerEvent(title: "Oil change", occurredAt: fixedTestNow, rawText: "Changed oil.")
        let related = RelatedContextRowPresentation(
            result: RelationshipTraversalResult(
                target: .event(event.id),
                navigationTarget: .eventDetail(event.id),
                source: .linkedThing,
                sourceLabel: "Linked thing",
                sourceMessageID: nil,
                dedupeKey: "event-\(event.id.uuidString)",
                confidence: nil,
                createdBy: nil
            ),
            records: RelationshipTraversalRecords(events: [event])
        )

        XCTAssertEqual(searchPresentation.badges.count, 1)
        XCTAssertEqual(searchPresentation.badges.map(\.role), [.status])
        XCTAssertEqual(searchPresentation.badges.map(\.semantic), [.statusNow])
        XCTAssertTrue(searchPresentation.accessibilityLabel.contains("Reminder"))
        XCTAssertEqual(reminderPresentation.badges.map(\.role), [.status, .timing])
        XCTAssertEqual(reminderPresentation.badges.map(\.tone), [.info, .muted])
        XCTAssertEqual(related.badge.role, .category)
        XCTAssertEqual(related.badge.tone, .muted)
    }

    func testHighPriorityReviewBadgesEscalateWithoutChangingCopy() {
        let quiet = LedgerBadgePresentation.reviewState(for: .candidate, priority: 80, isHighPriority: false)
        let urgent = LedgerBadgePresentation.reviewState(for: .candidate, priority: 80, isHighPriority: true)
        let reviewed = LedgerBadgePresentation.reviewState(for: .accepted, priority: 80, isHighPriority: true)
        let failed = LedgerBadgePresentation.reviewState(for: .failed, priority: 80, isHighPriority: false)

        XCTAssertEqual(quiet.label, "Review")
        XCTAssertEqual(quiet.tone, .muted)
        XCTAssertEqual(urgent.label, "Review")
        XCTAssertEqual(urgent.tone, .attention)
        XCTAssertEqual(reviewed.label, "Reviewed")
        XCTAssertEqual(reviewed.tone, .muted)
        XCTAssertEqual(failed.label, "Needs review")
        XCTAssertEqual(failed.tone, .danger)
    }

    private func searchResult() -> LocalSearchResult {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
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

    private let day: TimeInterval = 86_400
}
