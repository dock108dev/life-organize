import SwiftData
import SwiftUI

struct ThingsSplitView: View {
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @State private var selectedThingID: UUID?
    @State private var visibleThingIDs: [UUID] = []
    @State private var lastVisibleThingIDs: [UUID] = []
    private let isAddingThingPresentation: Binding<Bool>?
    let onOpenLog: () -> Void

    init(isAddingThing: Binding<Bool>? = nil, onOpenLog: @escaping () -> Void = {}) {
        self.isAddingThingPresentation = isAddingThing
        self.onOpenLog = onOpenLog
    }

    private var sortedThings: [Thing] {
        ThingListOrdering.sorted(things)
    }

    private var selectedThing: Thing? {
        guard let selectedThingID else { return nil }
        return things.first { $0.id == selectedThingID }
    }

    var body: some View {
        HStack(spacing: 0) {
            ThingsListView(
                isAddingThing: isAddingThingPresentation,
                selectedThingID: $selectedThingID,
                presentsSelectionInPlace: true,
                onVisibleThingIDsChange: updateVisibleThingIDs,
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
                .ledgerWorkspaceDetailPane("things-detail")
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
        .onAppear {
            repairSelection(visibleIDs: visibleThingIDs.isEmpty ? sortedThings.map(\.id) : visibleThingIDs)
        }
        .onChange(of: sortedThings.map(\.id)) { _, ids in
            repairSelection(visibleIDs: visibleThingIDs.isEmpty ? ids : visibleThingIDs)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let selectedThing {
            ThingDetailView(thing: selectedThing)
        } else if sortedThings.isEmpty {
            ThingsEmptyDetailView()
        } else {
            ThingsNoSelectionView()
        }
    }

    private func updateVisibleThingIDs(_ ids: [UUID]) {
        repairSelection(visibleIDs: ids)
        lastVisibleThingIDs = ids
        visibleThingIDs = ids
    }

    private func repairSelection(visibleIDs: [UUID]) {
        selectedThingID = ThingSelectionRepair.repairedSelection(
            selectedID: selectedThingID,
            previousVisibleIDs: lastVisibleThingIDs,
            currentVisibleIDs: visibleIDs,
            defaultsToFirstVisible: true
        )
    }
}

enum ThingListOrdering {
    static func sorted(_ things: [Thing]) -> [Thing] {
        things.sorted { lhs, rhs in
            switch (lhs.lastEventAt, rhs.lastEventAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

enum ThingSelectionRepair {
    static func repairedSelection(
        selectedID: UUID?,
        previousVisibleIDs: [UUID],
        currentVisibleIDs: [UUID],
        defaultsToFirstVisible: Bool
    ) -> UUID? {
        guard !currentVisibleIDs.isEmpty else { return nil }
        guard let selectedID else {
            return defaultsToFirstVisible ? currentVisibleIDs.first : nil
        }
        if currentVisibleIDs.contains(selectedID) {
            return selectedID
        }
        if let previousIndex = previousVisibleIDs.firstIndex(of: selectedID),
           currentVisibleIDs.indices.contains(previousIndex) {
            return currentVisibleIDs[previousIndex]
        }
        return currentVisibleIDs.last
    }
}

struct ThingsNoSelectionView: View {
    var body: some View {
        LedgerNoSelectionPlaceholderView(
            "Select a thing",
            systemImage: "tray",
            description: "The summary pane will show that thing's history, reminders, and notes."
        )
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("things-no-selection")
    }
}

struct ThingsEmptyDetailView: View {
    var body: some View {
        LedgerNoSelectionPlaceholderView(
            "No things yet",
            systemImage: "tray",
            description: "Open Timeline or add a thing from the list pane."
        )
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("things-no-content")
    }
}

struct MissingThingSelectionView: View {
    var body: some View {
        ContentUnavailableView("Thing unavailable", systemImage: "exclamationmark.circle")
            .background(LedgerScreenBackground().ignoresSafeArea())
    }
}
