import SwiftData
import SwiftUI

struct ThingsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerRule.updatedAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @State private var searchText = ""
    @State private var localIsAddingThing = false
    @State private var activeThingRoute: ThingDetailRoute?
    @State private var reviewItemErrorMessage: String?
    @AppStorage("ledger.context.things.dismissed") private var isThingsContextDismissed = false
    private let isAddingThingPresentation: Binding<Bool>?
    @Binding private var selectedThingID: UUID?
    let presentsSelectionInPlace: Bool
    let onVisibleThingIDsChange: ([UUID]) -> Void
    let onOpenLog: () -> Void

    init(
        isAddingThing: Binding<Bool>? = nil,
        selectedThingID: Binding<UUID?> = .constant(nil),
        presentsSelectionInPlace: Bool = false,
        onVisibleThingIDsChange: @escaping ([UUID]) -> Void = { _ in },
        onOpenLog: @escaping () -> Void = {}
    ) {
        self.isAddingThingPresentation = isAddingThing
        self._selectedThingID = selectedThingID
        self.presentsSelectionInPlace = presentsSelectionInPlace
        self.onVisibleThingIDsChange = onVisibleThingIDsChange
        self.onOpenLog = onOpenLog
    }

    private var isSearching: Bool {
        !SearchService.normalizeForLocalSearch(searchText).isEmpty
    }

    private var isAddingThing: Binding<Bool> {
        isAddingThingPresentation ?? $localIsAddingThing
    }

    static let localSearchScopes: Set<LocalSearchEntityKind> = [.thing]

    private var sortedThings: [Thing] {
        ThingListOrdering.sorted(things)
    }

    private var visibleThingIDs: [UUID] {
        if isSearching {
            return searchResults.compactMap(\.thingDetailID)
        }
        return sortedThings.map(\.id)
    }

    private var shouldShowThingsContext: Bool {
        !isThingsContextDismissed && sortedThings.count <= 3
    }

    var body: some View {
        Group {
            if isSearching {
                searchResultsView
            } else if things.isEmpty {
                LedgerCenteredEmptyState {
                    LedgerEmptyStateView(content: .things) {
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
            } else {
                List {
                    if shouldShowThingsContext {
                        LedgerContextPanel(content: .things) {
                            isThingsContextDismissed = true
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(sortedThings) { thing in
                        thingRowLink(for: thing)
                        .accessibilityIdentifier("thing-row-\(thing.id.uuidString)")
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(rowBackground(for: thing))
                        .ledgerReviewItemContextMenu(
                            reviewPresentation(for: thing)?.item,
                            onError: { reviewItemErrorMessage = $0 }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(LedgerScreenBackground().ignoresSafeArea())
                .accessibilityIdentifier("things-list")
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search things"
        )
        .sheet(isPresented: isAddingThing) {
            NavigationStack {
                ThingEditView(existingThing: nil) { thing in
                    modelContext.insert(thing)
                    try modelContext.save()
                    selectedThingID = thing.id
                }
            }
        }
        .navigationDestination(for: LocalSearchResult.self) { result in
            searchDestination(for: result)
        }
        .navigationDestination(item: $activeThingRoute) { route in
            if let thing = things.first(where: { $0.id == route.id }) {
                ThingDetailView(thing: thing)
            } else {
                MissingThingSelectionView()
            }
        }
        .onAppear(perform: reportVisibleThingIDs)
        .onChange(of: visibleThingIDs) { _, _ in
            reportVisibleThingIDs()
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

    private func showAddThingSheet() {
        isAddingThing.wrappedValue = true
    }

    @ViewBuilder
    private var emptyStateActions: some View {
        Button("Open Timeline", action: onOpenLog)
            .buttonStyle(.borderedProminent)

        Button("Add Thing") {
            showAddThingSheet()
        }
        .buttonStyle(.bordered)
    }

    private var searchResults: [LocalSearchResult] {
        let search = SearchService()
        return search.search(
            LocalSearchQuery(rawText: searchText, scopes: Self.localSearchScopes, limit: 50),
            in: search.records(
                things: things
            )
        )
    }

    @ViewBuilder
    private var searchResultsView: some View {
        LedgerSearchResultsList(
            results: searchResults,
            emptyContent: .noThingSearchResults,
            onSelect: presentsSelectionInPlace ? { selectSearchResult($0) } : nil
        )
    }

    private func searchDestination(for result: LocalSearchResult) -> some View {
        LocalSearchDestinationView(
            result: result,
            things: things,
            events: [],
            rules: [],
            notes: [],
            messages: []
        )
    }

    private func reviewPresentation(for thing: Thing) -> LedgerReviewItemPresentation? {
        LedgerReviewItemPresentationService().primaryPresentation(
            for: .thing,
            targetID: thing.id,
            in: reviewItems
        )
    }

    private func relatedRules(for thing: Thing) -> [LedgerRule] {
        let sourceIDs = Set(thing.sourceMessageIDs)
        return rules.filter { rule in
            guard let sourceMessageID = rule.sourceMessageID else { return false }
            return sourceIDs.contains(sourceMessageID)
        }
    }

    private func sourceMessages(for thing: Thing) -> [ChatMessage] {
        let sourceIDs = Set(thing.sourceMessageIDs)
        return messages.filter { sourceIDs.contains($0.id) }
    }

    @ViewBuilder
    private func thingRowLink(for thing: Thing) -> some View {
        let row = ThingRow(
            thing: thing,
            reviewPresentation: reviewPresentation(for: thing),
            relatedRules: relatedRules(for: thing),
            sourceMessages: sourceMessages(for: thing),
            isSelected: presentsSelectionInPlace && selectedThingID == thing.id
        )

        if presentsSelectionInPlace {
            Button {
                selectedThingID = thing.id
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedThingID = thing.id
                activeThingRoute = ThingDetailRoute(id: thing.id)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
    }

    private func rowBackground(for thing: Thing) -> Color {
        presentsSelectionInPlace && selectedThingID == thing.id
            ? LedgerPalette.accent.opacity(0.10)
            : Color.clear
    }

    private func selectSearchResult(_ result: LocalSearchResult) {
        guard let thingID = result.thingDetailID else { return }
        selectedThingID = thingID
    }

    private func reportVisibleThingIDs() {
        onVisibleThingIDsChange(visibleThingIDs)
    }
}

private struct ThingDetailRoute: Identifiable, Hashable {
    let id: UUID
}

private extension LocalSearchResult {
    var thingDetailID: UUID? {
        if case .thingDetail(let id) = navigationTarget {
            return id
        }
        return nil
    }
}

private struct ThingRow: View {
    let thing: Thing
    let reviewPresentation: LedgerReviewItemPresentation?
    var relatedRules: [LedgerRule] = []
    var sourceMessages: [ChatMessage] = []
    var isSelected = false

    private var snapshot: ThingPreviewSnapshot {
        ThingPreviewSnapshot(thing: thing, relatedRules: relatedRules, sourceMessages: sourceMessages)
    }

    var body: some View {
        let snapshot = snapshot
        let candidateBadges = badgeCandidates(for: snapshot)
        let visibleBadges = LedgerBadgePresentation.primaryBadges(from: candidateBadges)

        LedgerRow(
            primary: snapshot.title,
            secondary: rowLines(snapshot),
            density: LedgerSurfaceDensity.thingsRow.rowDensity,
            emphasis: isSelected ? .active : .normal
        ) {
            ForEach(visibleBadges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
        .accessibilityLabel(accessibilityLabel(for: snapshot, candidateBadges: candidateBadges, visibleBadges: visibleBadges))
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func rowLines(_ snapshot: ThingPreviewSnapshot) -> [LedgerRowLine] {
        var lines = [snapshot.listSummaryLine]
        if let savedItemSummaryLine = snapshot.savedItemSummaryLine,
           savedItemSummaryLine.text != snapshot.listSummaryLine.text {
            lines.append(savedItemSummaryLine)
        }
        return lines
    }

    private func badgeCandidates(for snapshot: ThingPreviewSnapshot) -> [LedgerBadgePresentation] {
        [
            snapshot.categoryTitle.map { LedgerBadgePresentation(semantic: .categoryThing, label: $0) },
            reviewPresentation?.badge
        ].compactMap(\.self)
    }

    private func accessibilityLabel(
        for snapshot: ThingPreviewSnapshot,
        candidateBadges: [LedgerBadgePresentation],
        visibleBadges: [LedgerBadgePresentation]
    ) -> String {
        let hiddenBadges = LedgerBadgePresentation.hiddenBadges(from: candidateBadges, visibleBadges: visibleBadges)
        return ([snapshot.title] + visibleBadges.map(\.label) + hiddenBadges.map(\.label) + rowLines(snapshot).map(\.text))
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

#Preview {
    NavigationStack {
        ThingsListView()
            .navigationTitle(AppTab.things.title)
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
