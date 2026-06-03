import SwiftData
import SwiftUI

struct LedgerReviewQueueView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerNote.updatedAt, order: .reverse) private var notes: [LedgerNote]

    let origin: LedgerReviewOrigin?
    let focusedItemID: UUID?
    let deviceTokenStore: any DeviceTokenStore
    let onClose: (() -> Void)?

    @State private var errorMessage: String?
    @State private var selectedItemID: UUID?
    @State private var lastAppliedFocusedItemID: UUID?
    @State private var previousVisibleItemIDs: [UUID] = []

    init(
        origin: LedgerReviewOrigin? = nil,
        focusedItemID: UUID? = nil,
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        onClose: (() -> Void)? = nil
    ) {
        self.origin = origin
        self.focusedItemID = focusedItemID
        self.deviceTokenStore = deviceTokenStore
        self.onClose = onClose
    }

    private var queueState: LedgerReviewQueueLoadState {
        LedgerReviewQueueLoadState.load {
            try queueService.entries(from: reviewItems, origin: origin)
        }
    }

    private var queueEntries: [LedgerReviewQueueEntry] {
        queueState.entries
    }

    private var queueLoadErrorMessage: String? {
        queueState.errorMessage
    }

    private var visibleEntries: [LedgerReviewQueueEntry] {
        guard let focusedItemID else { return queueEntries }
        let focused = queueEntries.filter { $0.itemID == focusedItemID }
        let remaining = queueEntries.filter { $0.itemID != focusedItemID }
        return focused + remaining
    }

    private var visibleItemIDs: [UUID] {
        visibleEntries.map(\.itemID)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var selectedReview: (item: LedgerReviewItem, entry: LedgerReviewQueueEntry)? {
        guard let selectedItemID,
              let entry = visibleEntries.first(where: { $0.itemID == selectedItemID }),
              let item = reviewItems.first(where: { $0.id == entry.itemID }) else {
            return nil
        }
        return (item, entry)
    }

    private var queueService: LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: modelContext,
            deviceTokenStore: deviceTokenStore,
            dataGeneration: sessionState.dataGeneration,
            isDataGenerationCurrent: sessionState.isCurrentDataGeneration
        )
    }

    var body: some View {
        Group {
            if isRegularWidth {
                regularQueueView
            } else {
                compactQueueView
            }
        }
        .navigationTitle(origin == nil ? "Review" : "Review Context")
        .toolbar {
            closeToolbarItem
        }
        .alert(
            "Couldn't Load Review",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var regularQueueView: some View {
        NavigationSplitView {
            regularQueueList
        } detail: {
            regularDetail
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            reconcileSelection(preferredFocusedItemID: focusedItemID)
        }
        .onChange(of: visibleItemIDs) {
            reconcileSelection(preferredFocusedItemID: focusedItemID)
        }
        .onChange(of: focusedItemID) { _, newFocusedItemID in
            reconcileSelection(preferredFocusedItemID: newFocusedItemID)
        }
    }

    @ViewBuilder
    private var regularQueueList: some View {
        if let queueLoadErrorMessage {
            reviewLoadFailureState(queueLoadErrorMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LedgerScreenBackground().ignoresSafeArea())
                .accessibilityIdentifier("review-queue-list")
        } else if visibleEntries.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LedgerScreenBackground().ignoresSafeArea())
                .accessibilityIdentifier("review-queue-list")
        } else {
            List {
                ForEach(visibleEntries) { entry in
                    if let item = reviewItems.first(where: { $0.id == entry.itemID }) {
                        let presentation = LedgerReviewQueueRowPresentation(item: item, entry: entry)
                        Button {
                            selectedItemID = entry.itemID
                        } label: {
                            LedgerReviewQueueRow(
                                presentation: presentation,
                                isSelected: selectedItemID == entry.itemID
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("review-queue-row-\(entry.itemID.uuidString)")
                        .accessibilityLabel(presentation.accessibilityLabel)
                        .accessibilityHint(selectedItemID == entry.itemID ? "Selected review" : "Shows review details")
                        .accessibilityAddTraits(selectedItemID == entry.itemID ? .isSelected : [])
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("review-queue-list")
        }
    }

    @ViewBuilder
    private var regularDetail: some View {
        Group {
            if let selectedReview {
                detailView(item: selectedReview.item, entry: selectedReview.entry)
                    .id(selectedReview.item.id)
            } else if let queueLoadErrorMessage {
                reviewLoadFailureState(queueLoadErrorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LedgerScreenBackground().ignoresSafeArea())
            } else if visibleEntries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LedgerScreenBackground().ignoresSafeArea())
            } else {
                LedgerNoSelectionPlaceholderView(
                    "Select a review",
                    systemImage: "sidebar.left",
                    description: "Choose an item from the review queue."
                )
                .background(LedgerScreenBackground().ignoresSafeArea())
            }
        }
        .ledgerWorkspaceDetailPane("review-queue-detail")
    }

    private var compactQueueView: some View {
        Group {
            if let queueLoadErrorMessage {
                LedgerCenteredEmptyState {
                    reviewLoadFailureState(queueLoadErrorMessage)
                }
            } else if visibleEntries.isEmpty {
                LedgerCenteredEmptyState {
                    emptyState
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleEntries) { entry in
                            if let item = reviewItems.first(where: { $0.id == entry.itemID }) {
                                let presentation = LedgerReviewQueueRowPresentation(item: item, entry: entry)
                                NavigationLink {
                                    detailView(item: item, entry: entry)
                                } label: {
                                    LedgerReviewQueueRow(presentation: presentation)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("review-queue-row-\(entry.itemID.uuidString)")
                                .accessibilityLabel(presentation.accessibilityLabel)
                                .accessibilityHint("Opens review details")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(LedgerScreenBackground().ignoresSafeArea())
                .accessibilityIdentifier("review-queue-list")
            }
        }
    }

    private var emptyState: some View {
        LedgerEmptyStateView(content: origin == nil ? .reviewAllCaughtUp : .reviewContextEmpty)
    }

    private func reviewLoadFailureState(_ message: String) -> some View {
        LedgerNoSelectionPlaceholderView(
            "Review could not load",
            systemImage: "exclamationmark.triangle",
            description: message
        )
        .accessibilityIdentifier("review-queue-load-error")
    }

    private func detailView(item: LedgerReviewItem, entry: LedgerReviewQueueEntry) -> some View {
        LedgerReviewQueueDetailView(
            item: item,
            entry: entry,
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            deviceTokenStore: deviceTokenStore
        )
    }

    @ToolbarContentBuilder
    private var closeToolbarItem: some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
                    .accessibilityIdentifier("review-queue-close-button")
            }
        }
    }

    private func reconcileSelection(preferredFocusedItemID: UUID?) {
        let currentVisibleItemIDs = visibleItemIDs
        guard isRegularWidth else {
            previousVisibleItemIDs = currentVisibleItemIDs
            return
        }

        let repairedSelection = ReviewQueueSelectionRepair.repairedSelection(
            selectedID: selectedItemID,
            preferredFocusedID: preferredFocusedItemID,
            lastAppliedFocusedID: lastAppliedFocusedItemID,
            previousVisibleIDs: previousVisibleItemIDs,
            currentVisibleIDs: currentVisibleItemIDs
        )
        selectedItemID = repairedSelection.selectedID
        lastAppliedFocusedItemID = repairedSelection.lastAppliedFocusedID
        previousVisibleItemIDs = currentVisibleItemIDs
    }
}

private struct LedgerReviewQueueRow: View {
    let presentation: LedgerReviewQueueRowPresentation
    var isSelected = false

    var body: some View {
        LedgerRow(
            primary: presentation.question,
            secondary: secondaryLines,
            surfaceDensity: .detailSummary,
            emphasis: isSelected ? .active : .normal,
            badges: {
                ForEach(Array(presentation.badges.prefix(1))) { badge in
                    LedgerBadgePill(badge: badge, size: .micro)
                }
            },
            accessory: {
                LedgerIcon(systemName: "chevron.right", context: .cardList, tone: isSelected ? .link : .muted)
            }
        )
    }

    private var secondaryLines: [LedgerRowLine] {
        var lines = [
            LedgerRowLine(text: presentation.suggestedHint, role: .contentPreview, lineLimit: 2)
        ]
        if let sourceHint = presentation.sourceHint {
            lines.append(LedgerRowLine(text: sourceHint, tone: .muted, role: .metadata))
        }
        return lines
    }
}
