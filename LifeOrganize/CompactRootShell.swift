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
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("Workspace") {
                    sidebarRow(.timeline)
                    sidebarRow(.things)
                    sidebarRow(.carryForward)
                }

                Section("Utilities") {
                    sidebarRow(.search)
                    if visibleSections.contains(.review) {
                        sidebarRow(.review)
                    }
                }

                Section("Preferences") {
                    sidebarRow(.settings)
                }
            }
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
        Button {
            selectedSection = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedSection == section ? LedgerPalette.accent.opacity(0.12) : Color.clear)
        .accessibilityIdentifier(section.accessibilityIdentifier)
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
            ThingsSplitView(onOpenLog: onOpenLog)
                .navigationTitle(section.title)
                .toolbar {
                    RegularToolbarButtons(
                        state: toolbarState,
                        selectedSection: $selectedSection,
                        showsSearch: false
                    )
                }
        case .carryForward:
            RulesSplitView(onOpenLog: onOpenLog)
                .navigationTitle(section.title)
                .toolbar {
                    RegularToolbarButtons(
                        state: toolbarState,
                        selectedSection: $selectedSection
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
                        isShowingSettings: $isShowingSettings,
                        showsSearch: false
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
    var showsSearch = true

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

            if showsSearch {
                LedgerToolbarIconButton(
                    systemName: AppToolbarSearchEntry.systemName,
                    accessibilityLabel: AppToolbarSearchEntry.accessibilityLabel,
                    accessibilityIdentifier: AppToolbarSearchEntry.accessibilityIdentifier
                ) {
                    isShowingSearch = true
                }
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

private struct RegularToolbarButtons: ToolbarContent {
    let state: AppToolbarState
    @Binding var selectedSection: AppSection
    var showsSearch = true

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if state.showsReviewQueueButton {
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

            if showsSearch {
                LedgerToolbarIconButton(
                    systemName: AppToolbarSearchEntry.systemName,
                    accessibilityLabel: AppToolbarSearchEntry.accessibilityLabel,
                    accessibilityIdentifier: AppToolbarSearchEntry.accessibilityIdentifier,
                    isActive: selectedSection == .search
                ) {
                    selectedSection = .search
                }
            }

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

private extension View {
    func appTabItem(_ tab: AppTab, resetToken: UUID) -> some View {
        tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .id(resetToken)
    }
}
