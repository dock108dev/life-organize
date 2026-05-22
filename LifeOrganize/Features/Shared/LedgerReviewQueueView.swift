import SwiftData
import SwiftUI

struct LedgerReviewQueueView: View {
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
            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    origin == nil ? "All caught up" : "Nothing to review here",
                    systemImage: "text.badge.checkmark",
                    description: Text("Nothing needs a decision right now.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleEntries) { entry in
                            if let item = reviewItems.first(where: { $0.id == entry.itemID }) {
                                let presentation = LedgerReviewQueueRowPresentation(item: item, entry: entry)
                                NavigationLink {
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
                .background(Color(.systemBackground))
                .accessibilityIdentifier("review-queue-list")
            }
        }
        .navigationTitle(origin == nil ? "Review" : "Review Context")
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                        .accessibilityIdentifier("review-queue-close-button")
                }
            }
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
}

private struct LedgerReviewQueueRow: View {
    let presentation: LedgerReviewQueueRowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                Text(presentation.question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    ForEach(presentation.badges) { badge in
                        LedgerBadgePill(badge: badge, size: .micro)
                    }
                }
            }

            Text(presentation.suggestedHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let sourceHint = presentation.sourceHint {
                    Text(sourceHint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
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
}
