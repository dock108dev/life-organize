import SwiftData
import SwiftUI

struct UnifiedSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @State private var searchText: String
    @State private var selectedRoute: LocalSearchSelectionRoute?
    let showsDoneButton: Bool

    init(initialSearchText: String = "", showsDoneButton: Bool = false) {
        _searchText = State(initialValue: initialSearchText)
        self.showsDoneButton = showsDoneButton
    }

    private var isSearching: Bool {
        !SearchService.normalizeForLocalSearch(searchText).isEmpty
    }

    private var searchResults: [LocalSearchResult] {
        let search = SearchService()
        return search.search(
            LocalSearchQuery(rawText: searchText, limit: 50),
            in: search.records(
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                messages: messages.filter { $0.role == .user }
            )
        )
    }

    private var currentRoutes: [LocalSearchSelectionRoute] {
        searchResults.map(LocalSearchSelectionRoute.init)
    }

    private var usesRegularWorkspace: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesRegularWorkspace {
                regularSearchWorkspace
            } else {
                compactSearchContent
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search what you remember"
        )
        .navigationDestination(for: LocalSearchResult.self) { result in
            destination(for: result)
        }
        .onAppear {
            repairSelection()
        }
        .onChange(of: currentRoutes) {
            repairSelection()
        }
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .accessibilityIdentifier("search-done-button")
                    }
                    .accessibilityIdentifier("search-done-button")
                }
            }
        }
    }

    @ViewBuilder
    private var compactSearchContent: some View {
        if isSearching {
            searchResultsView
        } else {
            searchLandingView
        }
    }

    private var regularSearchWorkspace: some View {
        HStack(spacing: 0) {
            regularSearchListPane
                // layout-guard: allow fixed-size reason="regular-width search list column bounds"
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 430)

            Divider()

            regularSearchDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
        .accessibilityIdentifier("search-workspace")
    }

    @ViewBuilder
    private var regularSearchListPane: some View {
        if isSearching {
            LedgerSearchResultsList(
                results: searchResults,
                selectedResultID: selectedRoute?.id
            ) { result in
                selectedRoute = LocalSearchSelectionRoute(result: result)
            }
        } else {
            searchLandingView
        }
    }

    @ViewBuilder
    private var regularSearchDetailPane: some View {
        if let selectedRoute {
            LocalSearchDestinationView(
                target: selectedRoute.navigationTarget,
                things: things,
                events: events,
                rules: rules,
                notes: notes,
                messages: messages,
                missingRecordActionTitle: "Clear selection"
            ) {
                self.selectedRoute = nil
            }
            .id(selectedRoute.id)
        } else {
            LedgerNoSelectionPlaceholderView(
                "Select a result",
                systemImage: "sidebar.left",
                description: "Choose an item from the search results."
            )
            .background(Color(.systemGroupedBackground))
            .accessibilityIdentifier("search-no-selection")
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        ZStack {
            LedgerScreenBackground()
                .ignoresSafeArea()

            LedgerSearchResultsList(results: searchResults)
                .ledgerAdaptiveWidth(.readable)
        }
    }

    private func destination(for result: LocalSearchResult) -> some View {
        LocalSearchDestinationView(
            result: result,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            messages: messages
        )
    }

    private func repairSelection() {
        guard usesRegularWorkspace else {
            selectedRoute = nil
            return
        }
        guard let selectedRoute else { return }
        if let refreshedRoute = currentRoutes.first(where: { $0.id == selectedRoute.id }) {
            self.selectedRoute = refreshedRoute
        } else {
            self.selectedRoute = nil
        }
    }

    private var searchLandingView: some View {
        ScrollView {
            LedgerEmptyStateView(content: .searchLanding) {
                VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
                    LedgerSectionHeader(title: "Try a detail")
                    ForEach(Self.landingExamples) { example in
                        Button {
                            searchText = example.query
                        } label: {
                            LedgerRow(
                                primary: example.query,
                                secondary: [LedgerRowLine(text: example.detail, role: .contentPreview)],
                                density: .compact
                            ) {
                                LedgerPill(text: example.pillText, tone: example.tone, size: .small)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-landing-example-\(example.accessibilityKey)")
                    }
                }
                .frame(maxWidth: LedgerAdaptiveLayout.EmptyState.contentMaxWidth)
            }
            .frame(maxWidth: .infinity, minHeight: LedgerAdaptiveLayout.EmptyState.searchLandingMinHeight)
            .ledgerAdaptiveWidth(.readable)
        }
    }

    static let landingExamples = [
        SearchLandingExample(query: "oil last month", detail: "Thing plus rough timing", pillText: "Rough date", tone: .neutral),
        SearchLandingExample(query: "May 2026", detail: "A month from the ledger", pillText: "Month", tone: .info),
        SearchLandingExample(query: "HarborMart 40k", detail: "Vendor, mileage, or phrase fragments", pillText: "Fragment", tone: .success),
        SearchLandingExample(query: "upcoming", detail: "Future reminder windows", pillText: "Timing", tone: .attention)
    ]

    static let phaseThreeExampleQueries = landingExamples.map(\.query)
}

struct SearchLandingExample: Identifiable, Equatable {
    let query: String
    let detail: String
    let pillText: String
    let tone: LedgerTone

    var id: String {
        query
    }

    var accessibilityKey: String {
        SearchService.normalizeForLocalSearch(query).replacingOccurrences(of: " ", with: "-")
    }
}

struct LocalSearchSelectionRoute: Hashable, Identifiable {
    let id: LocalSearchResult.ID
    let navigationTarget: LocalSearchNavigationTarget

    init(result: LocalSearchResult) {
        id = result.id
        navigationTarget = result.navigationTarget
    }
}
