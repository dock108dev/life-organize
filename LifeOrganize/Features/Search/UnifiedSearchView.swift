import SwiftData
import SwiftUI

struct UnifiedSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @State private var searchText: String
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

    var body: some View {
        Group {
            if isSearching {
                searchResultsView
            } else {
                searchLandingView
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
    private var searchResultsView: some View {
        LedgerSearchResultsList(results: searchResults)
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
                                secondary: [LedgerRowLine(text: example.detail)],
                                density: .compact
                            ) {
                                LedgerPill(text: example.pillText, tone: example.tone, size: .small)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-landing-example-\(example.accessibilityKey)")
                    }
                }
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
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
