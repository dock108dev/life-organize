import XCTest

extension LifeOrganizeScenarioUITests {
    func testOperationalHomeSeedScenarioWalkthroughCapturesContinuitySurfaces() throws {
        let app = launchOperationalHomeSeed(resetStore: true, initialTab: nil)

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Replaced Home Air Filters").firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Bought dog food").firstMatch.exists)
        attachScreenshot(named: "operational_home.timeline", from: app)
        app.terminate()

        let seededApp = launchOperationalHomeSeed(resetStore: false, initialTab: "things")
        XCTAssertTrue(seededApp.navigationBars["Things"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(seededApp.descendants(matching: .any)["things-list"].exists)
        let filtersRow = seededApp.buttons.containing(.staticText, identifier: "Home Air Filters").firstMatch
        XCTAssertTrue(filtersRow.exists)
        XCTAssertTrue(seededApp.staticTexts.matching(labelContaining: "Home Air Filters").firstMatch.exists)
        attachScreenshot(named: "operational_home.things", from: seededApp)

        filtersRow.tap()
        XCTAssertTrue(seededApp.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(seededApp.navigationBars["Home Air Filters"].exists)
        XCTAssertTrue(seededApp.descendants(matching: .any)["thing-detail-title"].exists)
        attachScreenshot(named: "operational_home.thing_detail", from: seededApp)
        seededApp.navigationBars["Home Air Filters"].buttons["Things"].tap()

        tapTab("Carry Forward", in: seededApp)
        XCTAssertTrue(seededApp.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(seededApp.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch.exists)
        XCTAssertTrue(seededApp.staticTexts.matching(labelContaining: "Replace Home Air Filters").firstMatch.exists)
        attachScreenshot(named: "operational_home.carry_forward", from: seededApp)

        seededApp.buttons["root-search-entry"].tap()
        XCTAssertTrue(seededApp.navigationBars["Search"].waitForFastExistence(timeout: 5))
        let searchField = seededApp.searchFields.firstMatch
        XCTAssertTrue(searchField.exists)
        searchField.tap()
        searchField.typeText("Harbor Warehouse")
        let keyboardSearchButton = seededApp.keyboards.buttons["Search"]
        if keyboardSearchButton.exists {
            keyboardSearchButton.tap()
        }
        let eventResult = seededApp.buttons.matching(identifierPrefix: "ledger-search-result-event-").firstMatch
        XCTAssertTrue(eventResult.waitForFastExistence(timeout: 5))
        XCTAssertTrue(seededApp.staticTexts.matching(labelContaining: "Bought household supplies").firstMatch.exists)
        attachScreenshot(named: "operational_home.search", from: seededApp)
    }

    private func launchOperationalHomeSeed(resetStore: Bool, initialTab: String?) -> XCUIApplication {
        var arguments = [
            "--seed-scenario=operational_home",
            "-fixed-now=2026-07-05T08:00:00-04:00"
        ]
        if resetStore {
            arguments.append("--reset-db")
        }
        if let initialTab {
            arguments.append("--initial-tab=\(initialTab)")
        }
        return launchUITestApp(extraArguments: arguments, useInMemoryStore: true)
    }
}
