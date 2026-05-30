import XCTest
@testable import LifeOrganize

final class LedgerAdaptiveLayoutTests: XCTestCase {
    func testWidthRolesExposeSemanticCaps() {
        XCTAssertEqual(
            LedgerAdaptiveWidthRole.allCases,
            [.readable, .detail, .form, .sheet, .debugList, .debugDetail, .debugPayload, .fullBleed]
        )
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .readable), 680)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .detail), 820)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .form), 560)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .sheet), 520)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .debugList), 760)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .debugDetail), 820)
        XCTAssertEqual(LedgerAdaptiveLayout.maxWidth(for: .debugPayload), 920)
        XCTAssertNil(LedgerAdaptiveLayout.maxWidth(for: .fullBleed))
        XCTAssertEqual(LedgerAdaptiveLayout.Width.emptyStateMax, 320)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.contentMaxWidth, 320)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.surfaceMaxWidth, 430)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.settingsContentMax, 680)
    }

    func testWorkspaceMetricsExposeSharedRegularWidthComposition() {
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.listColumnMin, 300)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.listColumnIdeal, 340)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.listColumnMax, 390)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.splitDividerOpacity, 0.38)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.contentVerticalPadding, 18)
        XCTAssertEqual(LedgerAdaptiveLayout.Workspace.settingsContentMax, LedgerAdaptiveLayout.Width.readableMax)
    }

    func testEmptyStateMetricsExposeSharedSurfacePolicy() {
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.contentMaxWidth, LedgerAdaptiveLayout.Width.emptyStateMax)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.horizontalPadding, LedgerVisualSystem.Padding.noticeHorizontal)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.verticalPadding, 28)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.secondaryVerticalPadding, 22)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.cornerRadius, 18)
        XCTAssertEqual(LedgerAdaptiveLayout.EmptyState.searchLandingMinHeight, 420)
    }

    func testEditFormWidthRolesExposePerFlowCaps() {
        XCTAssertEqual(
            LedgerEditFormWidthRole.allCases,
            [.thing, .event, .note, .rule, .deleteReassignment]
        )
        XCTAssertEqual(LedgerAdaptiveLayout.editFormMaxWidth(for: .thing), 560)
        XCTAssertEqual(LedgerAdaptiveLayout.editFormMaxWidth(for: .event), 640)
        XCTAssertEqual(LedgerAdaptiveLayout.editFormMaxWidth(for: .note), 560)
        XCTAssertEqual(LedgerAdaptiveLayout.editFormMaxWidth(for: .rule), 600)
        XCTAssertEqual(LedgerAdaptiveLayout.editFormMaxWidth(for: .deleteReassignment), 520)
    }

    func testReadableAndDetailGuttersScaleByAvailableWidth() {
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 360, role: .readable), 16)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 430, role: .readable), 20)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 744, role: .detail), 20)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 1_024, role: .detail), 28)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 1_440, role: .readable), 40)
    }

    func testFormAndSheetGuttersStayTighterThanReadableColumns() {
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 360, role: .form), 16)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 430, role: .form), 20)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 744, role: .form), 24)
        XCTAssertEqual(LedgerAdaptiveLayout.gutter(for: 1_024, role: .sheet), 20)
    }

    func testContentWidthPreservesCompactSpaceAndCapsWideColumns() {
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 360, role: .readable), 328)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 430, role: .readable), 390)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 744, role: .detail), 704)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_024, role: .readable), 680)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .detail), 820)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .form), 560)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .debugList), 760)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .debugDetail), 820)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .debugPayload), 920)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 1_440, role: .fullBleed), 1_440)
        XCTAssertEqual(LedgerAdaptiveLayout.contentWidth(for: 0, role: .readable), 0)
    }

    func testEditFormsUseSharedRegularWidthContainment() throws {
        XCTAssertTrue(
            try sourceFile("LifeOrganize/Features/Things/ThingEditView.swift")
                .contains(".ledgerEditFormWidth(.thing)")
        )
        XCTAssertTrue(
            try sourceFile("LifeOrganize/Features/Things/EventEditView.swift")
                .contains(".ledgerEditFormWidth(.event)")
        )
        XCTAssertTrue(
            try sourceFile("LifeOrganize/Features/Things/NoteEditView.swift")
                .contains(".ledgerEditFormWidth(.note)")
        )
        XCTAssertTrue(
            try sourceFile("LifeOrganize/Features/Things/RuleEditView.swift")
                .contains(".ledgerEditFormWidth(.rule)")
        )
        XCTAssertTrue(
            try sourceFile("LifeOrganize/Features/Things/ThingDeleteReassignmentView.swift")
                .contains(".ledgerEditFormWidth(.deleteReassignment)")
        )
    }

    func testSharedDestinationSurfacesUseAdaptiveDetailContainment() throws {
        let eventSource = try sourceFile("LifeOrganize/Features/Things/EventDetailView.swift")
        let searchDestinationSource = try sourceFile("LifeOrganize/Features/Search/LocalSearchDestinationView.swift")
        let timelineReplaySource = try sourceFile("LifeOrganize/Features/Timeline/TimelineSliceReplayView.swift")

        XCTAssertTrue(eventSource.contains(".ledgerAdaptiveWidth(.detail)"))
        XCTAssertGreaterThanOrEqual(searchDestinationSource.occurrences(of: ".ledgerAdaptiveWidth(.detail)"), 3)
        XCTAssertTrue(timelineReplaySource.contains(".ledgerAdaptiveWidth(.detail)"))
    }

    func testSharedEmptyStatesUseAdaptiveSurfaceMetrics() throws {
        let emptyStateSource = try sourceFile("LifeOrganize/Features/Shared/LedgerEmptyStateView.swift")
        let searchSource = try sourceFile("LifeOrganize/Features/Search/UnifiedSearchView.swift")
        let settingsSource = try sourceFile("LifeOrganize/Features/Settings/SettingsView.swift")
        let reviewSource = try sourceFile("LifeOrganize/Features/Shared/LedgerReviewQueueView.swift")
        let thingsSplitSource = try sourceFile("LifeOrganize/Features/Things/ThingsSplitView.swift")
        let rulesSource = try sourceFile("LifeOrganize/Features/Rules/RulesListView.swift")

        XCTAssertTrue(emptyStateSource.contains("LedgerAdaptiveLayout.EmptyState.contentMaxWidth"))
        XCTAssertTrue(emptyStateSource.contains("LedgerAdaptiveLayout.EmptyState.surfaceMaxWidth"))
        XCTAssertTrue(emptyStateSource.contains("LedgerAdaptiveLayout.EmptyState.horizontalPadding"))
        XCTAssertTrue(emptyStateSource.contains("LedgerAdaptiveLayout.EmptyState.verticalPadding"))
        XCTAssertTrue(emptyStateSource.contains("LedgerAdaptiveLayout.EmptyState.cornerRadius"))
        XCTAssertTrue(emptyStateSource.contains("struct LedgerCenteredEmptyState"))
        let forbiddenFixedMaxWidth = ".frame(maxWidth: " + "320)"
        XCTAssertFalse(searchSource.contains(forbiddenFixedMaxWidth))
        XCTAssertTrue(searchSource.contains("LedgerAdaptiveLayout.EmptyState.contentMaxWidth"))
        XCTAssertTrue(searchSource.contains("LedgerAdaptiveLayout.EmptyState.searchLandingMinHeight"))
        XCTAssertTrue(searchSource.contains("LedgerSearchResultsList(results: searchResults)"))
        XCTAssertGreaterThanOrEqual(searchSource.occurrences(of: ".ledgerAdaptiveWidth(.readable)"), 2)
        XCTAssertTrue(searchSource.contains("LedgerNoSelectionPlaceholderView("))
        XCTAssertTrue(searchSource.contains("\"Select a result\""))
        XCTAssertTrue(settingsSource.contains("LedgerEmptyStateView(content: .settingsNoDeviceToken)"))
        XCTAssertTrue(settingsSource.contains(#""settings-workspace""#))
        XCTAssertTrue(reviewSource.contains("LedgerEmptyStateView(content: origin == nil"))
        XCTAssertGreaterThanOrEqual(reviewSource.occurrences(of: "LedgerNoSelectionPlaceholderView("), 1)
        XCTAssertTrue(reviewSource.contains(#""review-queue-detail""#))
        XCTAssertTrue(thingsSplitSource.contains(#""things-detail""#))
        XCTAssertTrue(thingsSplitSource.contains("\"Select a thing\""))
        XCTAssertTrue(thingsSplitSource.contains("\"No things yet\""))
        XCTAssertTrue(rulesSource.contains("RulesUIContract.detailPaneAccessibilityIdentifier"))
        XCTAssertTrue(rulesSource.contains("\"Select a reminder\""))
        XCTAssertTrue(rulesSource.contains("\"No reminders yet\""))
    }

    func testCrossFeatureDestinationBuildersKeepFeatureOwnedLookupContracts() throws {
        let searchDestinationSource = try sourceFile("LifeOrganize/Features/Search/LocalSearchDestinationView.swift")
        let relatedContextSource = try sourceFile("LifeOrganize/Features/Shared/RelatedContextViews.swift")
        let reviewDetailSource = try sourceFile("LifeOrganize/Features/Shared/LedgerReviewQueueDetailView.swift")
        let timelineSource = try sourceFile("LifeOrganize/Features/Chat/LedgerFeedTimelineViews.swift")

        XCTAssertTrue(searchDestinationSource.contains("struct LocalSearchDestinationView: View"))
        XCTAssertTrue(searchDestinationSource.contains("let things: [Thing]"))
        XCTAssertTrue(searchDestinationSource.contains("let events: [LedgerEvent]"))
        XCTAssertTrue(searchDestinationSource.contains("let rules: [LedgerRule]"))
        XCTAssertTrue(searchDestinationSource.contains("let notes: [LedgerNote]"))
        XCTAssertTrue(searchDestinationSource.contains("let messages: [ChatMessage]"))
        XCTAssertTrue(relatedContextSource.contains("struct RelatedContextDestinationView: View"))
        XCTAssertTrue(relatedContextSource.contains("MissingSearchRecordView()"))
        XCTAssertTrue(reviewDetailSource.contains("destination(for targetType: LedgerReviewItemTargetType, id: UUID)"))
        XCTAssertTrue(reviewDetailSource.contains("MissingSearchRecordView()"))
        XCTAssertTrue(timelineSource.contains("LedgerReviewQueueView("))
        XCTAssertTrue(timelineSource.contains("focusedItemID: reviewPresentation.item.id"))
        XCTAssertTrue(timelineSource.contains("deviceTokenStore: deviceTokenStore"))
        XCTAssertTrue(timelineSource.contains("onAddKey: onAddKey"))
        XCTAssertTrue(timelineSource.contains("EventDetailView(event: event)"))
    }

    func testSearchRegularWorkspaceUsesSelectionRouteAndExistingDestinationResolver() throws {
        let searchSource = try sourceFile("LifeOrganize/Features/Search/UnifiedSearchView.swift")
        let destinationSource = try sourceFile("LifeOrganize/Features/Search/LocalSearchDestinationView.swift")
        let sharedControlsSource = try sourceFile("LifeOrganize/Features/Shared/LedgerSharedControls.swift")

        XCTAssertTrue(searchSource.contains("struct LocalSearchSelectionRoute: Hashable, Identifiable"))
        XCTAssertTrue(searchSource.contains("@State private var selectedRoute: LocalSearchSelectionRoute?"))
        XCTAssertTrue(searchSource.contains("private var currentRoutes: [LocalSearchSelectionRoute]"))
        XCTAssertTrue(searchSource.contains("LocalSearchDestinationView("))
        XCTAssertTrue(searchSource.contains("target: selectedRoute.navigationTarget"))
        XCTAssertTrue(searchSource.contains("missingRecordActionTitle: \"Clear selection\""))
        XCTAssertTrue(searchSource.contains("onChange(of: currentRoutes)"))
        XCTAssertTrue(searchSource.contains("self.selectedRoute = nil"))
        XCTAssertFalse(searchSource.contains("NavigationSplitView {"))
        XCTAssertTrue(destinationSource.contains("missingRecordActionTitle: String"))
        XCTAssertTrue(destinationSource.contains("MissingSearchRecordView(actionTitle: missingRecordActionTitle"))
        XCTAssertTrue(sharedControlsSource.contains("selectedResultID: LocalSearchResult.ID?"))
        XCTAssertTrue(sharedControlsSource.contains("onSelect(result)"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private extension String {
    func occurrences(of substring: String) -> Int {
        components(separatedBy: substring).count - 1
    }
}
