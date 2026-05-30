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
        XCTAssertTrue(app.staticTexts["Capture anything worth remembering. LifeOrganize turns it into history, Things, and follow-up reminders."].exists)
        XCTAssertTrue(app.buttons["Save note"].exists)
        XCTAssertTrue(app.buttons["Ask today"].exists)
        XCTAssertTrue(app.buttons["Set reminder"].exists)
        XCTAssertTrue(app.buttons["Log something"].exists)
        XCTAssertTrue(app.buttons["settings-entry"].exists)
        XCTAssertTrue(app.buttons["root-search-entry"].exists)

        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertEqual(input.placeholderValue, "Add anything or ask what’s due")
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
        XCTAssertTrue(app.buttons["settings-export-button"].exists)
        XCTAssertTrue(app.buttons["settings-clear-data-button"].exists)
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

    func testProductionLikeSettingsHidesDiagnosticsDespiteStaleUnlockAndFooterGesture() throws {
        let unlockedApp = launchUITestApp(
            extraArguments: [
                "-enable-developer-mode",
                "-unlock-developer-mode"
            ],
            useInMemoryStore: true
        )
        unlockedApp.buttons["settings-entry"].tap()
        XCTAssertTrue(unlockedApp.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(unlockedApp.staticTexts["Developer Diagnostics"].waitForFastExistence(timeout: 5))
        unlockedApp.terminate()

        let productionLikeApp = launchUITestApp(
            extraArguments: [
                "-disable-developer-mode"
            ],
            useInMemoryStore: true
        )
        productionLikeApp.buttons["settings-entry"].tap()
        XCTAssertTrue(productionLikeApp.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(productionLikeApp.staticTexts["device-token-status"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(productionLikeApp.buttons["settings-export-button"].exists)
        XCTAssertTrue(productionLikeApp.buttons["settings-clear-data-button"].exists)
        assertDeveloperDiagnosticsHidden(in: productionLikeApp)

        let footer = productionLikeApp.staticTexts["settings-version-footer"]
        if !footer.waitForFastExistence(timeout: 1) {
            productionLikeApp.swipeUp()
        }
        XCTAssertTrue(footer.waitForFastExistence(timeout: 5))
        footer.tap()
        footer.press(forDuration: 1.1)

        assertDeveloperDiagnosticsHidden(in: productionLikeApp)
    }

    func testTimelineComposerStaysReadableDuringFocusedDraftEntry() throws {
        let app = launchUITestApp(extraArguments: ["--reset-db"], useInMemoryStore: true)

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save note"].exists)
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.waitForFastExistence(timeout: 5))
        if app.frame.width >= 760 {
            XCTAssertLessThanOrEqual(input.frame.width, 620)
            XCTAssertGreaterThan(input.frame.minX, 40)
            XCTAssertLessThan(input.frame.maxX, app.frame.maxX - 40)
        }

        input.tap()
        input.typeText("Draft while the keyboard is open")

        XCTAssertFalse(app.buttons["Save note"].exists)
        XCTAssertTrue(input.exists)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        }
    }
}
