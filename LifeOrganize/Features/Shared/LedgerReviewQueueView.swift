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
    let onAddKey: () -> Void
    let onClose: (() -> Void)?

    @State private var errorMessage: String?
    @State private var selectedItemID: UUID?
    @State private var lastAppliedFocusedItemID: UUID?
    @State private var previousVisibleItemIDs: [UUID] = []

    init(
        origin: LedgerReviewOrigin? = nil,
        focusedItemID: UUID? = nil,
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore(),
        onAddKey: @escaping () -> Void = {},
        onClose: (() -> Void)? = nil
    ) {
        self.origin = origin
        self.focusedItemID = focusedItemID
        self.deviceTokenStore = deviceTokenStore
        self.onAddKey = onAddKey
        self.onClose = onClose
    }

    private var queueEntries: [LedgerReviewQueueEntry] {
        (try? queueService.entries(from: reviewItems, origin: origin)) ?? []
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
        if visibleEntries.isEmpty {
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
                        .accessibilityIdentifier("review-queue-row-\(entry.itemID.uuidString)")
                        .accessibilityLabel(presentation.accessibilityLabel)
                        .accessibilityHint(selectedItemID == entry.itemID ? "Selected review" : "Shows review details")
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
        if let selectedReview {
            detailView(item: selectedReview.item, entry: selectedReview.entry)
                .id(selectedReview.item.id)
        } else if visibleEntries.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            LedgerNoSelectionPlaceholderView(
                "Select a Review",
                systemImage: "sidebar.left",
                description: "Choose an item from the review queue."
            )
            .background(Color(.systemGroupedBackground))
        }
    }

    private var compactQueueView: some View {
        Group {
            if visibleEntries.isEmpty {
                emptyState
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

    private func detailView(item: LedgerReviewItem, entry: LedgerReviewQueueEntry) -> some View {
        LedgerReviewQueueDetailView(
            item: item,
            entry: entry,
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            deviceTokenStore: deviceTokenStore,
            onAddKey: onAddKey
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            questionAndBadges

            Text(presentation.suggestedHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let sourceHint = presentation.sourceHint {
                    Text(sourceHint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                        .accessibilityLabel(sourceHint)
                }

                Spacer(minLength: 8)

                Label(presentation.nextActionTitle, systemImage: presentation.isBlocked ? "exclamationmark.circle" : "arrow.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(presentation.isBlocked ? LedgerTone.attention.foreground : .secondary)
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(presentation.urgencyText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(presentation.isBlocked ? LedgerTone.attention.foreground : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .ledgerSurface(cornerRadius: 12, tint: presentation.isBlocked ? .attention : .info)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.10))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if presentation.isBlocked {
                Rectangle()
                    .fill(LedgerTone.attention.foreground)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var questionAndBadges: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                questionText
                badgeRow
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                questionText

                Spacer(minLength: 8)

                badgeRow
            }
        }
    }

    private var questionText: some View {
        Text(presentation.question)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var badgeRow: some View {
        HStack(spacing: 4) {
            ForEach(presentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .micro)
            }
        }
    }
}
