import XCTest
@testable import LifeOrganize

final class ThingsListDetailContractTests: XCTestCase {
    func testSelectionRepairKeepsStableVisibleSelection() {
        let first = UUID()
        let second = UUID()
        let replacement = UUID()

        XCTAssertEqual(
            ThingSelectionRepair.repairedSelection(
                selectedID: second,
                previousVisibleIDs: [first, second],
                currentVisibleIDs: [first, second, replacement],
                defaultsToFirstVisible: true
            ),
            second
        )
    }

    func testSelectionRepairMovesToNextVisibleRecordAtSameIndex() {
        let first = UUID()
        let deleted = UUID()
        let next = UUID()

        XCTAssertEqual(
            ThingSelectionRepair.repairedSelection(
                selectedID: deleted,
                previousVisibleIDs: [first, deleted, next],
                currentVisibleIDs: [first, next],
                defaultsToFirstVisible: true
            ),
            next
        )
    }

    func testSelectionRepairFallsBackToPreviousVisibleRecord() {
        let previous = UUID()
        let deleted = UUID()

        XCTAssertEqual(
            ThingSelectionRepair.repairedSelection(
                selectedID: deleted,
                previousVisibleIDs: [previous, deleted],
                currentVisibleIDs: [previous],
                defaultsToFirstVisible: true
            ),
            previous
        )
    }

    func testSelectionRepairClearsWhenNoVisibleRecordsRemain() {
        XCTAssertNil(
            ThingSelectionRepair.repairedSelection(
                selectedID: UUID(),
                previousVisibleIDs: [UUID()],
                currentVisibleIDs: [],
                defaultsToFirstVisible: true
            )
        )
    }

    func testThingDetailLayoutBreakpointsProtectReadableColumns() {
        XCTAssertEqual(
            ThingDetailLayoutMode.mode(for: 500, horizontalSizeClass: .regular),
            .compactSingleColumn
        )
        XCTAssertEqual(
            ThingDetailLayoutMode.mode(for: 820, horizontalSizeClass: .regular),
            .readableSingleColumn
        )
        XCTAssertEqual(
            ThingDetailLayoutMode.mode(for: 1_024, horizontalSizeClass: .regular),
            .twoColumn
        )
        XCTAssertEqual(ThingDetailLayoutMode.twoColumn.contentWidth(for: 1_440), 1_120)
    }
}
