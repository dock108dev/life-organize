import SwiftData
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case log
    case things
    case rules

    init?(argumentValue: String) {
        switch argumentValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "timeline", "log":
            self = .log
        case "things":
            self = .things
        case "carry_forward", "rules":
            self = .rules
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .log:
            "Timeline"
        case .things:
            "Things"
        case .rules:
            "Carry Forward"
        }
    }

    var systemImage: String {
        switch self {
        case .log:
            "clock"
        case .things:
            "tray.full"
        case .rules:
            "checklist"
        }
    }
}

struct AppToolbarState: Equatable {
    let openReviewItemCount: Int

    var showsReviewQueueButton: Bool {
        openReviewItemCount > 0
    }
}

struct AppRootView: View {
    static let initialTab: AppTab = .log

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @StateObject private var sessionState = AppSessionState()
    @ObservedObject private var developerModeState: DeveloperModeState
    @State private var selectedTab: AppTab
    @State private var activeSheet: AppRootSheet?
    @State private var hasAIServiceCredential = false
    @State private var maintenanceErrorMessage: String?
    private let deviceTokenStore: any DeviceTokenStore
    private let searchText: String

    @MainActor
    init(
        selectedTab: AppTab = .log,
        initialSheet: AppInitialSheet? = nil,
        searchText: String = "",
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        developerModeState: DeveloperModeState? = nil
    ) {
        _selectedTab = State(initialValue: selectedTab)
        _activeSheet = State(initialValue: initialSheet.map(AppRootSheet.init))
        self.developerModeState = developerModeState ?? DeveloperModeState()
        self.deviceTokenStore = deviceTokenStore
        self.searchText = searchText
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LogNavigationRoot(
                isShowingSettings: sheetBinding(for: .settings),
                isShowingSearch: sheetBinding(for: .search),
                isShowingReviewQueue: sheetBinding(for: .reviewQueue),
                toolbarState: toolbarState,
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore
            )
            .appTabItem(.log, resetToken: sessionState.resetToken)

            ThingsNavigationRoot(
                isShowingSettings: sheetBinding(for: .settings),
                isShowingSearch: sheetBinding(for: .search),
                isShowingReviewQueue: sheetBinding(for: .reviewQueue),
                toolbarState: toolbarState,
                onOpenLog: { selectedTab = .log }
            )
            .appTabItem(.things, resetToken: sessionState.resetToken)

            RulesNavigationRoot(
                isShowingSettings: sheetBinding(for: .settings),
                isShowingSearch: sheetBinding(for: .search),
                isShowingReviewQueue: sheetBinding(for: .reviewQueue),
                toolbarState: toolbarState,
                onOpenLog: { selectedTab = .log }
            )
            .appTabItem(.rules, resetToken: sessionState.resetToken)
        }
        .environmentObject(sessionState)
        .environmentObject(developerModeState)
        .environment(\.debugAccessPolicy, developerModeState.policy)
        .tint(LedgerPalette.accent)
        .sheet(item: $activeSheet, onDismiss: reloadAIServiceState) { sheet in
            sheetView(for: sheet)
        }
        .onAppear {
            reloadAIServiceState()
            repairDerivedFields()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                repairDerivedFields()
            }
        }
        .alert(
            "Couldn’t Refresh Ledger",
            isPresented: Binding(
                get: { maintenanceErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        maintenanceErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(maintenanceErrorMessage ?? "")
        }
        .overlay(alignment: .bottomTrailing) {
            if AppRuntimeConfiguration.current.isScreenshotMode {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screenshot-ready")
            }
        }
    }

    private func repairDerivedFields() {
        let runtime = AppRuntimeConfiguration.current
        guard !(runtime.isAutomationRuntime && runtime.shouldSkipLaunchMaintenance) else {
            return
        }
        do {
            try ExtractionRecoveryMaintenanceService(modelContext: modelContext).repairInterruptedEntries()
            try DerivedFieldMaintenanceService(modelContext: modelContext).repairAll()
            try LedgerReviewItemGenerationService(modelContext: modelContext).refresh()
            maintenanceErrorMessage = nil
        } catch {
            maintenanceErrorMessage = "Some cached ledger fields could not be refreshed."
        }
    }

    private func reloadAIServiceState() {
        do {
            hasAIServiceCredential = try !deviceTokenStore.ensureDeviceToken().isEmpty
        } catch {
            hasAIServiceCredential = false
        }
    }

    private var toolbarState: AppToolbarState {
        AppToolbarState(openReviewItemCount: reviewItems.ambientlyVisibleCount)
    }

    private func sheetBinding(for sheet: AppRootSheet) -> Binding<Bool> {
        Binding {
            activeSheet == sheet
        } set: { isPresented in
            if isPresented {
                activeSheet = sheet
            } else if activeSheet == sheet {
                activeSheet = nil
            }
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: AppRootSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView(deviceTokenStore: deviceTokenStore) {
                selectedTab = .log
                activeSheet = nil
            }
            .environmentObject(sessionState)
            .environmentObject(developerModeState)
            .environment(\.debugAccessPolicy, developerModeState.policy)
        case .search:
            NavigationStack {
                UnifiedSearchView(initialSearchText: searchText, showsDoneButton: true)
            }
            .environment(\.debugAccessPolicy, developerModeState.policy)
        case .reviewQueue:
            NavigationStack {
                LedgerReviewQueueView(deviceTokenStore: deviceTokenStore) {
                    activeSheet = .settings
                } onClose: {
                    activeSheet = nil
                }
            }
            .environmentObject(sessionState)
        }
    }
}

private struct LogNavigationRoot: View {
    @Binding var isShowingSettings: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingReviewQueue: Bool
    let toolbarState: AppToolbarState
    let hasAIServiceCredential: Bool
    let deviceTokenStore: any DeviceTokenStore

    var body: some View {
        NavigationStack {
            ChatView(
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore,
                onAddKey: { isShowingSettings = true }
            )
                .navigationTitle(AppTab.log.title)
                .toolbar {
                    AppToolbarButtons(
                        state: toolbarState,
                        isShowingReviewQueue: $isShowingReviewQueue,
                        isShowingSearch: $isShowingSearch,
                        isShowingSettings: $isShowingSettings
                    )
                }
        }
    }
}

private struct ThingsNavigationRoot: View {
    @Binding var isShowingSettings: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingReviewQueue: Bool
    let toolbarState: AppToolbarState
    let onOpenLog: () -> Void

    var body: some View {
        NavigationStack {
            ThingsListView(onOpenLog: onOpenLog)
                .navigationTitle(AppTab.things.title)
                .toolbar {
                    AppToolbarButtons(
                        state: toolbarState,
                        isShowingReviewQueue: $isShowingReviewQueue,
                        isShowingSearch: $isShowingSearch,
                        isShowingSettings: $isShowingSettings
                    )
                }
        }
    }
}

private struct RulesNavigationRoot: View {
    @Binding var isShowingSettings: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingReviewQueue: Bool
    let toolbarState: AppToolbarState
    let onOpenLog: () -> Void

    var body: some View {
        NavigationStack {
            RulesListView(onOpenLog: onOpenLog)
                .navigationTitle(AppTab.rules.title)
                .toolbar {
                    AppToolbarButtons(
                        state: toolbarState,
                        isShowingReviewQueue: $isShowingReviewQueue,
                        isShowingSearch: $isShowingSearch,
                        isShowingSettings: $isShowingSettings
                    )
                }
        }
    }
}

private struct AppToolbarButtons: ToolbarContent {
    let state: AppToolbarState
    @Binding var isShowingReviewQueue: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingSettings: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if state.showsReviewQueueButton {
                LedgerToolbarIconButton(
                    systemName: "text.badge.checkmark",
                    accessibilityLabel: "Review Items",
                    accessibilityIdentifier: "review-queue-button",
                    accessibilityValue: "\(state.openReviewItemCount) open",
                    isActive: true
                ) {
                    isShowingReviewQueue = true
                }
            }

            LedgerToolbarIconButton(
                systemName: AppToolbarSearchEntry.systemName,
                accessibilityLabel: AppToolbarSearchEntry.accessibilityLabel,
                accessibilityIdentifier: AppToolbarSearchEntry.accessibilityIdentifier
            ) {
                isShowingSearch = true
            }

            LedgerToolbarIconButton(
                systemName: "gearshape",
                accessibilityLabel: "Settings",
                accessibilityIdentifier: "settings-entry"
            ) {
                isShowingSettings = true
            }
        }
    }
}

private enum AppRootSheet: String, Identifiable {
    case settings
    case search
    case reviewQueue

    var id: String { rawValue }

    init(_ sheet: AppInitialSheet) {
        switch sheet {
        case .settings:
            self = .settings
        case .search:
            self = .search
        case .reviewQueue:
            self = .reviewQueue
        }
    }
}

private extension View {
    func appTabItem(_ tab: AppTab, resetToken: UUID) -> some View {
        tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .id(resetToken)
    }
}

private extension Array where Element == LedgerReviewItem {
    var ambientlyVisibleCount: Int {
        filter(\.state.isAmbientlyVisible).count
    }
}

enum AppToolbarSearchEntry {
    static let systemName = "magnifyingglass.circle"
    static let accessibilityLabel = "Search Timeline"
    static let accessibilityIdentifier = "root-search-entry"
}

#Preview {
    AppRootView()
        .modelContainer(ModelContainerFactory.make(inMemory: true))
}
