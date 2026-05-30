import XCTest
@testable import LifeOrganize

final class CarryForwardListDetailContractTests: XCTestCase {
    func testSelectionRepairKeepsVisibleReminderSelected() {
        let first = UUID()
        let selected = UUID()

        XCTAssertEqual(
            RuleSelectionRepair.repairedSelection(
                selectedID: selected,
                currentVisibleIDs: [first, selected]
            ),
            selected
        )
    }

    func testSelectionRepairClearsMissingReminder() {
        XCTAssertNil(
            RuleSelectionRepair.repairedSelection(
                selectedID: UUID(),
                currentVisibleIDs: [UUID()]
            )
        )
    }

    func testSelectionRepairClearsHiddenReminderWhenNoRowsAreVisible() {
        XCTAssertNil(
            RuleSelectionRepair.repairedSelection(
                selectedID: UUID(),
                currentVisibleIDs: []
            )
        )
    }

    func testSelectionRepairLeavesEmptySelectionEmpty() {
        XCTAssertNil(
            RuleSelectionRepair.repairedSelection(
                selectedID: nil,
                currentVisibleIDs: []
            )
        )
    }

    func testSelectionRepairUsesPlaceholderWhenRowsBecomeVisibleWithoutSelection() {
        XCTAssertNil(
            RuleSelectionRepair.repairedSelection(
                selectedID: nil,
                currentVisibleIDs: [UUID()]
            )
        )
    }

    func testSelectionRepairKeepsSelectedPausedReminderWhenVisibilityIncludesIt() {
        let selectedPaused = UUID()

        XCTAssertEqual(
            RuleSelectionRepair.repairedSelection(
                selectedID: selectedPaused,
                currentVisibleIDs: [selectedPaused]
            ),
            selectedPaused
        )
    }

    func testLaneVisibilityIncludesSelectedPausedReminderWhenPausedRowsAreHidden() {
        XCTAssertEqual(
            RuleLaneVisibility.visibleLanes(showsPaused: false, selectedLane: .paused),
            [.now, .comingUp, .review, .paused]
        )
    }

    func testLaneVisibilityDoesNotChangeActiveLanesForActiveSelection() {
        XCTAssertEqual(
            RuleLaneVisibility.visibleLanes(showsPaused: false, selectedLane: .comingUp),
            [.now, .comingUp, .review]
        )
    }

    func testLaneVisibilityKeepsPausedToggleIndependentFromSelection() {
        XCTAssertEqual(
            RuleLaneVisibility.visibleLanes(showsPaused: true, selectedLane: nil),
            [.now, .comingUp, .review, .paused]
        )
    }
}
