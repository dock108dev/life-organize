import SwiftUI
import XCTest
@testable import LifeOrganize

final class LedgerReviewQueueListDetailContractTests: XCTestCase {
    func testFocusedReviewSeedsSelectionOnceWhenVisible() {
        let first = UUID()
        let focused = UUID()

        let result = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: nil,
            preferredFocusedID: focused,
            lastAppliedFocusedID: nil,
            previousVisibleIDs: [],
            currentVisibleIDs: [first, focused]
        )

        XCTAssertEqual(result.selectedID, focused)
        XCTAssertEqual(result.lastAppliedFocusedID, focused)
    }

    func testUserSelectionSurvivesAfterFocusedReviewWasApplied() {
        let focused = UUID()
        let selected = UUID()

        let result = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: selected,
            preferredFocusedID: focused,
            lastAppliedFocusedID: focused,
            previousVisibleIDs: [focused, selected],
            currentVisibleIDs: [focused, selected]
        )

        XCTAssertEqual(result.selectedID, selected)
        XCTAssertEqual(result.lastAppliedFocusedID, focused)
    }

    func testSelectedReviewRemainsSelectedAcrossQueueRefresh() {
        let first = UUID()
        let selected = UUID()
        let last = UUID()

        let result = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: selected,
            preferredFocusedID: nil,
            lastAppliedFocusedID: nil,
            previousVisibleIDs: [first, selected, last],
            currentVisibleIDs: [first, selected, last]
        )

        XCTAssertEqual(result.selectedID, selected)
    }

    func testSelectionAdvancesToNextVisibleReviewAtSameIndex() {
        let first = UUID()
        let removed = UUID()
        let next = UUID()

        let result = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: removed,
            preferredFocusedID: nil,
            lastAppliedFocusedID: nil,
            previousVisibleIDs: [first, removed, next],
            currentVisibleIDs: [first, next]
        )

        XCTAssertEqual(result.selectedID, next)
    }

    func testSelectionClearsWhenQueueIsEmpty() {
        let result = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: UUID(),
            preferredFocusedID: nil,
            lastAppliedFocusedID: nil,
            previousVisibleIDs: [UUID()],
            currentVisibleIDs: []
        )

        XCTAssertNil(result.selectedID)
    }

    func testDetailLayoutUsesRailOnlyForWideRegularNonAccessibilityWidths() {
        XCTAssertEqual(
            ReviewQueueDetailLayout.mode(
                for: 744,
                horizontalSizeClass: .regular,
                isAccessibilitySize: false
            ),
            .singleColumn
        )
        XCTAssertEqual(
            ReviewQueueDetailLayout.mode(
                for: 900,
                horizontalSizeClass: .regular,
                isAccessibilitySize: false
            ),
            .twoColumn
        )
        XCTAssertEqual(
            ReviewQueueDetailLayout.mode(
                for: 900,
                horizontalSizeClass: .regular,
                isAccessibilitySize: true
            ),
            .singleColumn
        )
        XCTAssertEqual(ReviewQueueDetailLayout.actionColumnWidth(for: 900), 300)
        XCTAssertEqual(ReviewQueueDetailLayout.actionColumnWidth(for: 1_200), 360)
    }
}
