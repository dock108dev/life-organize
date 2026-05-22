import XCTest

final class LifeOrganizeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchTabsFakeExtractionAndPersistenceAcrossRelaunch() throws {
        let app = launchApp(resetStore: true, useInMemoryStore: false)

        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Things"].exists)
        XCTAssertTrue(app.tabBars.buttons["Carry Forward"].exists)

        send("Changed oil today.", in: app)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        app.tabBars.buttons["Things"].tap()
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        app.terminate()

        let relaunchedApp = launchApp(resetStore: false, useInMemoryStore: false)
        relaunchedApp.tabBars.buttons["Things"].tap()
        XCTAssertTrue(
            relaunchedApp.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5)
        )
    }

    func testFirstRunEmptyStatesAndSettingsAccess() throws {
        let app = launchApp(resetStore: true)

        XCTAssertTrue(app.staticTexts["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["device-token-notice"].exists)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI service"].exists)
        XCTAssertTrue(app.staticTexts["device-token-status"].exists)
        app.buttons["Done"].tap()

        send("No buying domains for 30 days.", in: app)
        dismissKeyboardIfVisible(in: app)
        tapTab("Carry Forward", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(labelContaining: "No buying domains").firstMatch.waitForFastExistence(timeout: 5)
        )
    }

    func testSettingsShowsDeviceServiceToken() throws {
        let app = launchApp(resetStore: true)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["device-token-save-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh Token"].exists)

        app.terminate()

        let cleanApp = launchApp(resetStore: true)
        cleanApp.buttons["Settings"].tap()
        XCTAssertTrue(cleanApp.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(cleanApp.buttons["Refresh Token"].exists)
    }

    func testRootSearchEntryIsAvailableFromEveryPrimaryTab() throws {
        let app = launchApp(resetStore: true)

        XCTAssertTrue(app.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
        tapPrimaryTab(at: 0.5, in: app)
        XCTAssertTrue(app.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
        tapPrimaryTab(at: 0.84, in: app)
        XCTAssertTrue(app.buttons["root-search-entry"].waitForFastExistence(timeout: 5))
    }

    func testGlobalLedgerSearchNavigatesToResultContext() throws {
        let app = launchApp(resetStore: true)

        send("Changed oil today at Valvoline.", in: app)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        app.buttons["root-search-entry"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Search"].exists)

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForFastExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Changed oil")
        let keyboardSearchButton = app.keyboards.buttons["Search"]
        if keyboardSearchButton.exists {
            keyboardSearchButton.tap()
        }

        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Event").firstMatch.waitForFastExistence(timeout: 5))
        let resultButton = app.buttons.matching(identifierPrefix: "ledger-search-result-event-").firstMatch
        XCTAssertTrue(resultButton.waitForFastExistence(timeout: 5))

        resultButton.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForFastExistence(timeout: 5))
        app.navigationBars["Event"].buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
    }

    func testPrimaryRenderedFlowsStayReachableWithoutExactRowCopy() throws {
        let app = launchApp(resetStore: true)

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.textFields["chat-input"].exists)
        XCTAssertTrue(app.buttons["chat-send-button"].exists)
        XCTAssertTrue(app.buttons["root-search-entry"].exists)

        send("Changed oil today.", in: app)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        send("No buying domains for 30 days.", in: app)
        dismissKeyboardIfVisible(in: app)
        tapTab("Carry Forward", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(labelContaining: "No buying domains").firstMatch.waitForFastExistence(timeout: 5)
        )
        tapTab("Timeline", in: app)

        app.buttons["root-search-entry"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForFastExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("oil")
        let keyboardSearchButton = app.keyboards.buttons["Search"]
        if keyboardSearchButton.exists {
            keyboardSearchButton.tap()
        }
        let searchEventResult = app.buttons.matching(identifierPrefix: "ledger-search-result-event-").firstMatch
        XCTAssertTrue(searchEventResult.waitForFastExistence(timeout: 5))
        dismissPresentedSearch(in: app)
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))

        tapTab("Things", in: app)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        tapTab("Carry Forward", in: app)
        XCTAssertTrue(
            app.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch.waitForFastExistence(timeout: 5)
        )
    }

    func testReviewQueueRenderedFlowForAmbiguousGroomingSeed() throws {
        let app = launchApp(
            resetStore: false,
            extraArguments: [
                "--reset-db",
                "-reset-device-token",
                "-fixed-now=2026-05-20T08:00:00-04:00",
                "--seed-scenario=ambiguous_dog_grooming"
            ]
        )

        XCTAssertTrue(app.buttons["Review Items"].waitForFastExistence(timeout: 5))
        app.buttons["Review Items"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 5))
        let bogeyReviewText = app.staticTexts.matching(labelContaining: "Review reminder for Bogey").firstMatch
        XCTAssertTrue(bogeyReviewText.waitForFastExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(labelContaining: "May 27 to June 3, 2026").firstMatch.waitForFastExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Choose Date").firstMatch.waitForFastExistence(timeout: 5))
        attachScreenshot(named: "review_queue", from: app)
    }

    func testDeterministicSimulatorWalkthroughCoversPrimarySurfaces() throws {
        let app = launchApp(
            resetStore: true,
            extraArguments: ["--seed-scenario=first-run-empty"],
            useInMemoryStore: false
        )

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Timeline"].exists)
        XCTAssertTrue(app.tabBars.buttons["Things"].exists)
        XCTAssertTrue(app.tabBars.buttons["Carry Forward"].exists)
        XCTAssertTrue(app.buttons["root-search-entry"].exists)
        XCTAssertTrue(app.buttons["settings-entry"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].exists)

        send("Changed oil today at Northstar Auto Bay.", in: app)
        XCTAssertTrue(
            app.buttons.matching(identifierPrefix: "timeline-row-event-").firstMatch.waitForFastExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))

        send("No buying domains for 30 days.", in: app)
        dismissKeyboardIfVisible(in: app)

        app.tabBars.buttons["Things"].tap()
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["things-list"].waitForFastExistence(timeout: 5))
        let thingRow = app.buttons.matching(identifierPrefix: "thing-row-").firstMatch
        XCTAssertTrue(thingRow.waitForFastExistence(timeout: 5))
        thingRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail-events-section"].waitForFastExistence(timeout: 5))
        app.navigationBars.buttons["Things"].tap()
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 5))

        tapPrimaryTab(at: 0.84, in: app)
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["carry-forward-list"].waitForFastExistence(timeout: 5))
        let carryForwardRow = app.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch
        XCTAssertTrue(carryForwardRow.waitForFastExistence(timeout: 5))
        carryForwardRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["carry-forward-detail"].waitForFastExistence(timeout: 5))
        app.navigationBars["Carry Forward"].buttons["Carry Forward"].tap()
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))

        app.buttons["root-search-entry"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search-landing-example-oil-last-month"].exists)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForFastExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("oil")
        let keyboardSearchButton = app.keyboards.buttons["Search"]
        if keyboardSearchButton.exists {
            keyboardSearchButton.tap()
        }
        let eventResult = app.buttons.matching(identifierPrefix: "ledger-search-result-event-").firstMatch
        XCTAssertTrue(eventResult.waitForFastExistence(timeout: 5))
        eventResult.tap()
        XCTAssertTrue(app.navigationBars["Event"].waitForFastExistence(timeout: 5))
        app.navigationBars["Event"].buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 5))
        dismissPresentedSearch(in: app)
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))

        tapTab("Timeline", in: app)
        send("partial oil update", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(labelContaining: "partial oil update").firstMatch.waitForFastExistence(timeout: 5)
        )

        app.terminate()
        let relaunchedApp = launchApp(resetStore: false, useInMemoryStore: false)
        let reviewButton = relaunchedApp.buttons["review-queue-button"]
        XCTAssertTrue(reviewButton.waitForFastExistence(timeout: 5))
        reviewButton.tap()
        XCTAssertTrue(relaunchedApp.navigationBars["Review"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(relaunchedApp.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 5))
        let reviewRow = relaunchedApp.buttons.matching(identifierPrefix: "review-queue-row-").firstMatch
        XCTAssertTrue(reviewRow.waitForFastExistence(timeout: 5))
        reviewRow.tap()
        XCTAssertTrue(relaunchedApp.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 5))
        let reviewDetailSource = relaunchedApp.descendants(matching: .any)["review-queue-detail-source"]
        XCTAssertTrue(reviewDetailSource.waitForFastExistence(timeout: 5))
        XCTAssertTrue(
            relaunchedApp.descendants(matching: .any)["review-queue-detail-question"].waitForFastExistence(timeout: 5)
        )
        XCTAssertTrue(relaunchedApp.buttons["review-queue-dismiss-button"].waitForFastExistence(timeout: 5))
        relaunchedApp.navigationBars["Review"].buttons["Review"].tap()
        relaunchedApp.buttons["review-queue-close-button"].tap()
        XCTAssertTrue(relaunchedApp.navigationBars["Timeline"].waitForFastExistence(timeout: 5))

        relaunchedApp.buttons["settings-entry"].tap()
        XCTAssertTrue(relaunchedApp.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(relaunchedApp.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        relaunchedApp.buttons["settings-done-button"].tap()
        XCTAssertTrue(relaunchedApp.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
    }

    private func launchApp(
        resetStore: Bool,
        extraArguments: [String] = [],
        useInMemoryStore: Bool = true
    ) -> XCUIApplication {
        launchUITestApp(
            extraArguments: extraArguments,
            resetStore: resetStore,
            resetDeviceToken: resetStore,
            useInMemoryStore: useInMemoryStore
        )
    }

    private func tapPrimaryTab(at xPosition: Double, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForFastExistence(timeout: 5))
        tabBar.coordinate(withNormalizedOffset: CGVector(dx: xPosition, dy: 0.5)).tap()
    }
}
