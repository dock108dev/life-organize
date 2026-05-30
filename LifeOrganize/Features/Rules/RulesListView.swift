import SwiftData
import SwiftUI

struct RulesListView: View {
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @State private var localIsAddingRule = false
    @State private var showsPaused = false
    @State private var activeRuleRoute: RuleDetailRoute?
    @State private var reviewItemErrorMessage: String?
    @AppStorage("ledger.context.rules.dismissed") private var isRulesContextDismissed = false
    private let isAddingRulePresentation: Binding<Bool>?
    @Binding private var selectedRuleID: UUID?
    private let continuityService = ReminderContinuityPresentationService()
    let presentsSelectionInPlace: Bool
    let onVisibleRuleIDsChange: ([UUID]) -> Void
    let onOpenLog: () -> Void

    init(
        isAddingRule: Binding<Bool>? = nil,
        selectedRuleID: Binding<UUID?> = .constant(nil),
        presentsSelectionInPlace: Bool = false,
        onVisibleRuleIDsChange: @escaping ([UUID]) -> Void = { _ in },
        onOpenLog: @escaping () -> Void = {}
    ) {
        self.isAddingRulePresentation = isAddingRule
        self._selectedRuleID = selectedRuleID
        self.presentsSelectionInPlace = presentsSelectionInPlace
        self.onVisibleRuleIDsChange = onVisibleRuleIDsChange
        self.onOpenLog = onOpenLog
    }

    private var isAddingRule: Binding<Bool> {
        isAddingRulePresentation ?? $localIsAddingRule
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                LedgerCenteredEmptyState {
                    LedgerEmptyStateView(content: .rules) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                emptyStateActions
                            }

                            VStack(spacing: 10) {
                                emptyStateActions
                            }
                        }
                    }
                }
            } else if visibleRuleIDs.isEmpty && !showsPaused {
                LedgerCenteredEmptyState {
                    LedgerEmptyStateView(
                        content: LedgerEmptyStateContent(
                            symbolName: "checklist",
                            title: "Nothing needs attention right now",
                            body: "Paused and completed items are hidden from active Carry Forward.",
                            secondaryBody: "Show paused items when you want to review old follow-ups."
                        )
                    ) {
                        Button("Show Paused") {
                            showsPaused = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                List {
                    if !isRulesContextDismissed {
                        LedgerContextPanel(content: .rules) {
                            isRulesContextDismissed = true
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(visibleLanes, id: \.title) { lane in
                        let laneRules = rules(in: lane)
                        if !laneRules.isEmpty {
                            Section {
                                ForEach(laneRules) { rule in
                                    let reviewPresentation = reviewPresentation(for: rule)
                                    ruleLink(rule, reviewPresentation: reviewPresentation)
                                        .accessibilityIdentifier(RulesUIContract.rowAccessibilityIdentifier(for: rule.id))
                                        .listRowInsets(ReminderListLayout.rowInsets)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(rowBackground(for: rule))
                                        .ledgerReviewItemContextMenu(
                                            reviewPresentation?.item,
                                            onError: { reviewItemErrorMessage = $0 }
                                        )
                                }
                            } header: {
                                LedgerSectionHeader(title: lane.title)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier(RulesUIContract.listAccessibilityIdentifier)
                .listSectionSpacing(ReminderListLayout.sectionSpacing)
                .scrollContentBackground(.hidden)
                .background(LedgerScreenBackground().ignoresSafeArea())
            }
        }
        .sheet(isPresented: isAddingRule) {
            NavigationStack {
                RuleEditView(rule: nil, thing: nil)
            }
        }
        .navigationDestination(item: $activeRuleRoute) { route in
            if let rule = rules.first(where: { $0.id == route.id }) {
                RuleDetailView(rule: rule)
            } else {
                MissingRuleSelectionView()
            }
        }
        .onAppear(perform: reportVisibleRuleIDs)
        .onChange(of: visibleRuleIDs) { _, _ in
            reportVisibleRuleIDs()
        }
        .alert(
            "Couldn't Update Review Item",
            isPresented: Binding(
                get: { reviewItemErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        reviewItemErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reviewItemErrorMessage ?? "")
        }
    }

    private func showAddRuleSheet() {
        isAddingRule.wrappedValue = true
    }

    @ViewBuilder
    private var emptyStateActions: some View {
        Button("Open Timeline", action: onOpenLog)
            .buttonStyle(.borderedProminent)

        Button("Add Reminder") {
            showAddRuleSheet()
        }
        .buttonStyle(.bordered)
    }

    private var selectedRule: LedgerRule? {
        guard let selectedRuleID else { return nil }
        return rules.first { $0.id == selectedRuleID }
    }

    private var selectedLane: ReminderContinuityLane? {
        selectedRule.map { continuityService.presentation(for: $0).lane }
    }

    private var visibleLanes: [ReminderContinuityLane] {
        RuleLaneVisibility.visibleLanes(showsPaused: showsPaused, selectedLane: selectedLane)
    }

    private var visibleRuleIDs: [UUID] {
        visibleLanes.flatMap { rules(in: $0).map(\.id) }
    }

    private func rules(in lane: ReminderContinuityLane) -> [LedgerRule] {
        continuityService.rules(rules, in: lane)
    }

    @ViewBuilder
    private func ruleLink(_ rule: LedgerRule, reviewPresentation: LedgerReviewItemPresentation?) -> some View {
        let row = LedgerRuleRow(
            rule: rule,
            reviewPresentation: reviewPresentation,
            density: LedgerSurfaceDensity.reminderRow.rowDensity,
            emphasis: continuityService.presentation(for: rule).lane.rowEmphasis,
            reasonText: rule.details.nilIfEmpty ?? ""
        )

        if presentsSelectionInPlace {
            Button {
                selectedRuleID = rule.id
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedRuleID = rule.id
                activeRuleRoute = RuleDetailRoute(id: rule.id)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
    }

    private func reviewPresentation(for rule: LedgerRule) -> LedgerReviewItemPresentation? {
        LedgerReviewItemPresentationService().primaryPresentation(
            for: .rule,
            targetID: rule.id,
            in: reviewItems
        )
    }

    private func rowBackground(for rule: LedgerRule) -> Color {
        presentsSelectionInPlace && selectedRuleID == rule.id
            ? LedgerPalette.accent.opacity(0.10)
            : Color.clear
    }

    private func reportVisibleRuleIDs() {
        onVisibleRuleIDsChange(visibleRuleIDs)
    }
}

enum RulesUIContract {
    static let listAccessibilityIdentifier = "carry-forward-list"
    static let detailAccessibilityIdentifier = "carry-forward-detail"
    static let detailPaneAccessibilityIdentifier = "carry-forward-detail-pane"

    static func rowAccessibilityIdentifier(for ruleID: UUID) -> String {
        "carry-forward-row-\(ruleID.uuidString)"
    }
}

struct RulesSplitView: View {
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @State private var selectedRuleID: UUID?
    @State private var visibleRuleIDs: [UUID] = []
    private let isAddingRulePresentation: Binding<Bool>?
    let onOpenLog: () -> Void

    init(isAddingRule: Binding<Bool>? = nil, onOpenLog: @escaping () -> Void = {}) {
        self.isAddingRulePresentation = isAddingRule
        self.onOpenLog = onOpenLog
    }

    private var selectedRule: LedgerRule? {
        guard let selectedRuleID else { return nil }
        return rules.first { $0.id == selectedRuleID }
    }

    var body: some View {
        HStack(spacing: 0) {
            RulesListView(
                isAddingRule: isAddingRulePresentation,
                selectedRuleID: $selectedRuleID,
                presentsSelectionInPlace: true,
                onVisibleRuleIDsChange: updateVisibleRuleIDs,
                onOpenLog: onOpenLog
            )
            // layout-guard: allow fixed-size reason="regular-width list column bounds"
            .frame(
                minWidth: LedgerAdaptiveLayout.Workspace.listColumnMin,
                idealWidth: LedgerAdaptiveLayout.Workspace.listColumnIdeal,
                maxWidth: LedgerAdaptiveLayout.Workspace.listColumnMax
            )

            LedgerWorkspaceSplitDivider()

            selectedDetail
                .ledgerWorkspaceDetailPane(RulesUIContract.detailPaneAccessibilityIdentifier)
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
        .onAppear {
            repairSelection(visibleIDs: visibleRuleIDs.isEmpty ? rules.map(\.id) : visibleRuleIDs)
        }
        .onChange(of: rules.map(\.id)) { _, ids in
            repairSelection(visibleIDs: visibleRuleIDs.isEmpty ? ids : visibleRuleIDs)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let selectedRule {
            RuleDetailView(rule: selectedRule)
        } else if rules.isEmpty {
            CarryForwardEmptyDetailView()
        } else if visibleRuleIDs.isEmpty {
            CarryForwardNoVisibleSelectionView()
        } else {
            CarryForwardNoSelectionView()
        }
    }

    private func updateVisibleRuleIDs(_ ids: [UUID]) {
        visibleRuleIDs = ids
        repairSelection(visibleIDs: ids)
    }

    private func repairSelection(visibleIDs: [UUID]) {
        selectedRuleID = RuleSelectionRepair.repairedSelection(
            selectedID: selectedRuleID,
            currentVisibleIDs: visibleIDs
        )
    }
}

enum RuleSelectionRepair {
    static func repairedSelection(selectedID: UUID?, currentVisibleIDs: [UUID]) -> UUID? {
        guard let selectedID else { return nil }
        return currentVisibleIDs.contains(selectedID) ? selectedID : nil
    }
}

enum RuleLaneVisibility {
    static func visibleLanes(
        showsPaused: Bool,
        selectedLane: ReminderContinuityLane?
    ) -> [ReminderContinuityLane] {
        let baseLanes = showsPaused
            ? ReminderContinuityLane.allCases
            : ReminderContinuityLane.activeCases

        return ReminderContinuityLane.allCases.filter { lane in
            baseLanes.contains(lane) || selectedLane == lane
        }
    }
}

struct CarryForwardNoSelectionView: View {
    var body: some View {
        LedgerNoSelectionPlaceholderView(
            "Select a reminder",
            systemImage: "checklist",
            description: "Choose a reminder to see its details."
        )
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("carry-forward-no-selection")
    }
}

struct CarryForwardEmptyDetailView: View {
    var body: some View {
        LedgerNoSelectionPlaceholderView(
            "No reminders yet",
            systemImage: "checklist",
            description: "Add a reminder or open Timeline to create one."
        )
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("carry-forward-no-content")
    }
}

struct CarryForwardNoVisibleSelectionView: View {
    var body: some View {
        LedgerNoSelectionPlaceholderView(
            "No visible reminder",
            systemImage: "checklist",
            description: "Show paused items to choose an old follow-up."
        )
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("carry-forward-no-visible-selection")
    }
}

struct MissingRuleSelectionView: View {
    var body: some View {
        ContentUnavailableView("Reminder unavailable", systemImage: "exclamationmark.circle")
            .background(LedgerScreenBackground().ignoresSafeArea())
    }
}

private struct RuleDetailRoute: Identifiable, Hashable {
    let id: UUID
}

enum ReminderListLayout {
    static let rowVerticalInset: CGFloat = 3
    static let rowHorizontalInset: CGFloat = 6
    static let sectionSpacing: CGFloat = 8

    static var rowInsets: EdgeInsets {
        EdgeInsets(
            top: rowVerticalInset,
            leading: rowHorizontalInset,
            bottom: rowVerticalInset,
            trailing: rowHorizontalInset
        )
    }
}

#Preview {
    NavigationStack {
        RulesListView()
            .navigationTitle(AppTab.rules.title)
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
