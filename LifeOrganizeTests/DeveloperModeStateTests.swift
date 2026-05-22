import XCTest
@testable import LifeOrganize

@MainActor
final class DeveloperModeStateTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "DeveloperModeStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testUnavailableStateCannotUnlockDebugAccess() {
        let state = DeveloperModeState(isAvailable: false, defaults: defaults)

        state.unlock()

        XCTAssertFalse(state.policy.isDeveloperModeAvailable)
        XCTAssertFalse(state.policy.isDeveloperModeUnlocked)
        XCTAssertFalse(state.policy.allowsExtractionDebugScreens)
    }

    func testAvailableStateStartsLocked() {
        let state = DeveloperModeState(isAvailable: true, defaults: defaults)

        XCTAssertTrue(state.policy.isDeveloperModeAvailable)
        XCTAssertFalse(state.policy.isDeveloperModeUnlocked)
        XCTAssertFalse(state.policy.allowsExtractionDebugScreens)
    }

    func testUnlockPersistsDebugAccess() {
        let state = DeveloperModeState(isAvailable: true, defaults: defaults)

        state.unlock()
        let restoredState = DeveloperModeState(isAvailable: true, defaults: defaults)

        XCTAssertTrue(state.policy.allowsExtractionDebugScreens)
        XCTAssertTrue(restoredState.policy.allowsExtractionDebugScreens)
    }

    func testLockClearsDebugAccess() {
        let state = DeveloperModeState(isAvailable: true, defaults: defaults)
        state.unlock()

        state.lock()

        XCTAssertFalse(state.policy.isDeveloperModeUnlocked)
        XCTAssertFalse(state.policy.allowsExtractionDebugScreens)
    }

    func testLockedSettingsDoesNotShowDeveloperDiagnostics() {
        let lockedPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: false)
        let unlockedPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: true)

        XCTAssertFalse(SettingsView.showsDeveloperDiagnostics(for: lockedPolicy))
        XCTAssertTrue(SettingsView.showsDeveloperDiagnostics(for: unlockedPolicy))
    }

    func testExtractionDebugListShowsRequiredGateWhenLocked() {
        let lockedPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: false)
        let unavailablePolicy = DebugAccessPolicy.unavailable
        let unlockedPolicy = DebugAccessPolicy(isDeveloperModeAvailable: true, isDeveloperModeUnlocked: true)

        XCTAssertEqual(
            ExtractionDebugListView.accessPresentation(for: lockedPolicy),
            .requiredGate(.extractionDebug)
        )
        XCTAssertEqual(
            ExtractionDebugListView.accessPresentation(for: unavailablePolicy),
            .requiredGate(.extractionDebug)
        )
        XCTAssertEqual(ExtractionDebugListView.accessPresentation(for: unlockedPolicy), .attemptsList)
        XCTAssertEqual(DeveloperModeRequiredContent.extractionDebug.title, "Developer Mode Required")
        XCTAssertTrue(DeveloperModeRequiredContent.extractionDebug.description.contains("view diagnostics"))
    }

    func testRuntimeLaunchArgumentRequestsDeveloperModeForUITests() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-enable-developer-mode"
        ])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertTrue(configuration.enablesDeveloperMode)
        XCTAssertTrue(configuration.isDeveloperModeAvailable)
    }
}
