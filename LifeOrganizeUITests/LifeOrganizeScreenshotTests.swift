import XCTest

extension LifeOrganizeScenarioUITests {
    func testFirstLaunchAndEmptyTimelineScreenshots() throws {
        let app = launchScreenshotApp(seed: "empty", start: "timeline")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["device-token-notice"].exists)
        XCTAssertTrue(app.buttons["Log something"].exists)
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "timeline-row-").firstMatch.exists)

        capture("first_launch", from: app)
        capture("timeline_empty", from: app)
    }

    func testTimelineScreenshot() throws {
        let app = launchScreenshotApp(seed: "default", start: "timeline")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Replaced Home Air Filters").firstMatch.exists)

        capture("timeline", from: app)
    }

    func testThingsAndThingDetailScreenshots() throws {
        let app = launchScreenshotApp(seed: "default", start: "things")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["things-list"].waitForFastExistence(timeout: 10))
        let filtersRow = app.buttons.containing(.staticText, identifier: "Home Air Filters").firstMatch
        XCTAssertTrue(filtersRow.waitForFastExistence(timeout: 10))

        capture("things", from: app)

        filtersRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Home Air Filters"].waitForFastExistence(timeout: 10))

        capture("thing_detail", from: app)
    }

    func testCarryForwardScreenshot() throws {
        let app = launchScreenshotApp(seed: "carry-forward", start: "carry-forward")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["carry-forward-list"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Replace Home Air Filters").firstMatch.exists)

        capture("carry_forward", from: app)
    }

    func testSearchScreenshot() throws {
        let app = launchScreenshotApp(seed: "search", start: "search", searchQuery: "registration renewal")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Search"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.searchFields.firstMatch.waitForFastExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifierPrefix: "ledger-search-result-")
                .firstMatch
                .waitForFastExistence(timeout: 10)
        )
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        capture("search", from: app)
    }

    func testReviewQueueScreenshot() throws {
        let app = launchScreenshotApp(seed: "review", start: "review")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Review"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifierPrefix: "review-queue-row-").firstMatch.exists)

        capture("review_queue", from: app)
    }

    func testHeavyTimelineScreenshot() throws {
        let app = launchScreenshotApp(seed: "heavy", start: "timeline", fixedNow: "2026-05-21T12:00:00-04:00")
        waitUntilReady(in: app)
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
        let feed = app.descendants(matching: .any)["timeline-feed"]
        XCTAssertTrue(feed.waitForFastExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifierPrefix: "timeline-row-")
                .firstMatch
                .waitForFastExistence(timeout: 10)
        )

        capture("heavy_timeline", from: app)
    }

    private func launchScreenshotApp(
        seed: String,
        start: String,
        searchQuery: String? = nil,
        fixedNow: String = "2027-01-15T08:00:00-05:00"
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshot-mode",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-fixed-now=\(fixedNow)",
            "-screenshot-seed=\(seed)",
            "-screenshot-start=\(start)",
            "-screenshot-locale=en_US",
            "-screenshot-time-zone=America/New_York",
            "-screenshot-calendar=gregorian",
            "-screenshot-appearance=light",
            "-use-in-memory-store",
            "-skip-launch-maintenance"
        ]
        if let searchQuery {
            app.launchArguments.append("-screenshot-search-query=\(searchQuery)")
        }
        app.launch()
        return app
    }

    private func waitUntilReady(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot-ready"].waitForFastExistence(timeout: 6),
            file: file,
            line: line
        )
    }

    private func capture(_ name: String, from app: XCUIApplication) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "screenshot__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
