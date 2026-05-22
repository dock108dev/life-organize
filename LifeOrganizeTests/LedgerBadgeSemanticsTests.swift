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

        XCTAssertLessThanOrEqual(searchPresentation.badges.count, 2)
        XCTAssertEqual(searchPresentation.badges.map(\.role), [.status, .category])
        XCTAssertEqual(searchPresentation.badges.map(\.semantic), [.statusNow, .categoryReminder])
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
        XCTAssertEqual(failed.label, "Failed")
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
