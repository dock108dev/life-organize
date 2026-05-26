import SwiftUI
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

    func testTimestampAccessibilityFallbackPreservesLocalizedSuffixes() {
        XCTAssertEqual(LedgerTimelineTimestampLabel.accessibilityWrappedText(for: "12:59 PM"), "12:59\nPM")
        XCTAssertEqual(LedgerTimelineTimestampLabel.accessibilityWrappedText(for: "12:59\u{202F}PM"), "12:59\nPM")
        XCTAssertEqual(LedgerTimelineTimestampLabel.accessibilityWrappedText(for: "23:59"), "23:59")
    }

    func testTimelineContentLineLimitsExpandAtAccessibilitySizes() {
        XCTAssertEqual(LedgerTimelineDetailText.lineLimit(for: .large), 2)
        XCTAssertEqual(LedgerTimelineDetailText.lineLimit(for: .accessibility1), 4)
        XCTAssertEqual(LedgerTimelineSectionChrome<EmptyView>.subtitleLineLimit(for: .large), 1)
        XCTAssertEqual(LedgerTimelineSectionChrome<EmptyView>.subtitleLineLimit(for: .accessibility1), 2)
        XCTAssertEqual(LedgerTimelineSectionChrome<EmptyView>.summaryLineLimit(for: .large), 1)
        XCTAssertEqual(LedgerTimelineSectionChrome<EmptyView>.summaryLineLimit(for: .accessibility1), 2)
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
