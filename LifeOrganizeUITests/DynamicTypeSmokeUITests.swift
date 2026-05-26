import XCTest

final class DynamicTypeSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNormalTextSizeCoreControlsStayReachable() throws {
        runCoreSurfaceSmoke(at: .normal)
    }

    func testLargeTextSizeCoreControlsStayReachable() throws {
        runCoreSurfaceSmoke(at: .large)
    }

    func testAccessibilityLargeTextSizeCoreControlsStayReachable() throws {
        runCoreSurfaceSmoke(at: .accessibilityLarge)
    }

    func testAccessibilityXXXLTextSizeCoreControlsStayReachable() throws {
        runCoreSurfaceSmoke(at: .accessibilityXXXL)
    }

    private func runCoreSurfaceSmoke(at size: DynamicTypeSmokeSize) {
        let app = launchUITestApp(
            extraArguments: size.launchArguments + [
                "--reset-db",
                "--seed-scenario=ambiguous_dog_grooming",
                "-fixed-now=2026-05-20T08:00:00-04:00"
            ],
            resetDeviceToken: true,
            useInMemoryStore: true
        )

        assertTimelineControlsReachable(in: app)
        assertThingsListAndDetailReachable(in: app)
        assertSettingsTokenControlsReachable(in: app)
        assertReviewQueueDetailAndActionsReachable(in: app)
    }

    private func assertTimelineControlsReachable(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].waitForFastExistence(timeout: 10))

        let input = app.textFields["chat-input"]
        assertReachable(input, in: app)
        input.tap()
        input.typeText("Changed oil today.")

        let sendButton = app.buttons["chat-send-button"]
        assertReachable(sendButton, in: app)
        XCTAssertTrue(sendButton.waitForEnabled(timeout: 5))
        sendButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        dismissKeyboardIfVisible(in: app)
    }

    private func assertThingsListAndDetailReachable(in app: XCUIApplication) {
        tapTab("Things", in: app)
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["things-list"].waitForFastExistence(timeout: 10))

        let thingsList = app.descendants(matching: .any)["things-list"]
        let thingRow = firstReachableButton(identifierPrefix: "thing-row-", in: app, scrollView: thingsList)
        thingRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 10))

        let backButton = app.navigationBars.buttons["Things"]
        XCTAssertTrue(backButton.waitForFastExistence(timeout: 5))
        backButton.tap()
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 5))
    }

    private func assertSettingsTokenControlsReachable(in app: XCUIApplication) {
        tapTab("Timeline", in: app)

        let settingsButton = app.buttons["settings-entry"]
        assertReachable(settingsButton, in: app)
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 10))

        let tokenStatus = app.staticTexts["device-token-status"]
        XCTAssertTrue(tokenStatus.waitForFastExistence(timeout: 10))

        XCTAssertTrue(app.buttons["device-token-save-button"].waitForFastExistence(timeout: 10))
        let tokenActionButton = firstUsableButton(
            matching: app.buttons.matching(NSPredicate(format: "label IN %@", ["Prepare Service", "Refresh Token"]))
        )
        assertReachable(tokenActionButton, in: app)

        let doneButton = app.buttons["settings-done-button"]
        assertReachable(doneButton, in: app)
        doneButton.tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 10))
    }

    private func assertReviewQueueDetailAndActionsReachable(in app: XCUIApplication) {
        let reviewButton = app.buttons["review-queue-button"]
        assertReachable(reviewButton, in: app)
        reviewButton.tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForFastExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 10))

        let reviewRow = app.buttons.matching(identifierPrefix: "review-queue-row-").firstMatch
        assertReachable(reviewRow, in: app, scrollView: app.scrollViews.firstMatch)
        reviewRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 10))

        _ = firstExistingElement(in: [
            app.buttons["review-queue-accept-button"],
            app.buttons["review-queue-edit-button"],
            app.buttons["review-queue-blocked-action"]
        ])
        let dismissButton = app.buttons["review-queue-dismiss-button"]
        let reviewDetail = app.descendants(matching: .any)["review-queue-detail"]
        assertReachable(dismissButton, in: app, scrollView: reviewDetail)
    }

    private func firstExistingElement(in elements: [XCUIElement]) -> XCUIElement {
        for element in elements where element.waitForFastExistence(timeout: 2) {
            return element
        }
        return elements[0]
    }

    private func firstReachableButton(
        identifierPrefix: String,
        in app: XCUIApplication,
        scrollView: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let query = app.buttons.matching(identifierPrefix: identifierPrefix)
        let scrollTarget = scrollView.hasUsableFrame ? scrollView : app
        for _ in 0..<5 {
            let button = query.firstMatch
            if button.exists {
                assertReachable(button, in: app, scrollView: scrollTarget, file: file, line: line)
                return button
            }
            scrollTarget.swipeUp()
        }
        let button = query.firstMatch
        XCTAssertTrue(button.waitForFastExistence(timeout: 5), file: file, line: line)
        assertReachable(button, in: app, scrollView: scrollTarget, file: file, line: line)
        return button
    }

    private func firstUsableButton(matching query: XCUIElementQuery) -> XCUIElement {
        XCTAssertTrue(query.firstMatch.waitForFastExistence(timeout: 10))
        return query.allElementsBoundByIndex.first(where: \.isHittable)
            ?? query.allElementsBoundByIndex.first(where: \.hasUsableFrame)
            ?? query.firstMatch
    }

    private func assertReachable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        scrollView: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForFastExistence(timeout: 10), file: file, line: line)
        guard !element.isHittable else { return }

        let candidateScrollTarget = scrollView ?? app.scrollViews.firstMatch
        guard candidateScrollTarget.exists else {
            XCTFail("Element exists but is not hittable: \(element)", file: file, line: line)
            return
        }

        let scrollTarget = candidateScrollTarget.hasUsableFrame ? candidateScrollTarget : app
        for _ in 0..<4 where !element.isHittable {
            scrollTarget.swipeUp()
        }
        for _ in 0..<2 where !element.isHittable {
            scrollTarget.swipeDown()
        }

        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
}

private extension XCUIElement {
    var hasUsableFrame: Bool {
        !frame.isEmpty && frame.width > 1 && frame.height > 1
    }
}

private enum DynamicTypeSmokeSize {
    case normal
    case large
    case accessibilityLarge
    case accessibilityXXXL

    var launchArguments: [String] {
        [
            "-UIPreferredContentSizeCategoryName",
            uiContentSizeCategoryName
        ]
    }

    private var uiContentSizeCategoryName: String {
        switch self {
        case .normal:
            return "UICTContentSizeCategoryM"
        case .large:
            return "UICTContentSizeCategoryL"
        case .accessibilityLarge:
            return "UICTContentSizeCategoryAccessibilityL"
        case .accessibilityXXXL:
            return "UICTContentSizeCategoryAccessibilityXXXL"
        }
    }
}
