import SwiftData
import XCTest
@testable import LifeOrganize

final class AppRuntimeConfigurationTests: XCTestCase {
    func testParsesExistingAndDeterministicLaunchArguments() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-reset-store",
            "-reset-api-key",
            "-use-fake-extractor",
            "-fixed-now=2027-01-15T08:00:00-05:00",
            "-screenshot-mode",
            "--initial-tab=things",
            "-seed-scenario=first_launch_empty",
            "--seed-scenario=car_maintenance",
        ])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertTrue(configuration.isAutomationRuntime)
        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetAPIKey)
        XCTAssertTrue(configuration.usesDeterministicExtractor)
        XCTAssertTrue(configuration.isScreenshotMode)
        XCTAssertNotNil(configuration.fixedNow)
        XCTAssertEqual(configuration.initialTab, .things)
        XCTAssertEqual(configuration.seedScenarioIDs, ["first_launch_empty", "car_maintenance"])
    }

    func testResetDatabaseAliasRequestsFreshInstallStateWithoutRequiringLegacyResetFlags() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "--reset-db",
        ])

        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetAPIKey)
        XCTAssertTrue(configuration.requestsFreshInstallReset)
    }

    func testDogContinuitySeedAliasSelectsOperationalHomeScenario() throws {
        let scenario = try XCTUnwrap(SeedScenario(argumentValue: "dog_continuity"))

        XCTAssertEqual(scenario.fixtureID, "operational_home")
    }

    func testDestructiveResetArgumentsDoNotSelectProductionStoreWithoutUITesting() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "--reset-db",
            "--seed-scenario=first-run-empty",
        ])

        if case .standard = configuration.modelContainer() {
            XCTAssertFalse(configuration.isUITesting)
        } else {
            XCTFail("Reset aliases without UI testing must not select an automation store.")
        }
    }

    func testScreenshotModeUsesAutomationStoreWithoutLegacyUITestingFlag() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "--reset-db",
        ])

        XCTAssertTrue(configuration.isAutomationRuntime)
        if case .store = configuration.modelContainer() {
            XCTAssertTrue(configuration.requestsFreshInstallReset)
        } else {
            XCTFail("Screenshot mode must use isolated automation storage.")
        }
    }

    func testScreenshotModeDerivesDeterministicDefaultsWithoutLegacyFlags() throws {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
        ])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertTrue(configuration.usesDeterministicExtractor)
        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetAPIKey)
        XCTAssertTrue(configuration.disablesAnimations)
        XCTAssertEqual(configuration.seedScenarioIDs, ["operational_home"])
        XCTAssertEqual(configuration.initialTab, nil)
        XCTAssertEqual(configuration.screenshotAPIKeyMode, .missing)
        XCTAssertNotNil(configuration.fixedNow)
        XCTAssertNil(try configuration.apiKeyStore().loadOpenAIAPIKey())
    }

    func testScreenshotModeParsesScenarioPresentationAndRouteArguments() throws {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "-screenshot-seed=search",
            "-screenshot-start=search",
            "-screenshot-search-query=oil",
            "-screenshot-api-key=present",
            "-screenshot-locale=en_US",
            "-screenshot-time-zone=America/New_York",
            "-screenshot-calendar=gregorian",
            "-screenshot-appearance=dark",
        ])

        XCTAssertEqual(configuration.seedScenarioIDs, ["timeline_search"])
        XCTAssertEqual(configuration.initialTab, .log)
        XCTAssertEqual(configuration.initialSheet, .search)
        XCTAssertEqual(configuration.screenshotSearchQuery, "oil")
        XCTAssertEqual(configuration.screenshotAPIKeyMode, .present)
        XCTAssertEqual(configuration.screenshotLocale?.identifier, "en_US")
        XCTAssertEqual(configuration.screenshotTimeZone?.identifier, "America/New_York")
        XCTAssertEqual(configuration.screenshotCalendar?.identifier, .gregorian)
        XCTAssertEqual(configuration.screenshotCalendar?.timeZone.identifier, "America/New_York")
        XCTAssertEqual(configuration.screenshotAppearance, .dark)
        XCTAssertEqual(try configuration.apiKeyStore().loadOpenAIAPIKey(), "sk-screenshot-key-1234")
    }

    func testScreenshotSeedCatalogCoversRequiredScenarioStates() {
        XCTAssertEqual(ScreenshotSeed.empty.seedScenarioIDs, ["first_launch_empty"])
        XCTAssertEqual(ScreenshotSeed.default.seedScenarioIDs, ["operational_home"])
        XCTAssertEqual(ScreenshotSeed.review.seedScenarioIDs, ["ambiguous_dog_grooming"])
        XCTAssertEqual(ScreenshotSeed.search.seedScenarioIDs, ["timeline_search"])
        XCTAssertEqual(ScreenshotSeed.carryForward.seedScenarioIDs, ["operational_home"])
        XCTAssertEqual(ScreenshotSeed.heavy.seedScenarioIDs, ["heavy_history"])
    }

    func testAutomationCanOptIntoInMemoryStoreForSingleLaunchScenarios() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-use-in-memory-store",
            "-skip-launch-maintenance",
        ])

        XCTAssertTrue(configuration.shouldSkipLaunchMaintenance)
        if case .inMemory = configuration.modelContainer() {
            XCTAssertTrue(configuration.isAutomationRuntime)
        } else {
            XCTFail("In-memory store flag should select an in-memory automation container.")
        }
    }

    func testFreshInstallResetClearsAutomationDefaults() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "--reset-db",
        ])
        let defaults = configuration.userDefaults()
        defaults.set(true, forKey: AppDefaultsKeys.developerModeUnlocked)

        configuration.resetLaunchStateIfNeeded(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.developerModeUnlocked))
    }

    @MainActor
    func testAutomationSeedScenariosLoadIdempotently() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)

        try SeedScenarioLoader.load(
            ["first_launch_empty", "car_maintenance", "ambiguous_dog_grooming"],
            into: container,
            isAutomationRuntime: true
        )
        try SeedScenarioLoader.load(
            ["car_maintenance", "ambiguous_dog_grooming"],
            into: container,
            isAutomationRuntime: true
        )

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityLink>()).count, 3)
    }

    @MainActor
    func testSeedScenariosAreIgnoredOutsideAutomationRuntime() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)

        try SeedScenarioLoader.load(
            ["car_maintenance"],
            into: container,
            isAutomationRuntime: false
        )

        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Thing>()).isEmpty)
    }

    @MainActor
    func testUnknownSeedScenarioFailsClearlyInAutomationRuntime() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)

        XCTAssertThrowsError(
            try SeedScenarioLoader.load(["missing_fixture"], into: container, isAutomationRuntime: true)
        ) { error in
            XCTAssertEqual(error as? SeedScenarioLoaderError, .unknownScenario("missing_fixture"))
        }
    }

    @MainActor
    func testFixtureBackedSeedFailureDoesNotPartiallyMutateStore() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(["car_maintenance"], into: container, isAutomationRuntime: true)

        let invalidFixture = try Self.fixtureData("car_maintenance")
            .replacingOccurrences(of: #""role": "user""#, with: #""role": "visitor""#)
        XCTAssertThrowsError(
            try SeedScenarioLoader.loadFixtureData(Data(invalidFixture.utf8), into: container)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("chatMessages.role has invalid value visitor"))
        }

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 1)
    }

    private static func fixtureData(_ id: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: "\(id).json")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
