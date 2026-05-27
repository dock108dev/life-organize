import Foundation
import SwiftUI

enum AppDefaultsKeys {
    static let developerModeUnlocked = "DeveloperMode.isUnlocked"
    static let timelineContextDismissed = "ledger.context.timeline.dismissed"
    static let thingsContextDismissed = "ledger.context.things.dismissed"
    static let rulesContextDismissed = "ledger.context.rules.dismissed"

    static let all = [
        developerModeUnlocked,
        timelineContextDismissed,
        thingsContextDismissed,
        rulesContextDismissed
    ]
}

struct AppRuntimeConfiguration {
    var isUITesting: Bool
    var isScreenshotMode: Bool
    var usesDeterministicExtractor: Bool
    var shouldResetStore: Bool
    var shouldResetDeviceToken: Bool
    var shouldSkipLaunchMaintenance: Bool
    var enablesDeveloperMode: Bool
    var unlocksDeveloperMode: Bool
    var simulatedAIServiceError: AppError?
    var seedScenarioIDs: [String]
    var initialTab: AppTab?
    var initialSection: AppSection?
    var initialSheet: AppInitialSheet?
    var screenshotSeed: ScreenshotSeed?
    var screenshotSearchQuery: String?
    var screenshotLocale: Locale?
    var screenshotTimeZone: TimeZone?
    var screenshotCalendar: Calendar?
    var screenshotAppearance: ScreenshotAppearance?
    var disablesAnimations: Bool
    var aiServiceBaseURL: URL
    private var shouldResetFreshInstallState: Bool
    private var usesInMemoryAutomationStore: Bool
    var fixedNow: Date?

    static let defaultAIServiceBaseURL = URL(string: "https://life.dock108.dev")!

    static var current: AppRuntimeConfiguration {
        AppRuntimeConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    init(arguments: [String]) {
        let screenshotMode = arguments.contains("-screenshot-mode")
        let automationRuntime = arguments.contains("-ui-testing") || screenshotMode
        isScreenshotMode = screenshotMode
        isUITesting = automationRuntime
        usesDeterministicExtractor = arguments.contains("-use-fake-extractor") || screenshotMode
        shouldResetFreshInstallState = arguments.contains("--reset-db")
        shouldResetStore = arguments.contains("-reset-store") || shouldResetFreshInstallState || screenshotMode
        shouldResetDeviceToken = arguments.contains("-reset-device-token") || shouldResetFreshInstallState || screenshotMode
        shouldSkipLaunchMaintenance = arguments.contains("-skip-launch-maintenance") || arguments.contains("--skip-launch-maintenance")
        enablesDeveloperMode = arguments.contains("-enable-developer-mode")
        unlocksDeveloperMode = automationRuntime && arguments.contains("-unlock-developer-mode")
        simulatedAIServiceError = Self.simulatedAIServiceError(from: arguments, isAutomationRuntime: automationRuntime)
        usesInMemoryAutomationStore = arguments.contains("-use-in-memory-store") || arguments.contains("--use-in-memory-store")
        screenshotSeed = Self.screenshotSeed(from: arguments)
        screenshotSearchQuery = Self.argumentValue(from: arguments, prefixes: ["-screenshot-search-query="])
        screenshotLocale = Self.screenshotLocale(from: arguments)
        screenshotTimeZone = Self.screenshotTimeZone(from: arguments)
        screenshotCalendar = Self.screenshotCalendar(from: arguments, timeZone: screenshotTimeZone, locale: screenshotLocale)
        screenshotAppearance = Self.screenshotAppearance(from: arguments)
        disablesAnimations = arguments.contains("-disable-animations") || screenshotMode
        aiServiceBaseURL = Self.aiServiceBaseURL(from: arguments)
        seedScenarioIDs = Self.seedScenarioIDs(from: arguments, screenshotSeed: screenshotSeed, isScreenshotMode: screenshotMode)
        let start = Self.screenshotStart(from: arguments)
        initialTab = Self.initialTab(from: arguments, screenshotStart: start)
        initialSection = start.map(AppSection.init)
        initialSheet = Self.initialSheet(from: arguments)
        fixedNow = Self.fixedDate(from: arguments) ?? (screenshotMode ? Self.defaultScreenshotNow : nil)
    }

    var isAutomationRuntime: Bool {
        isUITesting || isScreenshotMode
    }

    var requestsFreshInstallReset: Bool {
        shouldResetFreshInstallState
    }

    var isDeveloperModeAvailable: Bool {
        #if DEBUG
            return true
        #elseif INTERNAL_DIAGNOSTICS
            return true
        #else
            return isUITesting && enablesDeveloperMode
        #endif
    }

    @MainActor
    func messageExtractionClient(deviceTokenStore: any DeviceTokenStore) -> any MessageExtractionClient {
        if let simulatedAIServiceError {
            return SimulatedUnavailableMessageExtractionClient(error: simulatedAIServiceError)
        }
        if usesDeterministicExtractor {
            return DeterministicMessageExtractionClient()
        }
        return AIServiceMessageExtractionClient(deviceTokenStore: deviceTokenStore, serviceBaseURL: aiServiceBaseURL)
    }

    @MainActor
    func webRequestClient(deviceTokenStore: any DeviceTokenStore) -> (any WebRequestClient)? {
        if let simulatedAIServiceError {
            return SimulatedUnavailableWebRequestClient(error: simulatedAIServiceError)
        }
        guard !usesDeterministicExtractor else { return nil }
        return AIServiceWebRequestClient(deviceTokenStore: deviceTokenStore, serviceBaseURL: aiServiceBaseURL)
    }

    func deviceTokenStore() -> any DeviceTokenStore {
        if isAutomationRuntime {
            return InMemoryDeviceTokenStore()
        }
        return KeychainDeviceTokenStore()
    }

    func userDefaults() -> UserDefaults {
        guard isAutomationRuntime else {
            return .standard
        }

        let suiteName = "LifeOrganize.Automation"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create automation user defaults suite.")
        }
        return defaults
    }

    func resetLaunchStateIfNeeded(defaults: UserDefaults) {
        guard isAutomationRuntime else { return }

        if requestsFreshInstallReset {
            let locations = Self.automationStorageLocations()
            Self.resetDirectory(at: locations.applicationSupportRoot)
            Self.resetDirectory(at: locations.cachesRoot)
            Self.resetDirectory(at: locations.temporaryRoot)
            defaults.removePersistentDomain(forName: "LifeOrganize.Automation")
            Self.resetURLLoadingState()
        } else {
            if shouldResetStore {
                Self.removeStore(at: Self.uiTestingStoreURL())
            }
            if shouldResetDeviceToken {
                Self.resetAppDefaults(in: defaults)
            }
        }

        if isScreenshotMode {
            Self.prepareScreenshotDefaults(in: defaults)
        }
    }

    func applyProcessEnvironmentOverrides() {
        guard isScreenshotMode, let screenshotTimeZone else { return }

        NSTimeZone.default = screenshotTimeZone
    }

    var dateProvider: any DateProvider {
        if let fixedNow {
            return FixedDateProvider(now: fixedNow)
        }
        return SystemDateProvider()
    }

    func modelContainer() -> ModelContainerFactory.Configuration {
        guard isAutomationRuntime else {
            return .standard
        }

        if usesInMemoryAutomationStore {
            return .inMemory
        }
        return .store(url: Self.uiTestingStoreURL())
    }

    var preferredColorScheme: ColorScheme? {
        switch screenshotAppearance {
        case .light:
            .light
        case .dark:
            .dark
        case nil:
            nil
        }
    }

    private static func seedScenarioIDs(
        from arguments: [String],
        screenshotSeed: ScreenshotSeed?,
        isScreenshotMode: Bool
    ) -> [String] {
        let supportedPrefixes = [
            "-seed-scenario=",
            "--seed-scenario="
        ]
        let explicitIDs: [String] = arguments.compactMap { argument in
            guard let prefix = supportedPrefixes.first(where: { argument.hasPrefix($0) }) else {
                return nil
            }
            let id = String(argument.dropFirst(prefix.count))
            return id.isEmpty ? nil : id
        }
        if !explicitIDs.isEmpty {
            return explicitIDs
        }
        if let screenshotSeed {
            return screenshotSeed.seedScenarioIDs
        }
        return isScreenshotMode ? ScreenshotSeed.default.seedScenarioIDs : []
    }

    private static func initialTab(from arguments: [String], screenshotStart: ScreenshotStart?) -> AppTab? {
        if let rawValue = argumentValue(from: arguments, prefixes: ["-initial-tab=", "--initial-tab="]),
           let tab = AppTab(argumentValue: rawValue) {
            return tab
        }

        switch screenshotStart {
        case .timeline, .settings, .search, .review:
            return .log
        case .things:
            return .things
        case .carryForward:
            return .rules
        case nil:
            return nil
        }
    }

    private static func initialSheet(from arguments: [String]) -> AppInitialSheet? {
        switch screenshotStart(from: arguments) {
        case .settings:
            return .settings
        case .search:
            return .search
        case .review:
            return .reviewQueue
        case .timeline, .things, .carryForward, nil:
            return nil
        }
    }

    private static func fixedDate(from arguments: [String]) -> Date? {
        guard let rawValue = arguments.first(where: { $0.hasPrefix("-fixed-now=") })?
            .dropFirst("-fixed-now=".count) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: String(rawValue))
    }

    private static func screenshotSeed(from arguments: [String]) -> ScreenshotSeed? {
        argumentValue(from: arguments, prefixes: ["-screenshot-seed="]).flatMap(ScreenshotSeed.init(argumentValue:))
    }

    private static func screenshotStart(from arguments: [String]) -> ScreenshotStart? {
        argumentValue(from: arguments, prefixes: ["-screenshot-start="]).flatMap(ScreenshotStart.init(argumentValue:))
    }

    private static func aiServiceBaseURL(from arguments: [String]) -> URL {
        guard let value = argumentValue(from: arguments, prefixes: ["-ai-service-base-url=", "--ai-service-base-url="]),
              let url = URL(string: value),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return defaultAIServiceBaseURL
        }
        return url
    }

    private static func screenshotLocale(from arguments: [String]) -> Locale? {
        guard let identifier = argumentValue(from: arguments, prefixes: ["-screenshot-locale="]) else {
            return nil
        }
        return Locale(identifier: identifier)
    }

    private static func screenshotTimeZone(from arguments: [String]) -> TimeZone? {
        guard let identifier = argumentValue(from: arguments, prefixes: ["-screenshot-time-zone="]) else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }

    private static func screenshotCalendar(from arguments: [String], timeZone: TimeZone?, locale: Locale?) -> Calendar? {
        guard let rawIdentifier = argumentValue(from: arguments, prefixes: ["-screenshot-calendar="]) else {
            return nil
        }

        let identifier: Calendar.Identifier
        switch rawIdentifier.lowercased() {
        case "gregorian":
            identifier = .gregorian
        case "iso8601", "iso-8601":
            identifier = .iso8601
        default:
            return nil
        }

        var calendar = Calendar(identifier: identifier)
        if let timeZone {
            calendar.timeZone = timeZone
        }
        if let locale {
            calendar.locale = locale
        }
        return calendar
    }

    private static func screenshotAppearance(from arguments: [String]) -> ScreenshotAppearance? {
        argumentValue(from: arguments, prefixes: ["-screenshot-appearance="]).flatMap(ScreenshotAppearance.init(argumentValue:))
    }

    private static func argumentValue(from arguments: [String], prefixes: [String]) -> String? {
        guard let rawValue = arguments.first(where: { argument in
            prefixes.contains { argument.hasPrefix($0) }
        }) else {
            return nil
        }

        let prefix = prefixes.first { rawValue.hasPrefix($0) } ?? ""
        let value = String(rawValue.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static func uiTestingStoreURL() -> URL {
        let baseURL = automationStorageLocations().applicationSupportRoot
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Unable to create UI testing store directory: \(error)")
        }
        return baseURL.appendingPathComponent("LifeOrganize.sqlite")
    }

    private static func removeStore(at storeURL: URL) {
        let fileManager = FileManager.default
        let relatedURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                preconditionFailure("Unable to reset UI testing store: \(error)")
            }
        }
    }

    private static func resetAppDefaults(in defaults: UserDefaults) {
        for key in AppDefaultsKeys.all {
            defaults.removeObject(forKey: key)
        }
    }

    private static func prepareScreenshotDefaults(in defaults: UserDefaults) {
        defaults.set(true, forKey: AppDefaultsKeys.timelineContextDismissed)
        defaults.set(true, forKey: AppDefaultsKeys.thingsContextDismissed)
    }

    private static func resetDirectory(at url: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                preconditionFailure("Unable to reset automation directory: \(error)")
            }
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Unable to create automation directory: \(error)")
        }
    }

    private static func resetURLLoadingState() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
    }

    private static func automationStorageLocations() -> AppStorageLocations {
        let fileManager = FileManager.default
        let applicationSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UITesting", isDirectory: true)
        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LifeOrganize", isDirectory: true)
            .appendingPathComponent("UITesting", isDirectory: true)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("LifeOrganize", isDirectory: true)
            .appendingPathComponent("UITesting", isDirectory: true)
        return AppStorageLocations(
            applicationSupportRoot: applicationSupportRoot,
            cachesRoot: cachesRoot,
            temporaryRoot: temporaryRoot
        )
    }

    private static let defaultScreenshotNow: Date = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2027-01-15T08:00:00-05:00")!
    }()
}

private struct AppStorageLocations {
    var applicationSupportRoot: URL
    var cachesRoot: URL
    var temporaryRoot: URL
}

private struct FixedDateProvider: DateProvider {
    var now: Date
}

enum AppInitialSheet: String {
    case settings
    case search
    case reviewQueue
}

private extension AppSection {
    init(_ start: ScreenshotStart) {
        switch start {
        case .timeline:
            self = .timeline
        case .things:
            self = .things
        case .carryForward:
            self = .carryForward
        case .settings:
            self = .settings
        case .search:
            self = .search
        case .review:
            self = .review
        }
    }
}
