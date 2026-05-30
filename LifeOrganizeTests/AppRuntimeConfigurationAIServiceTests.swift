import XCTest
@testable import LifeOrganize

final class AppRuntimeConfigurationAIServiceTests: XCTestCase {
    func testDefaultRuntimeUsesProductionAIServiceBaseURL() {
        let configuration = AppRuntimeConfiguration(arguments: ["LifeOrganize"])

        XCTAssertEqual(AppRuntimeConfiguration.defaultAIServiceBaseURL.absoluteString, "https://life.dock108.dev")
        XCTAssertEqual(configuration.aiServiceBaseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
    }

    func testAutomationModesUseProductionAIServiceBaseURLByDefault() {
        let launchArgumentSets = [
            ["LifeOrganize", "-ui-testing"],
            ["LifeOrganize", "-screenshot-mode"],
            ["LifeOrganize", "-ui-testing", "-use-in-memory-store"],
            ["LifeOrganize", "-ui-testing", "-use-fake-extractor"],
            ["LifeOrganize", "-ui-testing", "-skip-launch-maintenance"],
            ["LifeOrganize", "-ui-testing", "-enable-developer-mode"],
            ["LifeOrganize", "-screenshot-mode", "-screenshot-seed=search", "-screenshot-start=search"]
        ]

        for arguments in launchArgumentSets {
            let configuration = AppRuntimeConfiguration(arguments: arguments)

            XCTAssertEqual(
                configuration.aiServiceBaseURL,
                AppRuntimeConfiguration.defaultAIServiceBaseURL,
                "Expected production backend for arguments: \(arguments)"
            )
        }
    }

    func testAIServiceBaseURLLaunchArgumentsOverrideDefault() throws {
        let cases = [
            (
                ["LifeOrganize", "-ai-service-base-url=http://127.0.0.1:8787"],
                try XCTUnwrap(URL(string: "http://127.0.0.1:8787"))
            )
        ]

        for (arguments, expectedURL) in cases {
            let configuration = AppRuntimeConfiguration(arguments: arguments)

            XCTAssertEqual(configuration.aiServiceBaseURL, expectedURL)
        }
    }

    func testNonLoopbackHTTPAIServiceBaseURLFallsBackToProductionOutsideAutomation() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ai-service-base-url=http://staging.example.invalid"
        ])

        XCTAssertEqual(configuration.aiServiceBaseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
    }

    func testAutomationCanUseNonLoopbackHTTPAIServiceBaseURL() throws {
        let overrideURL = try XCTUnwrap(URL(string: "http://staging.example.invalid"))
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-ai-service-base-url=\(overrideURL.absoluteString)"
        ])

        XCTAssertEqual(configuration.aiServiceBaseURL, overrideURL)
    }

    func testExplicitAIServiceBaseURLOverrideWinsInAutomationRuntime() throws {
        let overrideURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8787"))
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-use-in-memory-store",
            "-ai-service-base-url=\(overrideURL.absoluteString)"
        ])

        XCTAssertTrue(configuration.isAutomationRuntime)
        XCTAssertEqual(configuration.aiServiceBaseURL, overrideURL)
    }

    func testInvalidAIServiceBaseURLLaunchArgumentsFallBackToProduction() {
        let launchArgumentSets = [
            ["LifeOrganize", "-ai-service-base-url="],
            ["LifeOrganize", "-ai-service-base-url=localhost:8787"],
            ["LifeOrganize", "-ai-service-base-url=ftp://127.0.0.1:8787"],
            ["LifeOrganize", "-ai-service-base-url=file:///tmp/backend"],
            ["LifeOrganize", "-ai-service-base-url=life.dock108.dev"]
        ]

        for arguments in launchArgumentSets {
            let configuration = AppRuntimeConfiguration(arguments: arguments)

            XCTAssertEqual(
                configuration.aiServiceBaseURL,
                AppRuntimeConfiguration.defaultAIServiceBaseURL,
                "Expected invalid override to fall back to production for arguments: \(arguments)"
            )
        }
    }

    func testInvalidRuntimeArgumentsAreVisibleAsConfigurationWarnings() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-ai-service-base-url=ftp://127.0.0.1:8787",
            "-fixed-now=not-a-date",
            "-screenshot-seed=missing",
            "-screenshot-time-zone=Not/AZone",
            "-screenshot-calendar=martian",
            "-screenshot-appearance=sepia",
            "-screenshot-start=elsewhere",
            "-simulate-ai-service-error=unknown"
        ])

        XCTAssertEqual(
            Set(configuration.configurationWarnings),
            [
                "ai_service_base_url_ignored",
                "fixed_now_ignored",
                "screenshot_seed_ignored",
                "screenshot_time_zone_ignored",
                "screenshot_calendar_ignored",
                "screenshot_appearance_ignored",
                "screenshot_start_ignored",
                "simulated_ai_service_error_ignored"
            ]
        )
    }

    @MainActor
    func testProductionDefaultsUseBackendClientsAndDefaultServiceURL() {
        let configuration = AppRuntimeConfiguration(arguments: ["LifeOrganize"])
        let tokenStore = InMemoryDeviceTokenStore(token: "test-token")

        XCTAssertFalse(configuration.isUITesting)
        XCTAssertFalse(configuration.isScreenshotMode)
        XCTAssertFalse(configuration.usesDeterministicExtractor)
        XCTAssertEqual(configuration.aiServiceBaseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
        XCTAssertTrue(configuration.messageExtractionClient(deviceTokenStore: tokenStore) is AIServiceMessageExtractionClient)
        XCTAssertTrue(configuration.webRequestClient(deviceTokenStore: tokenStore) is AIServiceWebRequestClient)
    }

    @MainActor
    func testFakeExtractorAutomationUsesDeterministicClientAndNoWebClient() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-use-fake-extractor"
        ])
        let tokenStore = InMemoryDeviceTokenStore(token: "test-token")

        XCTAssertTrue(configuration.isAutomationRuntime)
        XCTAssertTrue(configuration.usesDeterministicExtractor)
        XCTAssertEqual(configuration.aiServiceBaseURL, AppRuntimeConfiguration.defaultAIServiceBaseURL)
        XCTAssertTrue(configuration.messageExtractionClient(deviceTokenStore: tokenStore) is DeterministicMessageExtractionClient)
        XCTAssertNil(configuration.webRequestClient(deviceTokenStore: tokenStore))
    }

    @MainActor
    func testAutomationCanSimulateAIServiceFailureWithoutLiveClient() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-ui-testing",
            "-use-fake-extractor",
            "-simulate-ai-service-error=network-unavailable"
        ])
        let tokenStore = InMemoryDeviceTokenStore(token: "test-token")

        XCTAssertEqual(configuration.simulatedAIServiceError, .networkUnavailable)
        XCTAssertTrue(configuration.messageExtractionClient(deviceTokenStore: tokenStore) is SimulatedUnavailableMessageExtractionClient)
        XCTAssertTrue(configuration.webRequestClient(deviceTokenStore: tokenStore) is SimulatedUnavailableWebRequestClient)
    }

    @MainActor
    func testServiceFailureSimulationIsIgnoredOutsideAutomationRuntime() {
        let configuration = AppRuntimeConfiguration(arguments: [
            "LifeOrganize",
            "-simulate-ai-service-error=network-unavailable"
        ])
        let tokenStore = InMemoryDeviceTokenStore(token: "test-token")

        XCTAssertNil(configuration.simulatedAIServiceError)
        XCTAssertTrue(configuration.messageExtractionClient(deviceTokenStore: tokenStore) is AIServiceMessageExtractionClient)
    }
}
