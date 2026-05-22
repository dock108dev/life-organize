import XCTest
@testable import LifeOrganize

final class LedgerTimelineChromeTests: XCTestCase {
    func testSharedRowChromeComputesDividerAlignmentFromTimelineAtoms() {
        let layout = LedgerTimelineRowChromeLayout(
            rowHorizontalPadding: 6,
            rowVerticalPadding: 3,
            rowColumnSpacing: 7,
            timestampWidth: 56,
            markerSize: 4,
            timestampTopPadding: 0,
            markerTopPadding: 7
        )

        XCTAssertEqual(layout.dividerLeadingPadding, 80)
    }

    func testFeedAndReplayUseSharedChromeWithoutConvergingDensity() {
        XCTAssertEqual(LedgerFeedTimelineLayout.rowChrome.dividerLeadingPadding, LedgerFeedTimelineLayout.dividerLeadingPadding)
        XCTAssertEqual(TimelineSliceReplayLayout.rowChrome.dividerLeadingPadding, TimelineSliceReplayLayout.dividerLeadingPadding)

        XCTAssertLessThan(LedgerFeedTimelineLayout.rowChrome.rowHorizontalPadding, TimelineSliceReplayLayout.rowChrome.rowHorizontalPadding)
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowChrome.rowVerticalPadding, TimelineSliceReplayLayout.rowChrome.rowVerticalPadding)
        XCTAssertLessThan(LedgerFeedTimelineLayout.rowChrome.markerSize, TimelineSliceReplayLayout.rowChrome.markerSize)
        XCTAssertEqual(LedgerFeedTimelineLayout.rowChrome.timestampTopPadding, 0)
        XCTAssertEqual(TimelineSliceReplayLayout.rowChrome.timestampTopPadding, 1)
    }
}
