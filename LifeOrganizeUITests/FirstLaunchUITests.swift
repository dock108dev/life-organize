import XCTest

final class LifeOrganizeScenarioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchFreshInstallScenarioCoversEmptyTimelineAndFirstEntry() throws {
        let app = launchUITestApp(extraArguments: ["--reset-db"], useInMemoryStore: true)

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Timeline"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Things"].exists)
        XCTAssertTrue(app.tabBars.buttons["Carry Forward"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["timeline-feed"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["device-token-notice"].exists)
        XCTAssertTrue(app.staticTexts["Timeline"].exists)
        XCTAssertTrue(app.staticTexts["Type anything worth remembering. LifeOrganize will turn it into history, Things, and follow-up reminders."].exists)
        XCTAssertTrue(app.buttons["Save note"].exists)
        XCTAssertTrue(app.buttons["Ask today"].exists)
        XCTAssertTrue(app.buttons["Set reminder"].exists)
        XCTAssertTrue(app.buttons["Log something"].exists)
        XCTAssertTrue(app.buttons["settings-entry"].exists)
        XCTAssertTrue(app.buttons["root-search-entry"].exists)

        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertEqual(input.placeholderValue, "Ask what is due or add a note")
        let sendButton = app.buttons["chat-send-button"]
        XCTAssertTrue(sendButton.exists)
        XCTAssertFalse(sendButton.isEnabled)
        XCTAssertFalse(app.buttons["review-queue-button"].exists)
        assertNoTimelineRows(in: app)
        attachScreenshot(named: "first_launch", from: app)

        input.tap()
        input.typeText("   ")
        XCTAssertFalse(sendButton.isEnabled)
        sendButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertNoTimelineRows(in: app)
        XCTAssertFalse(app.buttons["review-queue-button"].exists)
        dismissKeyboardIfVisible(in: app)

        app.buttons["settings-entry"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI service"].exists)
        XCTAssertTrue(app.staticTexts["device-token-status"].exists)
        XCTAssertFalse(app.staticTexts["Developer Diagnostics"].exists)
        app.buttons["settings-done-button"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "No buying domains").firstMatch.exists)

        send("Changed oil today at Northstar Auto Bay.", in: app)
        XCTAssertTrue(
            app.buttons.matching(identifierPrefix: "timeline-row-event-").firstMatch.waitForFastExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "timeline-row-event-").count, 1)
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "timeline-row-rule-").firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "timeline-row-note-").firstMatch.exists)
        XCTAssertFalse(app.buttons["review-queue-button"].exists)

        tapTab("Things", in: app)
        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Oil Change").firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "thing-row-").count, 1)

        tapTab("Carry Forward", in: app)
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing to carry forward yet"].waitForFastExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch.exists)
    }
}
