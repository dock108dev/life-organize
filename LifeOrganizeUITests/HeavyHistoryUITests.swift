import XCTest

extension LifeOrganizeScenarioUITests {
    func testSeedScrollsTimelineWithinTimeout() throws {
        executionTimeAllowance = 45
        let walkthroughStart = CFAbsoluteTimeGetCurrent()
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-use-fake-extractor",
            "-disable-animations",
            "-reset-store",
            "-reset-device-token",
            "-use-in-memory-store",
            "-skip-launch-maintenance",
            "-fixed-now=2026-05-21T12:00:00-04:00",
            "--seed-scenario=heavy_history"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
        let feed = app.descendants(matching: .any)["timeline-feed"]
        XCTAssertTrue(feed.waitForFastExistence(timeout: 10))
        let timelineRows = app.descendants(matching: .any).matching(identifierPrefix: "timeline-row-")
        XCTAssertTrue(timelineRows.firstMatch.waitForFastExistence(timeout: 10))
        for _ in 0..<2 {
            feed.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(timelineRows.firstMatch.exists)
        attachScreenshot(named: "heavy_timeline", from: app)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - walkthroughStart, 35)
    }
}
