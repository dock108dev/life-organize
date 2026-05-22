import XCTest

extension LifeOrganizeUITests {
    func dismissPresentedSearch(in app: XCUIApplication) {
        if let closeButton = visibleSearchCloseButton(in: app) {
            closeButton.tap()
            XCTAssertTrue(waitForSearchDismissal(in: app))
            return
        }

        dismissActiveSearchField(in: app)
        if let closeButton = visibleSearchCloseButton(in: app, timeout: 2) {
            closeButton.tap()
            XCTAssertTrue(waitForSearchDismissal(in: app))
            return
        }

        app.swipeDown()
        XCTAssertTrue(waitForSearchDismissal(in: app))
    }

    private func visibleSearchCloseButton(in app: XCUIApplication, timeout: TimeInterval = 0) -> XCUIElement? {
        let candidates = [
            app.buttons["search-done-button"],
            app.navigationBars["Search"].buttons["Done"],
            app.buttons["Done"]
        ]
        return candidates.first { button in
            timeout > 0 ? button.waitForFastExistence(timeout: timeout) : button.exists
        }
    }

    private func dismissActiveSearchField(in app: XCUIApplication) {
        let searchModeControls = [
            app.buttons["Cancel"],
            app.buttons["Close"]
        ]
        guard let button = searchModeControls.first(where: { $0.exists }) else { return }
        button.tap()
    }

    private func waitForSearchDismissal(in app: XCUIApplication) -> Bool {
        let gonePredicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gonePredicate, object: app.navigationBars["Search"])
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }
}
