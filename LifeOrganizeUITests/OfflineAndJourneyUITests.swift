import XCTest

final class LifeOrganizeOfflineJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBackendUnavailableSendStaysLocalAndOpensRecoveryReview() throws {
        let app = launchUITestApp(
            extraArguments: [
                "-simulate-ai-service-error=network-unavailable",
                "--reset-db"
            ],
            useInMemoryStore: true
        )

        XCTAssertTrue(app.navigationBars["Timeline"].waitForFastExistence(timeout: 5))
        send("Changed furnace filter today.", in: app)

        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Changed furnace filter today.").firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "sk-").firstMatch.exists)

        XCTAssertTrue(app.buttons["review-queue-button"].waitForFastExistence(timeout: 5))
        app.buttons["review-queue-button"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-list"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(labelContaining: "Entry recovery is available").firstMatch.waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(labelContaining: "Retry Now").firstMatch.waitForFastExistence(timeout: 5))

        let reviewRow = app.buttons.matching(identifierPrefix: "review-queue-row-").firstMatch
        XCTAssertTrue(reviewRow.waitForFastExistence(timeout: 5))
        reviewRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review-queue-accept-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review-queue-dismiss-button"].exists)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Changed furnace filter today.").firstMatch.exists)
    }

    func testPendingTokenRecoveryKeepsSettingsAndReviewActionsReachable() throws {
        let app = launchUITestApp(
            extraArguments: [
                "-simulate-ai-service-error=missing-token",
                "--reset-db"
            ],
            useInMemoryStore: true
        )

        send("Replace filter in 2 months.", in: app)
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Replace filter in 2 months.").firstMatch.waitForFastExistence(timeout: 5))

        app.buttons["settings-entry"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI service"].exists)
        XCTAssertTrue(app.staticTexts["device-token-status"].exists)
        app.buttons["settings-done-button"].tap()

        XCTAssertTrue(app.buttons["review-queue-button"].waitForFastExistence(timeout: 5))
        app.buttons["review-queue-button"].tap()
        let reviewRow = app.buttons.matching(identifierPrefix: "review-queue-row-").firstMatch
        XCTAssertTrue(reviewRow.waitForFastExistence(timeout: 5))
        reviewRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["review-queue-detail"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review-queue-accept-button"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review-queue-dismiss-button"].exists)
    }

    func testDeveloperDiagnosticsAndInternalQADoNotExposeProviderSecrets() throws {
        let app = launchUITestApp(
            extraArguments: [
                "-enable-developer-mode",
                "--reset-db",
                "--seed-scenario=ambiguous_dog_grooming"
            ],
            useInMemoryStore: true
        )

        app.buttons["settings-entry"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForFastExistence(timeout: 5))
        unlockDeveloperMode(in: app)

        XCTAssertTrue(app.staticTexts["Developer Diagnostics"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Extraction Attempts"].exists)
        XCTAssertTrue(app.buttons["Failed Extractions"].exists)
        XCTAssertTrue(app.buttons["Internal QA Lab"].exists)
        assertNoProviderSecretsVisible(in: app)

        app.buttons["Internal QA Lab"].tap()
        XCTAssertTrue(app.navigationBars["Internal QA Lab"].waitForFastExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Load Fixtures"].exists)
        XCTAssertTrue(app.buttons["Reset Local Database"].exists)
        XCTAssertTrue(app.buttons["Extraction Quality Dashboard"].exists)
        assertNoProviderSecretsVisible(in: app)
    }

    func testThingsAndCarryForwardSupportDetailEditAndDelete() throws {
        let app = launchOperationalHomeSeedOnThings()

        XCTAssertTrue(app.navigationBars["Things"].waitForFastExistence(timeout: 5))
        let thingRow = app.buttons.containing(.staticText, identifier: "Home Air Filters").firstMatch
        XCTAssertTrue(thingRow.waitForFastExistence(timeout: 10))
        thingRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Thing"].waitForFastExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 5))
        app.navigationBars["Home Air Filters"].buttons["Things"].tap()

        tapTab("Carry Forward", in: app)
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))
        let ruleRow = app.buttons.matching(identifierPrefix: "carry-forward-row-").firstMatch
        XCTAssertTrue(ruleRow.waitForFastExistence(timeout: 10))
        ruleRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["carry-forward-detail"].waitForFastExistence(timeout: 5))
        app.buttons["Reminder Actions"].tap()
        app.buttons["Edit Reminder"].tap()
        XCTAssertTrue(app.navigationBars["Edit Reminder"].waitForFastExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["carry-forward-detail"].waitForFastExistence(timeout: 5))
        app.buttons["Reminder Actions"].tap()
        app.buttons["Delete Reminder"].tap()
        app.buttons["Delete Reminder"].tap()
        XCTAssertTrue(app.navigationBars["Carry Forward"].waitForFastExistence(timeout: 5))
        app.terminate()

        let deletionApp = launchOperationalHomeSeedOnThings()
        let updatedThingRow = deletionApp.buttons.containing(.staticText, identifier: "Home Air Filters").firstMatch
        XCTAssertTrue(updatedThingRow.waitForFastExistence(timeout: 5))
        updatedThingRow.tap()
        XCTAssertTrue(deletionApp.descendants(matching: .any)["thing-detail"].waitForFastExistence(timeout: 5))
        deletionApp.buttons["More"].tap()
        deletionApp.buttons["Delete Thing"].tap()
        deletionApp.buttons["Delete and Unlink Records"].tap()
    }

    private func launchOperationalHomeSeedOnThings() -> XCUIApplication {
        launchUITestApp(
            extraArguments: [
                "--reset-db",
                "--seed-scenario=operational_home",
                "-fixed-now=2026-07-05T08:00:00-04:00",
                "--initial-tab=things"
            ],
            useInMemoryStore: true
        )
    }

    private func unlockDeveloperMode(in app: XCUIApplication) {
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "LifeOrganize ")).firstMatch
        for _ in 0..<4 where !footer.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(footer.waitForFastExistence(timeout: 5))
        footer.press(forDuration: 1.2)
    }

    private func assertNoProviderSecretsVisible(in app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "OPENAI_API_KEY").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "api.openai.com").firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(labelContaining: "sk-").firstMatch.exists)
    }
}
