import SwiftData
import SwiftUI

@main
struct LifeOrganizeApp: App {
    private let runtime: AppRuntimeConfiguration
    private let modelContainer: ModelContainer
    private let apiKeyStore: any APIKeyStore
    @StateObject private var developerModeState: DeveloperModeState

    init() {
        let runtime = AppRuntimeConfiguration.current
        self.runtime = runtime
        let defaults = runtime.userDefaults()
        runtime.resetLaunchStateIfNeeded(defaults: defaults)
        let apiKeyStore: any APIKeyStore = runtime.apiKeyStore()
        if runtime.shouldResetAPIKey && runtime.isAutomationRuntime && runtime.screenshotAPIKeyMode != .present {
            try? apiKeyStore.deleteOpenAIAPIKey()
        }
        self.apiKeyStore = apiKeyStore
        let container = ModelContainerFactory.make(configuration: runtime.modelContainer())
        do {
            try SeedScenarioLoader.load(
                runtime.seedScenarioIDs,
                into: container,
                now: runtime.dateProvider.now,
                isAutomationRuntime: runtime.isAutomationRuntime
            )
        } catch {
            preconditionFailure("Unable to load launch seed scenarios: \(error)")
        }
        _developerModeState = StateObject(
            wrappedValue: DeveloperModeState(
                isAvailable: runtime.isDeveloperModeAvailable,
                defaults: defaults
            )
        )
        modelContainer = container
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                selectedTab: runtime.initialTab ?? AppRootView.initialTab,
                initialSheet: runtime.initialSheet,
                searchText: runtime.screenshotSearchQuery ?? "",
                apiKeyStore: apiKeyStore,
                developerModeState: developerModeState
            )
            .environment(\.locale, runtime.screenshotLocale ?? Locale.current)
            .environment(\.timeZone, runtime.screenshotTimeZone ?? TimeZone.current)
            .environment(\.calendar, runtime.screenshotCalendar ?? Calendar.current)
            .preferredColorScheme(runtime.preferredColorScheme)
            .transaction { transaction in
                if runtime.disablesAnimations {
                    transaction.animation = nil
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
