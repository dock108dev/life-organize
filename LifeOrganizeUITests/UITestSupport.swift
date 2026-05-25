import XCTest

extension XCTestCase {
    func launchUITestApp(
        extraArguments: [String] = [],
        resetStore: Bool = false,
        resetDeviceToken: Bool = false,
        useInMemoryStore: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
            "-use-fake-extractor",
            "-disable-animations"
        ]
        if !extraArguments.contains(where: { $0.hasPrefix("-fixed-now=") }) {
            app.launchArguments.append("-fixed-now=2027-01-15T08:00:00-05:00")
        }
        if useInMemoryStore {
            app.launchArguments.append("-use-in-memory-store")
        }
        if let artifactsDir = ProcessInfo.processInfo.environment["LIFE_ORGANIZE_SCENARIO_ARTIFACTS_DIR"] {
            app.launchArguments.append("-scenario-artifacts-dir=\(artifactsDir)")
        }
        app.launchArguments.append(contentsOf: extraArguments)
        if resetStore {
            app.launchArguments.append("-reset-store")
        }
        if resetDeviceToken {
            app.launchArguments.append("-reset-device-token")
        }
        app.launch()
        return app
    }

    func tapTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForFastExistence(timeout: 5))
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func send(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.waitForFastExistence(timeout: 5))
        input.tap()
        input.typeText(text)
        let sendButton = app.buttons["chat-send-button"]
        XCTAssertTrue(sendButton.waitForFastExistence(timeout: 5))
        XCTAssertTrue(sendButton.waitForEnabled(timeout: 5))
        sendButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func attachScreenshot(named name: String, from app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        writeScenarioScreenshot(named: name, data: screenshot.pngRepresentation)
    }

    private func writeScenarioScreenshot(named name: String, data: Data) {
        guard let screenshotsDir = ProcessInfo.processInfo.environment["LIFE_ORGANIZE_SCENARIO_SCREENSHOTS_DIR"] else {
            return
        }
        let sanitizedName = name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        guard !sanitizedName.isEmpty else { return }
        let directory = URL(fileURLWithPath: screenshotsDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(sanitizedName).png"), options: [.atomic])
        } catch {
            XCTFail("Unable to write scenario screenshot \(sanitizedName): \(error.localizedDescription)")
        }
    }

    func dismissKeyboardIfVisible(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.swipeDown()
    }

    func assertNoTimelineRows(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifierPrefix: "timeline-row-").firstMatch.exists,
            file: file,
            line: line
        )
    }
}

extension XCUIElementQuery {
    func matching(labelContaining text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}

extension XCUIElement {
    func waitForFastExistence(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { $0.exists }
    }

    func waitForEnabled(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { $0.isEnabled }
    }

    private func waitUntil(timeout: TimeInterval, condition: (XCUIElement) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(self) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition(self)
    }
}
