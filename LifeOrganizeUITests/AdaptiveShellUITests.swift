import UIKit
import XCTest

final class AdaptiveShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRegularWidthSidebarShowsWorkspaceUtilitiesAndConditionalReview() throws {
        try requirePad()
        // layout-guard: allow UIDevice reason="test sets simulator orientation before launching app"
        XCUIDevice.shared.orientation = .landscapeLeft

        let emptyApp = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=first-run-empty",
            "-skip-launch-maintenance"
        ])

        assertSidebarExists(in: emptyApp)
        XCTAssertTrue(emptyApp.buttons["sidebar-section-timeline"].exists)
        XCTAssertTrue(emptyApp.buttons["sidebar-section-things"].exists)
        XCTAssertTrue(emptyApp.buttons["sidebar-section-carry-forward"].exists)
        XCTAssertTrue(emptyApp.buttons["sidebar-section-search"].exists)
        XCTAssertTrue(emptyApp.buttons["sidebar-section-settings"].exists)
        XCTAssertFalse(emptyApp.buttons["sidebar-section-review"].exists)
        XCTAssertFalse(emptyApp.tabBars.firstMatch.exists)
        emptyApp.terminate()

        let operationalApp = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=operational_home",
            "-fixed-now=2026-07-05T08:00:00-04:00"
        ])

        assertSidebarExists(in: operationalApp)
        assertRegularSelection(.timeline, in: operationalApp, expectedIdentifier: "timeline-feed")
        XCTAssertTrue(operationalApp.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.buttons["settings-entry"].exists)
        XCTAssertFalse(operationalApp.buttons["add-thing-button"].exists)
        XCTAssertFalse(operationalApp.buttons["add-reminder-button"].exists)
        assertRegularSelection(.things, in: operationalApp, expectedIdentifier: "things-list", requiresNavigationTitle: false)
        XCTAssertTrue(operationalApp.descendants(matching: .any)["things-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.buttons["add-thing-button"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(operationalApp.buttons["root-search-entry"].exists)
        XCTAssertTrue(operationalApp.buttons["settings-entry"].exists)
        assertRegularSelection(
            .carryForward,
            in: operationalApp,
            expectedIdentifier: "carry-forward-list",
            requiresNavigationTitle: false
        )
        XCTAssertTrue(operationalApp.descendants(matching: .any)["carry-forward-detail-pane"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.buttons["add-reminder-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.buttons["root-search-entry"].exists)
        XCTAssertTrue(operationalApp.buttons["settings-entry"].exists)
        assertRegularSelection(.search, in: operationalApp)
        XCTAssertTrue(operationalApp.searchFields.firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertFalse(operationalApp.buttons["search-done-button"].exists)
        assertRegularSelection(.settings, in: operationalApp)
        XCTAssertTrue(operationalApp.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.buttons["device-token-save-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(operationalApp.descendants(matching: .any)["settings-workspace"].exists)
        XCTAssertFalse(operationalApp.buttons["settings-done-button"].exists)
        XCTAssertFalse(operationalApp.tabBars.firstMatch.exists)
        operationalApp.terminate()

        let reviewApp = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=ambiguous_dog_grooming",
            "-fixed-now=2026-05-20T08:00:00-04:00"
        ])

        assertSidebarExists(in: reviewApp)
        XCTAssertTrue(reviewApp.buttons["sidebar-section-review"].waitForFastExistence(timeout: 5))
        assertRegularSelection(.review, in: reviewApp, expectedIdentifier: "review-queue-list")
        XCTAssertTrue(reviewApp.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(reviewApp.buttons["review-queue-close-button"].exists)
        XCTAssertFalse(reviewApp.tabBars.firstMatch.exists)
    }

    func testCompactLaunchKeepsTabsAndUtilityModals() throws {
        try requireCompactDevice()
        // layout-guard: allow UIDevice reason="test sets simulator orientation before launching app"
        XCUIDevice.shared.orientation = .portrait

        let app = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=first-run-empty"
        ])

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Timeline"].exists)
        XCTAssertTrue(app.tabBars.buttons["Things"].exists)
        XCTAssertTrue(app.tabBars.buttons["Carry Forward"].exists)
        XCTAssertFalse(app.buttons["sidebar-section-timeline"].exists)
        XCTAssertTrue(app.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-entry"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-thing-button"].exists)
        XCTAssertFalse(app.buttons["add-reminder-button"].exists)

        app.buttons["root-search-entry"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search-done-button"].waitForFastExistence(timeout: 5))
        app.buttons["search-done-button"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))

        app.buttons["settings-entry"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["device-token-save-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-done-button"].waitForFastExistence(timeout: 5))
        app.buttons["settings-done-button"].tap()
        app.terminate()

        let reviewApp = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=ambiguous_dog_grooming",
            "-fixed-now=2026-05-20T08:00:00-04:00"
        ])

        XCTAssertTrue(reviewApp.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.tabBars.buttons["Timeline"].exists)
        XCTAssertTrue(reviewApp.buttons["review-queue-button"].waitForFastExistence(timeout: 5))
        reviewApp.buttons["review-queue-button"].tap()
        XCTAssertTrue(reviewApp.navigationBars["Review"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.buttons["review-queue-close-button"].waitForFastExistence(timeout: 5))
        reviewApp.buttons["review-queue-close-button"].tap()
        XCTAssertTrue(reviewApp.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
    }

    func testPadPortraitShellKeepsCoreDestinationsReachable() throws {
        try requirePad()
        // layout-guard: allow UIDevice reason="test sets simulator orientation before launching app"
        XCUIDevice.shared.orientation = .portrait

        let app = launchAdaptiveApp(arguments: [
            "--reset-db",
            "--seed-scenario=operational_home",
            "-fixed-now=2026-07-05T08:00:00-04:00"
        ])

        if app.buttons["sidebar-section-timeline"].waitForFastExistence(timeout: 5) {
            assertRegularSelection(.timeline, in: app, expectedIdentifier: "timeline-feed")
            assertRegularSelection(.things, in: app, expectedIdentifier: "things-list", requiresNavigationTitle: false)
            assertRegularSelection(
                .carryForward,
                in: app,
                expectedIdentifier: "carry-forward-list",
                requiresNavigationTitle: false
            )
            assertRegularSelection(.search, in: app)
            XCTAssertFalse(app.buttons["search-done-button"].exists)
            assertRegularSelection(.settings, in: app)
            XCTAssertFalse(app.buttons["settings-done-button"].exists)
        } else {
            XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.buttons["Timeline"].exists)
            XCTAssertTrue(app.tabBars.buttons["Things"].exists)
            XCTAssertTrue(app.tabBars.buttons["Carry Forward"].exists)
            XCTAssertTrue(app.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
            XCTAssertTrue(app.buttons["settings-entry"].waitForFastExistence(timeout: 5))
        }

        app.terminate()
    }

    func testRegularWidthScreenshotStartsRouteToSidebarDestinations() throws {
        try requirePad()
        // layout-guard: allow UIDevice reason="test sets simulator orientation before launching app"
        XCUIDevice.shared.orientation = .landscapeLeft

        let searchApp = launchScreenshotStartApp(seed: "search", start: "search", searchQuery: "registration renewal")
        waitForScreenshotReady(in: searchApp)
        assertSidebarExists(in: searchApp)
        XCTAssertTrue(searchApp.navigationBars["Search"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(searchApp.searchFields.firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertTrue(searchApp.staticTexts["Select a result"].waitForFastExistence(timeout: 5))
        let searchResult = searchApp.buttons.matching(identifierPrefix: "ledger-search-result-").firstMatch
        XCTAssertTrue(searchResult.waitForFastExistence(timeout: 5))
        searchResult.tap()
        XCTAssertTrue(searchApp.searchFields.firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertTrue(searchApp.buttons.matching(identifierPrefix: "ledger-search-result-").firstMatch.exists)
        XCTAssertFalse(searchApp.buttons["search-done-button"].exists)
        XCTAssertFalse(searchApp.tabBars.firstMatch.exists)
        searchApp.terminate()

        let settingsApp = launchScreenshotStartApp(seed: "empty", start: "settings")
        waitForScreenshotReady(in: settingsApp)
        assertSidebarExists(in: settingsApp)
        XCTAssertTrue(settingsApp.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(settingsApp.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(settingsApp.buttons["device-token-save-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(settingsApp.descendants(matching: .any)["settings-workspace"].exists)
        XCTAssertFalse(settingsApp.buttons["settings-done-button"].exists)
        XCTAssertFalse(settingsApp.tabBars.firstMatch.exists)
        settingsApp.terminate()

        let reviewApp = launchScreenshotStartApp(seed: "review", start: "review")
        waitForScreenshotReady(in: reviewApp)
        assertSidebarExists(in: reviewApp)
        XCTAssertTrue(reviewApp.navigationBars["Review"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(reviewApp.buttons["sidebar-section-review"].exists)
        XCTAssertFalse(reviewApp.buttons["review-queue-close-button"].exists)
        XCTAssertFalse(reviewApp.tabBars.firstMatch.exists)
    }

    private enum SidebarDestination {
        case timeline
        case things
        case carryForward
        case search
        case review
        case settings

        var title: String {
            switch self {
            case .timeline: "Timeline"
            case .things: "Things"
            case .carryForward: "Carry Forward"
            case .search: "Search"
            case .review: "Review"
            case .settings: "Settings"
            }
        }

        var identifier: String {
            switch self {
            case .timeline: "sidebar-section-timeline"
            case .things: "sidebar-section-things"
            case .carryForward: "sidebar-section-carry-forward"
            case .search: "sidebar-section-search"
            case .review: "sidebar-section-review"
            case .settings: "sidebar-section-settings"
            }
        }
    }

    private func launchAdaptiveApp(arguments: [String]) -> XCUIApplication {
        launchUITestApp(
            extraArguments: arguments,
            resetStore: false,
            resetDeviceToken: true,
            useInMemoryStore: true
        )
    }

    private func launchScreenshotStartApp(seed: String, start: String, searchQuery: String? = nil) -> XCUIApplication {
        var arguments = [
            "-screenshot-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-fixed-now=2027-01-15T08:00:00-05:00",
            "-screenshot-seed=\(seed)",
            "-screenshot-start=\(start)",
            "-screenshot-locale=en_US",
            "-screenshot-time-zone=America/New_York",
            "-screenshot-calendar=gregorian",
            "-screenshot-appearance=light",
            "-skip-launch-maintenance"
        ]
        if let searchQuery {
            arguments.append("-screenshot-search-query=\(searchQuery)")
        }
        return launchUITestApp(extraArguments: arguments, useInMemoryStore: true)
    }

    private func assertSidebarExists(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["sidebar-section-timeline"].waitForFastExistence(timeout: 5), file: file, line: line)
    }

    private func assertRegularSelection(
        _ destination: SidebarDestination,
        in app: XCUIApplication,
        expectedIdentifier: String? = nil,
        requiresNavigationTitle: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons[destination.identifier]
        XCTAssertTrue(button.waitForFastExistence(timeout: 5), file: file, line: line)
        button.tap()
        if requiresNavigationTitle {
            XCTAssertTrue(app.navigationBars[destination.title].waitForFastExistence(timeout: 5), file: file, line: line)
        }
        if let expectedIdentifier {
            XCTAssertTrue(
                app.descendants(matching: .any)[expectedIdentifier].waitForFastExistence(timeout: 5),
                file: file,
                line: line
            )
        }
        XCTAssertFalse(app.tabBars.firstMatch.exists, file: file, line: line)
    }

    private func waitForScreenshotReady(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot-ready"].waitForFastExistence(timeout: 5),
            file: file,
            line: line
        )
    }

    private func requirePad() throws {
        // layout-guard: allow UIDevice reason="test selects a matching simulator family"
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Regular-width sidebar coverage runs on iPad destinations.")
        }
    }

    private func requireCompactDevice() throws {
        // layout-guard: allow UIDevice reason="test selects a matching simulator family"
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            throw XCTSkip("Compact tab coverage runs on iPhone or compact-width destinations.")
        }
    }
}
