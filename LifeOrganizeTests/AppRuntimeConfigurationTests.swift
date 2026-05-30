import SwiftData
import XCTest
@testable import LifeOrganize

final class AppRuntimeConfigurationTests: XCTestCase {
    func testParsesExistingAndDeterministicLaunchArguments() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-reset-store",
            "-reset-device-token",
            "-use-fake-extractor",
            "-fixed-now=2027-01-15T08:00:00-05:00",
            "-screenshot-mode",
            "-initial-tab=things",
            "-seed-scenario=first_launch_empty",
            "-seed-scenario=car_maintenance"
        ])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertTrue(configuration.isAutomationRuntime)
        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetDeviceToken)
        XCTAssertTrue(configuration.usesDeterministicExtractor)
        XCTAssertTrue(configuration.isScreenshotMode)
        XCTAssertNotNil(configuration.fixedNow)
        XCTAssertEqual(configuration.initialTab, .things)
        XCTAssertEqual(configuration.seedScenarioIDs, ["first_launch_empty", "car_maintenance"])
    }

    func testResetStoreAndDeviceTokenUseCurrentAutomationFlags() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-reset-store",
            "-reset-device-token"
        ])

        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetDeviceToken)
    }

    func testLegacyRuntimeAliasesAreAbsentFromRuntimeConfiguration() throws {
        let legacyArguments = [
            "--" + "reset-db",
            "--" + "use-in-memory-store",
            "--" + "skip-launch-maintenance",
            "--" + "initial-tab=things",
            "--" + "seed-scenario=car_maintenance",
            "--" + "ai-service-base-url=https://staging.example.invalid"
        ]
        let configuration = AppRuntimeConfiguration(arguments: ["LifeOrganize", "-ui-testing"] + legacyArguments)

        XCTAssertFalse(configuration.shouldResetStore)
        XCTAssertFalse(configuration.shouldResetDeviceToken)
        XCTAssertFalse(configuration.shouldSkipLaunchMaintenance)
        XCTAssertEqual(configuration.initialTab, nil)
        XCTAssertEqual(configuration.seedScenarioIDs, [])
        XCTAssertEqual(configuration.aiServiceBaseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
        if case .store = configuration.modelContainer() {
        } else {
            XCTFail("Legacy in-memory alias must not select the in-memory automation store.")
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LifeOrganize/Utilities/AppRuntimeConfiguration.swift")
        let source = try String(contentsOf: sourceURL)
        for legacyArgument in legacyArguments.map({ $0.components(separatedBy: "=")[0] }) {
            XCTAssertFalse(source.contains("\"\(legacyArgument)"))
        }
    }

    func testDogContinuitySeedAliasSelectsOperationalHomeScenario() throws {
        let scenario = try XCTUnwrap(SeedScenario(argumentValue: "dog_continuity"))

        XCTAssertEqual(scenario.fixtureID, "operational_home")
    }

    func testDestructiveResetArgumentsDoNotSelectProductionStoreWithoutUITesting() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-reset-store",
            "-seed-scenario=first-run-empty"
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
            "-screenshot-mode"
        ])

        XCTAssertTrue(configuration.isAutomationRuntime)
        if case .store = configuration.modelContainer() {
            XCTAssertTrue(configuration.shouldResetStore)
        } else {
            XCTFail("Screenshot mode must use isolated automation storage.")
        }
    }

    func testScreenshotModeDerivesDeterministicDefaultsWithoutLegacyFlags() throws {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode"
        ])

        XCTAssertTrue(configuration.isUITesting)
        XCTAssertTrue(configuration.usesDeterministicExtractor)
        XCTAssertTrue(configuration.shouldResetStore)
        XCTAssertTrue(configuration.shouldResetDeviceToken)
        XCTAssertTrue(configuration.disablesAnimations)
        XCTAssertEqual(configuration.seedScenarioIDs, ["operational_home"])
        XCTAssertEqual(configuration.initialTab, nil)
        XCTAssertNotNil(configuration.fixedNow)
        XCTAssertNil(try configuration.deviceTokenStore().loadDeviceToken())
    }

    func testScreenshotModeParsesScenarioPresentationAndRouteArguments() throws {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "-screenshot-seed=search",
            "-screenshot-start=search",
            "-screenshot-search-query=oil",
            "-screenshot-locale=en_US",
            "-screenshot-time-zone=America/New_York",
            "-screenshot-calendar=gregorian",
            "-screenshot-appearance=dark"
        ])

        XCTAssertEqual(configuration.seedScenarioIDs, ["timeline_search"])
        XCTAssertEqual(configuration.initialTab, .log)
        XCTAssertEqual(configuration.initialSection, .search)
        XCTAssertEqual(configuration.initialSheet, .search)
        XCTAssertEqual(configuration.screenshotSearchQuery, "oil")
        XCTAssertEqual(configuration.screenshotLocale?.identifier, "en_US")
        XCTAssertEqual(configuration.screenshotTimeZone?.identifier, "America/New_York")
        XCTAssertEqual(configuration.screenshotCalendar?.identifier, .gregorian)
        XCTAssertEqual(configuration.screenshotCalendar?.timeZone.identifier, "America/New_York")
        XCTAssertEqual(configuration.screenshotAppearance, .dark)
        XCTAssertNil(try configuration.deviceTokenStore().loadDeviceToken())
    }

    func testScreenshotStartsResolveToRootSectionsForAdaptiveShells() {
        let cases: [(String, AppSection, AppInitialSheet?)] = [
            ("timeline", .timeline, nil),
            ("things", .things, nil),
            ("carry-forward", .carryForward, nil),
            ("search", .search, .search),
            ("review", .review, .reviewQueue),
            ("settings", .settings, .settings)
        ]

        for (start, expectedSection, expectedSheet) in cases {
            let configuration = AppRuntimeConfiguration(arguments: [
                "LifeOrganize",
                "-screenshot-mode",
                "-screenshot-start=\(start)"
            ])

            XCTAssertEqual(configuration.initialSection, expectedSection)
            XCTAssertEqual(configuration.initialSheet, expectedSheet)
        }
    }

    func testExplicitInitialTabCanStillCombineWithScreenshotUtilityStart() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "-initial-tab=things",
            "-screenshot-start=search"
        ])

        XCTAssertEqual(configuration.initialTab, .things)
        XCTAssertEqual(configuration.initialSection, .search)
        XCTAssertEqual(configuration.initialSheet, .search)
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
            "-skip-launch-maintenance"
        ])

        XCTAssertTrue(configuration.shouldSkipLaunchMaintenance)
        if case .inMemory = configuration.modelContainer() {
            XCTAssertTrue(configuration.isAutomationRuntime)
        } else {
            XCTFail("In-memory store flag should select an in-memory automation container.")
        }
    }

    func testResetDeviceTokenClearsAutomationDefaults() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-reset-device-token"
        ])
        let defaults = configuration.userDefaults()
        defaults.set(true, forKey: AppDefaultsKeys.developerModeUnlocked)

        configuration.resetLaunchStateIfNeeded(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.developerModeUnlocked))
    }

    func testScreenshotModeSeedsDismissedTimelineAndThingsContextPanelsInAutomationDefaults() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "-use-in-memory-store"
        ])
        let defaults = configuration.userDefaults()
        defaults.removePersistentDomain(forName: "LifeOrganize.Automation")

        configuration.resetLaunchStateIfNeeded(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.timelineContextDismissed))
        XCTAssertTrue(defaults.bool(forKey: AppDefaultsKeys.thingsContextDismissed))
        XCTAssertFalse(defaults.bool(forKey: AppDefaultsKeys.rulesContextDismissed))
    }

    func testScreenshotModeAppliesTimeZoneOverrideForCurrentFormatters() {
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-screenshot-mode",
            "-screenshot-time-zone=America/New_York"
        ])

        configuration.applyProcessEnvironmentOverrides()

        XCTAssertEqual(TimeZone.current.identifier, "America/New_York")
    }

    func testDeveloperModeUnlockArgumentIsAutomationOnly() {
        let automationConfiguration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-enable-developer-mode",
            "-unlock-developer-mode"
        ])
        let productionConfiguration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-enable-developer-mode",
            "-unlock-developer-mode"
        ])

        XCTAssertTrue(automationConfiguration.unlocksDeveloperMode)
        XCTAssertFalse(productionConfiguration.unlocksDeveloperMode)
    }

    func testAutomationCanDisableDeveloperModeForProductionLikeCoverage() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-enable-developer-mode",
            "-unlock-developer-mode",
            "-disable-developer-mode"
        ])

        XCTAssertTrue(configuration.isAutomationRuntime)
        XCTAssertTrue(configuration.disablesDeveloperMode)
        XCTAssertFalse(configuration.unlocksDeveloperMode)
        XCTAssertFalse(configuration.isDeveloperModeAvailable)
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
