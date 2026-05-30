import SwiftUI

struct CompactRootShell: View {
    static let tabOrder: [AppTab] = [.log, .things, .rules]

    @Binding var selectedTab: AppTab
    @Binding var isShowingSettings: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingReviewQueue: Bool
    let toolbarState: AppToolbarState
    let hasAIServiceCredential: Bool
    let deviceTokenStore: any DeviceTokenStore
    let resetToken: UUID
    let onOpenLog: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            LogNavigationRoot(
                isShowingSettings: $isShowingSettings,
                isShowingSearch: $isShowingSearch,
                isShowingReviewQueue: $isShowingReviewQueue,
                toolbarState: toolbarState,
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore
            )
            .appTabItem(.log, resetToken: resetToken)

            ThingsNavigationRoot(
                isShowingSettings: $isShowingSettings,
                isShowingSearch: $isShowingSearch,
                isShowingReviewQueue: $isShowingReviewQueue,
                toolbarState: toolbarState,
                onOpenLog: onOpenLog
            )
            .appTabItem(.things, resetToken: resetToken)

            RulesNavigationRoot(
                isShowingSettings: $isShowingSettings,
                isShowingSearch: $isShowingSearch,
                isShowingReviewQueue: $isShowingReviewQueue,
                toolbarState: toolbarState,
                onOpenLog: onOpenLog
            )
            .appTabItem(.rules, resetToken: resetToken)
        }
    }
}

struct RegularRootShell: View {
    static let sectionOrder: [AppSection] = [.timeline, .things, .carryForward, .search, .review, .settings]

    static func sectionOrder(for toolbarState: AppToolbarState) -> [AppSection] {
        sectionOrder.filter { section in
            section != .review || toolbarState.showsReviewQueueButton
        }
    }

    static func validSelection(_ selection: AppSection, toolbarState: AppToolbarState) -> AppSection {
        selection == .review && !toolbarState.showsReviewQueueButton ? .timeline : selection
    }

    @Binding var selectedSection: AppSection
    let toolbarState: AppToolbarState
    let hasAIServiceCredential: Bool
    let deviceTokenStore: any DeviceTokenStore
    let searchText: String
    let resetToken: UUID
    let onOpenLog: () -> Void
    let onLocalDataCleared: () -> Void
    @State private var isAddingThing = false
    @State private var isAddingRule = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    sidebarRow(.timeline)
                    sidebarRow(.things)
                    sidebarRow(.carryForward)
                } header: {
                    sidebarHeader("Workspace")
                }

                Section {
                    sidebarRow(.search)
                    if visibleSections.contains(.review) {
                        sidebarRow(.review)
                    }
                } header: {
                    sidebarHeader("Utilities")
                }

                Section {
                    sidebarRow(.settings)
                } header: {
                    sidebarHeader("Preferences")
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle("LifeOrganize")
        } detail: {
            NavigationStack {
                destination(for: selectedSection)
                    .id(resetToken)
            }
        }
    }

    private var visibleSections: [AppSection] {
        Self.sectionOrder(for: toolbarState)
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            RegularSidebarSectionRow(section: section, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(section.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.58))
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .timeline:
            ChatView(
                hasAIServiceCredential: hasAIServiceCredential,
                deviceTokenStore: deviceTokenStore,
                onAddKey: { selectedSection = .settings }
            )
            .navigationTitle(section.title)
            .toolbar {
                RegularToolbarButtons(
                    state: toolbarState,
                    selectedSection: $selectedSection
                )
            }
        case .things:
            ThingsSplitView(isAddingThing: $isAddingThing, onOpenLog: onOpenLog)
                .navigationTitle(section.title)
                .toolbar {
                    RegularToolbarButtons(
                        state: toolbarState,
                        selectedSection: $selectedSection,
                        screenAction: .addThing,
                        performScreenAction: performScreenAction,
                        showsSearch: false
                    )
                }
        case .carryForward:
            RulesSplitView(isAddingRule: $isAddingRule, onOpenLog: onOpenLog)
                .navigationTitle(section.title)
                .toolbar {
                    RegularToolbarButtons(
                        state: toolbarState,
                        selectedSection: $selectedSection,
                        screenAction: .addReminder,
                        performScreenAction: performScreenAction
                    )
                }
        case .search:
            UnifiedSearchView(initialSearchText: searchText, showsDoneButton: false)
        case .review:
            LedgerReviewQueueView(
                deviceTokenStore: deviceTokenStore,
                onAddKey: { selectedSection = .settings },
                onClose: nil
            )
        case .settings:
            SettingsView(
                deviceTokenStore: deviceTokenStore,
                showsDoneButton: false,
                embedsNavigationStack: false,
                onLocalDataCleared: onLocalDataCleared
            )
        }
    }

    private func performScreenAction(_ action: AppToolbarScreenAction) {
        switch action {
        case .addThing:
            isAddingThing = true
        case .addReminder:
            isAddingRule = true
        }
    }
}

enum AppToolbarScreenAction: Equatable {
    case addThing
    case addReminder

    var systemName: String {
        "plus"
    }

    var accessibilityLabel: String {
        switch self {
        case .addThing:
            "Add Thing"
        case .addReminder:
            "Add Reminder"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .addThing:
            "add-thing-button"
        case .addReminder:
            "add-reminder-button"
        }
    }
}

struct AppToolbarConfiguration: Equatable {
    let screenAction: AppToolbarScreenAction?
    let showsReview: Bool
    let showsSearch: Bool
    let showsSettings: Bool

    static func root(
        state: AppToolbarState,
        screenAction: AppToolbarScreenAction? = nil,
        showsSearch: Bool = true
    ) -> AppToolbarConfiguration {
        AppToolbarConfiguration(
            screenAction: screenAction,
            showsReview: state.showsReviewQueueButton,
            showsSearch: showsSearch,
            showsSettings: true
        )
    }

    var orderedAccessibilityIdentifiers: [String] {
        var identifiers: [String] = []
        if let screenAction {
            identifiers.append(screenAction.accessibilityIdentifier)
        }
        if showsReview {
            identifiers.append("review-queue-button")
        }
        if showsSearch {
            identifiers.append(AppToolbarSearchEntry.accessibilityIdentifier)
        }
        if showsSettings {
            identifiers.append("settings-entry")
        }
        return identifiers
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
    @State private var isAddingThing = false

    var body: some View {
        NavigationStack {
            ThingsListView(isAddingThing: $isAddingThing, onOpenLog: onOpenLog)
                .navigationTitle(AppTab.things.title)
                .toolbar {
                    AppToolbarButtons(
                        state: toolbarState,
                        isShowingReviewQueue: $isShowingReviewQueue,
                        isShowingSearch: $isShowingSearch,
                        isShowingSettings: $isShowingSettings,
                        screenAction: .addThing,
                        performScreenAction: performScreenAction,
                        showsSearch: false
                    )
                }
        }
    }

    private func performScreenAction(_ action: AppToolbarScreenAction) {
        if action == .addThing {
            isAddingThing = true
        }
    }
}

private struct RulesNavigationRoot: View {
    @Binding var isShowingSettings: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingReviewQueue: Bool
    let toolbarState: AppToolbarState
    let onOpenLog: () -> Void
    @State private var isAddingRule = false

    var body: some View {
        NavigationStack {
            RulesListView(isAddingRule: $isAddingRule, onOpenLog: onOpenLog)
                .navigationTitle(AppTab.rules.title)
                .toolbar {
                    AppToolbarButtons(
                        state: toolbarState,
                        isShowingReviewQueue: $isShowingReviewQueue,
                        isShowingSearch: $isShowingSearch,
                        isShowingSettings: $isShowingSettings,
                        screenAction: .addReminder,
                        performScreenAction: performScreenAction
                    )
                }
        }
    }

    private func performScreenAction(_ action: AppToolbarScreenAction) {
        if action == .addReminder {
            isAddingRule = true
        }
    }
}

private struct AppToolbarButtons: ToolbarContent {
    let state: AppToolbarState
    @Binding var isShowingReviewQueue: Bool
    @Binding var isShowingSearch: Bool
    @Binding var isShowingSettings: Bool
    var screenAction: AppToolbarScreenAction?
    var performScreenAction: (AppToolbarScreenAction) -> Void = { _ in }
    var showsSearch = true

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let screenAction = configuration.screenAction {
                screenActionButton(screenAction)
            }

            if configuration.showsReview {
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

            if configuration.showsSearch {
                LedgerToolbarIconButton(
                    systemName: AppToolbarSearchEntry.systemName,
                    accessibilityLabel: AppToolbarSearchEntry.accessibilityLabel,
                    accessibilityIdentifier: AppToolbarSearchEntry.accessibilityIdentifier
                ) {
                    isShowingSearch = true
                }
            }

            if configuration.showsSettings {
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

    private var configuration: AppToolbarConfiguration {
        .root(state: state, screenAction: screenAction, showsSearch: showsSearch)
    }

    private func screenActionButton(_ action: AppToolbarScreenAction) -> some View {
        LedgerToolbarIconButton(
            systemName: action.systemName,
            accessibilityLabel: action.accessibilityLabel,
            accessibilityIdentifier: action.accessibilityIdentifier
        ) {
            performScreenAction(action)
        }
    }
}

private struct RegularToolbarButtons: ToolbarContent {
    let state: AppToolbarState
    @Binding var selectedSection: AppSection
    var screenAction: AppToolbarScreenAction?
    var performScreenAction: (AppToolbarScreenAction) -> Void = { _ in }
    var showsSearch = true

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let screenAction = configuration.screenAction {
                screenActionButton(screenAction)
            }

            if configuration.showsReview {
                LedgerToolbarIconButton(
                    systemName: "text.badge.checkmark",
                    accessibilityLabel: "Review Items",
                    accessibilityIdentifier: "review-queue-button",
                    accessibilityValue: "\(state.openReviewItemCount) open",
                    isActive: selectedSection == .review
                ) {
                    selectedSection = .review
                }
            }

            if configuration.showsSearch {
                LedgerToolbarIconButton(
                    systemName: AppToolbarSearchEntry.systemName,
                    accessibilityLabel: AppToolbarSearchEntry.accessibilityLabel,
                    accessibilityIdentifier: AppToolbarSearchEntry.accessibilityIdentifier,
                    isActive: selectedSection == .search
                ) {
                    selectedSection = .search
                }
            }

            if configuration.showsSettings {
                LedgerToolbarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    accessibilityIdentifier: "settings-entry",
                    isActive: selectedSection == .settings
                ) {
                    selectedSection = .settings
                }
            }
        }
    }

    private var configuration: AppToolbarConfiguration {
        .root(state: state, screenAction: screenAction, showsSearch: showsSearch)
    }

    private func screenActionButton(_ action: AppToolbarScreenAction) -> some View {
        LedgerToolbarIconButton(
            systemName: action.systemName,
            accessibilityLabel: action.accessibilityLabel,
            accessibilityIdentifier: action.accessibilityIdentifier
        ) {
            performScreenAction(action)
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
