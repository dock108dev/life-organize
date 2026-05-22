import XCTest

extension LifeOrganizeScenarioUITests {
    func testDeterministicLaunchAliasesReachFirstRun() throws {
        let app = launchScreenshotApp(
            extraArguments: [
                "--reset-db",
                "--seed-scenario=first-run-empty"
            ]
        )

        XCTAssertTrue(app.staticTexts["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["device-token-notice"].exists)
    }

    func testScreenshotModeRepeatedLaunchesReachSameFirstVisibleState() throws {
        let arguments = [
            "-screenshot-seed=default",
            "-screenshot-start=things",
            "-screenshot-locale=en_US",
            "-screenshot-time-zone=America/New_York",
            "-screenshot-calendar=gregorian",
            "-screenshot-appearance=light",
            "-fixed-now=2027-01-15T08:00:00-05:00"
        ]
        let firstApp = launchScreenshotApp(extraArguments: arguments)
        assertScreenshotThingsState(in: firstApp)
        firstApp.terminate()

        let secondApp = launchScreenshotApp(extraArguments: arguments)
        assertScreenshotThingsState(in: secondApp)
    }

    private func launchScreenshotApp(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshot-mode",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-use-in-memory-store"
        ]
        app.launchArguments.append(contentsOf: extraArguments)
        app.launch()
        return app
    }

    private func assertScreenshotThingsState(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot-ready"].waitForFastExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertTrue(app.navigationBars["Things"].exists, file: file, line: line)
        XCTAssertTrue(app.tabBars.buttons["Things"].isSelected, file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)["things-list"].exists, file: file, line: line)
        XCTAssertTrue(
            app.staticTexts.matching(labelContaining: "Home Air Filters").firstMatch.exists,
            file: file,
            line: line
        )
        XCTAssertFalse(app.keyboards.firstMatch.exists, file: file, line: line)
    }
}
