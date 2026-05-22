import SwiftData
import SwiftUI

struct ThingsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @State private var searchText = ""
    @State private var isAddingThing = false
    @State private var reviewItemErrorMessage: String?
    let onOpenLog: () -> Void

    init(onOpenLog: @escaping () -> Void = {}) {
        self.onOpenLog = onOpenLog
    }

    private var isSearching: Bool {
        !SearchService.normalizeForLocalSearch(searchText).isEmpty
    }

    static let localSearchScopes: Set<LocalSearchEntityKind> = [.thing]

    private var sortedThings: [Thing] {
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

    var body: some View {
        Group {
            if isSearching {
                searchResultsView
            } else if things.isEmpty {
                LedgerEmptyStateView(content: .things) {
                    HStack(spacing: 12) {
                        Button("Open Timeline", action: onOpenLog)
                            .buttonStyle(.borderedProminent)

                        Button("Add Thing") {
                            isAddingThing = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                List(sortedThings) { thing in
                    let reviewPresentation = reviewPresentation(for: thing)
                    NavigationLink {
                        ThingDetailView(thing: thing)
                    } label: {
                        ThingRow(thing: thing, reviewPresentation: reviewPresentation)
                    }
                    .accessibilityIdentifier("thing-row-\(thing.id.uuidString)")
                    .ledgerReviewItemContextMenu(reviewPresentation?.item, onError: { reviewItemErrorMessage = $0 })
                }
                .listStyle(.plain)
                .accessibilityIdentifier("things-list")
            }
        }
        .searchable(text: $searchText, prompt: "Search things")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LedgerToolbarIconButton(systemName: "plus", accessibilityLabel: "Add Thing") {
                    isAddingThing = true
                }
            }
        }
        .sheet(isPresented: $isAddingThing) {
            NavigationStack {
                ThingEditView(existingThing: nil) { thing in
                    modelContext.insert(thing)
                    try modelContext.save()
                }
            }
        }
        .navigationDestination(for: LocalSearchResult.self) { result in
            searchDestination(for: result)
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
        LedgerSearchResultsList(results: searchResults, emptyContent: .noThingSearchResults)
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
}

private struct ThingRow: View {
    let thing: Thing
    let reviewPresentation: LedgerReviewItemPresentation?

    private var snapshot: ThingPreviewSnapshot {
        ThingPreviewSnapshot(thing: thing)
    }

    var body: some View {
        let snapshot = snapshot

        LedgerRow(
            primary: snapshot.title,
            secondary: rowLines(snapshot),
            footer: snapshot.footerItems.isEmpty ? nil : snapshot.footerItems.joined(separator: " · "),
            density: LedgerSurfaceDensity.thingsRow.rowDensity
        ) {
            if let categoryTitle = snapshot.categoryTitle {
                LedgerBadgePill(
                    badge: LedgerBadgePresentation(semantic: .categoryThing, label: categoryTitle),
                    size: .small
                )
            }
            if let reviewPresentation {
                LedgerBadgePill(badge: reviewPresentation.badge, size: .small)
            }
        }
    }

    private func rowLines(_ snapshot: ThingPreviewSnapshot) -> [LedgerRowLine] {
        var lines = snapshot.continuityLines.map { line in
            var parts = [line.value]
            if let detail = line.detail?.nilIfEmpty {
                parts.append(detail)
            }
            let label = displayLabel(for: line.label)
            return LedgerRowLine(
                text: "\(label): \(parts.joined(separator: " · "))",
                tone: line.tone,
                lineLimit: label == "Recent note" || label == "Details" ? 2 : 1
            )
        }
        if let reviewPresentation {
            lines.append(reviewPresentation.rowLine)
        }
        return lines
    }

    private func displayLabel(for label: String) -> String {
        switch label {
        case "Last event":
            return "Last"
        case "Reminder":
            return "Now"
        default:
            return label
        }
    }
}

#Preview {
    NavigationStack {
        ThingsListView()
            .navigationTitle(AppTab.things.title)
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
