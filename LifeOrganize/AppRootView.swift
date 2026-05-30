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

enum AppSection: String, Hashable, Identifiable, CaseIterable {
    case timeline
    case things
    case carryForward
    case search
    case review
    case settings

    var id: String { rawValue }

    init?(argumentValue: String) {
        switch argumentValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "timeline", "log":
            self = .timeline
        case "things":
            self = .things
        case "carry_forward", "carryforward", "rules":
            self = .carryForward
        case "search":
            self = .search
        case "review", "review_queue", "reviewqueue":
            self = .review
        case "settings", "preferences":
            self = .settings
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .timeline:
            "Timeline"
        case .things:
            "Things"
        case .carryForward:
            "Carry Forward"
        case .search:
            "Search"
        case .review:
            "Review"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline:
            "clock"
        case .things:
            "tray.full"
        case .carryForward:
            "checklist"
        case .search:
            "magnifyingglass"
        case .review:
            "text.badge.checkmark"
        case .settings:
            "gearshape"
        }
    }

    var accessibilityIdentifier: String {
        "sidebar-section-\(rawValue.replacingOccurrences(of: "carryForward", with: "carry-forward"))"
    }
}

extension AppTab {
    var section: AppSection {
        switch self {
        case .log:
            .timeline
        case .things:
            .things
        case .rules:
            .carryForward
        }
    }

    init?(section: AppSection) {
        switch section {
        case .timeline:
            self = .log
        case .things:
            self = .things
        case .carryForward:
            self = .rules
        case .search, .review, .settings:
            return nil
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @StateObject private var sessionState = AppSessionState()
    @ObservedObject private var developerModeState: DeveloperModeState
    @State private var selectedTab: AppTab
    @State private var selectedSection: AppSection
    @State private var activeSheet: AppRootSheet?
    @State private var pendingInitialSection: AppSection?
    @State private var hasAIServiceCredential = false
    @State private var maintenanceErrorMessage: String?
    private let deviceTokenStore: any DeviceTokenStore
    private let searchText: String

    @MainActor
    init(
        selectedTab: AppTab = .log,
        initialSection: AppSection? = nil,
        initialSheet: AppInitialSheet? = nil,
        searchText: String = "",
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        developerModeState: DeveloperModeState? = nil
    ) {
        let requestedSection = initialSection ?? initialSheet.map(AppSection.init)
        _selectedTab = State(initialValue: selectedTab)
        _selectedSection = State(initialValue: requestedSection ?? selectedTab.section)
        _activeSheet = State(initialValue: nil)
        _pendingInitialSection = State(initialValue: requestedSection)
        self.developerModeState = developerModeState ?? DeveloperModeState()
        self.deviceTokenStore = deviceTokenStore
        self.searchText = searchText
    }

    var body: some View {
        rootShell
        .environmentObject(sessionState)
        .environmentObject(developerModeState)
        .environment(\.debugAccessPolicy, developerModeState.policy)
        .tint(LedgerPalette.accent)
        .sheet(item: $activeSheet, onDismiss: reloadAIServiceState) { sheet in
            sheetView(for: sheet)
        }
        .onAppear {
            consumeInitialSectionIfNeeded()
            moveFromUnavailableReviewIfNeeded()
            reloadAIServiceState()
            repairDerivedFields()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                repairDerivedFields()
            }
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            adaptPresentationToCurrentSizeClass()
        }
        .onChange(of: toolbarState) { _, _ in
            moveFromUnavailableReviewIfNeeded()
        }
        .onChange(of: selectedSection) { oldValue, newValue in
            if oldValue == .settings || newValue == .settings {
                reloadAIServiceState()
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

    @ViewBuilder
    private var rootShell: some View {
        if usesRegularShell {
            RegularRootShell(
                selectedSection: sectionBinding,
                toolbarState: toolbarState,
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore,
                searchText: searchText,
                resetToken: sessionState.resetToken,
                onOpenLog: { selectSection(.timeline) },
                onLocalDataCleared: { selectSection(.timeline) }
            )
        } else {
            CompactRootShell(
                selectedTab: tabBinding,
                isShowingSettings: sheetBinding(for: .settings),
                isShowingSearch: sheetBinding(for: .search),
                isShowingReviewQueue: sheetBinding(for: .reviewQueue),
                toolbarState: toolbarState,
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore,
                resetToken: sessionState.resetToken,
                onOpenLog: { selectSection(.timeline) }
            )
        }
    }

    private var usesRegularShell: Bool {
        horizontalSizeClass == .regular
    }

    private func repairDerivedFields() {
        let runtime = AppRuntimeConfiguration.current
        guard !(runtime.isAutomationRuntime && runtime.shouldSkipLaunchMaintenance) else {
            return
        }
        let failures = LaunchMaintenanceService(modelContext: modelContext).repair()
        if failures.isEmpty {
            maintenanceErrorMessage = nil
        } else {
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

    private var tabBinding: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { tab in
            selectedTab = tab
            selectedSection = tab.section
        }
    }

    private var sectionBinding: Binding<AppSection> {
        Binding {
            selectedSection
        } set: { section in
            selectSection(section)
        }
    }

    private func selectSection(_ section: AppSection) {
        selectedSection = section
        if let tab = AppTab(section: section) {
            selectedTab = tab
        }
    }

    private func consumeInitialSectionIfNeeded() {
        guard let section = pendingInitialSection else { return }
        selectSection(section)
        if !usesRegularShell, let sheet = AppRootSheet(section: section) {
            activeSheet = sheet
        }
        pendingInitialSection = nil
    }

    private func adaptPresentationToCurrentSizeClass() {
        if usesRegularShell {
            if let activeSheet {
                selectSection(activeSheet.section)
                self.activeSheet = nil
            }
            moveFromUnavailableReviewIfNeeded()
        } else if activeSheet == nil, let sheet = AppRootSheet(section: selectedSection) {
            activeSheet = sheet
        }
    }

    private func moveFromUnavailableReviewIfNeeded() {
        guard usesRegularShell else { return }
        let validSection = RegularRootShell.validSelection(selectedSection, toolbarState: toolbarState)
        if validSection != selectedSection {
            selectSection(validSection)
        }
    }

    private func sheetBinding(for sheet: AppRootSheet) -> Binding<Bool> {
        Binding {
            activeSheet == sheet
        } set: { isPresented in
            if isPresented {
                selectSection(sheet.section)
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
            SettingsView(deviceTokenStore: deviceTokenStore, showsDoneButton: true) {
                selectSection(.timeline)
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

private enum AppRootSheet: String, Identifiable {
    case settings
    case search
    case reviewQueue

    var id: String { rawValue }

    var section: AppSection {
        switch self {
        case .settings:
            .settings
        case .search:
            .search
        case .reviewQueue:
            .review
        }
    }

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

    init?(section: AppSection) {
        switch section {
        case .settings:
            self = .settings
        case .search:
            self = .search
        case .review:
            self = .reviewQueue
        case .timeline, .things, .carryForward:
            return nil
        }
    }
}

private extension AppSection {
    init(_ sheet: AppInitialSheet) {
        switch sheet {
        case .settings:
            self = .settings
        case .search:
            self = .search
        case .reviewQueue:
            self = .review
        }
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
