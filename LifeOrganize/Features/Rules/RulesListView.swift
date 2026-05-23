import SwiftData
import SwiftUI

struct RulesListView: View {
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @State private var isAddingRule = false
    @State private var showsPaused = false
    @State private var reviewItemErrorMessage: String?
    @AppStorage("ledger.context.rules.dismissed") private var isRulesContextDismissed = false
    private let continuityService = ReminderContinuityPresentationService()
    let onOpenLog: () -> Void

    init(onOpenLog: @escaping () -> Void = {}) {
        self.onOpenLog = onOpenLog
    }

    var body: some View {
        Group {
            if rules.isEmpty {
                LedgerEmptyStateView(content: .rules) {
                    HStack(spacing: 12) {
                        Button("Open Timeline", action: onOpenLog)
                            .buttonStyle(.borderedProminent)

                        Button("Add Reminder") {
                            isAddingRule = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if activeRules.isEmpty && !showsPaused {
                LedgerEmptyStateView(
                    content: LedgerEmptyStateContent(
                        symbolName: "checklist",
                        title: "Nothing needs attention right now.",
                        body: "Paused and completed items are hidden from active Carry Forward.",
                        secondaryBody: "Show paused items when you want to review old follow-ups."
                    )
                ) {
                    Button("Show Paused") {
                        showsPaused = true
                    }
                    .buttonStyle(.bordered)
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
                                        .accessibilityIdentifier("carry-forward-row-\(rule.id.uuidString)")
                                        .listRowInsets(ReminderListLayout.rowInsets)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
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
                .accessibilityIdentifier("carry-forward-list")
                .listSectionSpacing(ReminderListLayout.sectionSpacing)
                .scrollContentBackground(.hidden)
                .background(LedgerScreenBackground().ignoresSafeArea())
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LedgerToolbarIconButton(systemName: "plus", accessibilityLabel: "Add Reminder") {
                    isAddingRule = true
                }
            }
        }
        .sheet(isPresented: $isAddingRule) {
            NavigationStack {
                RuleEditView(rule: nil, thing: nil)
            }
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

    private var activeRules: [LedgerRule] {
        ReminderContinuityLane.activeCases.flatMap { rules(in: $0) }
    }

    private var visibleLanes: [ReminderContinuityLane] {
        showsPaused ? ReminderContinuityLane.allCases : ReminderContinuityLane.activeCases
    }

    private func rules(in lane: ReminderContinuityLane) -> [LedgerRule] {
        continuityService.rules(rules, in: lane)
    }

    private func ruleLink(_ rule: LedgerRule, reviewPresentation: LedgerReviewItemPresentation?) -> some View {
        NavigationLink {
            RuleDetailView(rule: rule)
        } label: {
            let presentation = continuityService.presentation(for: rule)
            LedgerRuleRow(
                rule: rule,
                reviewPresentation: reviewPresentation,
                density: LedgerSurfaceDensity.reminderRow.rowDensity,
                emphasis: presentation.lane.rowEmphasis,
                reasonText: rule.details.nilIfEmpty ?? ""
            )
        }
    }

    private func reviewPresentation(for rule: LedgerRule) -> LedgerReviewItemPresentation? {
        LedgerReviewItemPresentationService().primaryPresentation(
            for: .rule,
            targetID: rule.id,
            in: reviewItems
        )
    }
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
