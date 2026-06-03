import SwiftData
import SwiftUI

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var sessionState: AppSessionState
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var reminders: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isComposerFocused: Bool
    @State private var reviewItemErrorMessage: String?
    @State private var showsOlderTimeline = false
    @AppStorage("ledger.context.timeline.dismissed") private var isTimelineContextDismissed = false
    let deviceTokenStore: any DeviceTokenStore

    init(
        deviceTokenStore: any DeviceTokenStore = KeychainDeviceTokenStore()
    ) {
        self.deviceTokenStore = deviceTokenStore
    }

    private var feedSections: [LedgerFeedSection] {
        LedgerFeedProjection(calendar: calendar, now: runtimeNow).sections(
            messages: messages,
            events: events,
            reminders: reminders,
            notes: notes
        )
    }

    private var visibleFeedSections: [LedgerFeedSection] {
        showsOlderTimeline ? feedSections : recentFeedSections
    }

    private var recentFeedSections: [LedgerFeedSection] {
        feedSections.filter(isDefaultTimelineSection)
    }

    private var olderFeedSections: [LedgerFeedSection] {
        feedSections.filter { !isDefaultTimelineSection($0) }
    }

    private var visibleFutureFeedSections: [LedgerFeedSection] {
        visibleFeedSections.filter { $0.group == .upcoming }
    }

    private var visibleCurrentFeedSections: [LedgerFeedSection] {
        visibleFeedSections.filter { $0.group != .upcoming }
    }

    private var feedItemIDs: [String] {
        visibleFeedSections.flatMap { $0.items.map(\.id) }
    }

    private var isFeedEmpty: Bool {
        feedSections.isEmpty
    }

    private var isCompressedVertically: Bool {
        verticalSizeClass == .compact
    }

    private var isDraftEmpty: Bool {
        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var runtimeNow: Date {
        AppRuntimeConfiguration.current.dateProvider.now
    }

    private var showsComposerSuggestions: Bool {
        isFeedEmpty && isDraftEmpty && !isCompressedVertically
    }

    private var shouldAutofocusComposer: Bool {
        !AppRuntimeConfiguration.current.isScreenshotMode && !isCompressedVertically
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .id(ScrollAnchor.top)

                    if isFeedEmpty {
                        LedgerEmptyStateView(content: .chat)
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .ledgerAdaptiveWidth(.readable)
                    } else {
                        LazyVStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.sectionSpacing) {
                            ForEach(visibleFutureFeedSections) { section in
                                feedSectionView(section)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(ScrollAnchor.current)

                            if !isTimelineContextDismissed {
                                LedgerContextPanel(content: .timeline) {
                                    isTimelineContextDismissed = true
                                }
                            }

                            ForEach(visibleCurrentFeedSections) { section in
                                feedSectionView(section)
                            }

                            if !olderFeedSections.isEmpty {
                                TimelineOlderHistoryToggle(
                                    isExpanded: showsOlderTimeline,
                                    hiddenSectionCount: olderFeedSections.count,
                                    hiddenItemCount: olderFeedSections.reduce(0) { $0 + $1.items.count }
                                ) {
                                    showsOlderTimeline.toggle()
                                }
                            }
                        }
                        .ledgerAdaptiveWidth(.readable)
                        .padding(.top, LedgerFeedTimelineLayout.feedTopPadding)
                        .padding(.bottom, LedgerFeedTimelineLayout.feedBottomPadding)
                    }
                }
                .accessibilityIdentifier("timeline-feed")
                .background(LedgerScreenBackground().ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TimelineComposerInset {
                        VStack(spacing: 0) {
                            if showsComposerSuggestions {
                                ChatSuggestionBar { suggestion in
                                    viewModel.applySuggestion(suggestion)
                                    isComposerFocused = true
                                }
                            }

                            ChatInputBar(
                                text: $viewModel.draft,
                                placeholder: viewModel.inputPlaceholder,
                                isCommittingSend: viewModel.isCommittingSend,
                                isOrganizing: viewModel.isOrganizing,
                                errorMessage: viewModel.sendError,
                                isFocused: $isComposerFocused
                            ) {
                                viewModel.sendDraft(
                                    modelContext: modelContext,
                                    deviceTokenStore: deviceTokenStore,
                                    dataGeneration: sessionState.dataGeneration,
                                    isDataGenerationCurrent: sessionState.isCurrentDataGeneration
                                ) { messageID in
                                    isComposerFocused = !AppRuntimeConfiguration.current.isAutomationRuntime
                                    scrollToMessage(messageID, proxy: proxy)
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    isComposerFocused = shouldAutofocusComposer
                    scrollToDefaultPosition(proxy: proxy, animated: false)
                }
                .onChange(of: feedItemIDs) { _, _ in
                    scrollToDefaultPosition(proxy: proxy)
                }
            }
        }
        .background(LedgerScreenBackground().ignoresSafeArea())
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

    private func scrollToMessage(_ messageID: UUID, proxy: ScrollViewProxy) {
        let action = {
            proxy.scrollTo(LedgerFeedItem.messageID(for: messageID), anchor: .top)
        }
        if AppRuntimeConfiguration.current.disablesAnimations {
            action()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy, animated: Bool = true) {
        scroll(to: ScrollAnchor.top, proxy: proxy, animated: animated)
    }

    private func scrollToDefaultPosition(proxy: ScrollViewProxy, animated: Bool = true) {
        scroll(to: visibleCurrentFeedSections.isEmpty ? ScrollAnchor.top : ScrollAnchor.current, proxy: proxy, animated: animated)
    }

    private func scroll(to anchor: String, proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(anchor, anchor: .top)
        }
        if animated && !AppRuntimeConfiguration.current.disablesAnimations {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func isDefaultTimelineSection(_ section: LedgerFeedSection) -> Bool {
        TimelineDefaultVisibility(calendar: calendar, now: runtimeNow).isVisibleByDefault(section)
    }

    private enum ScrollAnchor {
        static let top = "chat-top"
        static let current = "chat-current"
    }

    private func feedSectionView(_ section: LedgerFeedSection) -> some View {
        LedgerFeedSectionView(
            section: section,
            reviewItems: reviewItems,
            deviceTokenStore: deviceTokenStore,
            onReviewItemError: { reviewItemErrorMessage = $0 }
        )
    }
}

private struct TimelineOlderHistoryToggle: View {
    let isExpanded: Bool
    let hiddenSectionCount: Int
    let hiddenItemCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.up.circle" : "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isExpanded ? "Hide older history" : "Show older history")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(summaryText)
                        .font(LedgerVisualSystem.Typography.rowSecondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, LedgerFeedTimelineLayout.rowHorizontalPadding)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline-older-history-toggle")
    }

    private var summaryText: String {
        let sections = LedgerDisplayFormatting.count(hiddenSectionCount, singular: "older day", plural: "older days")
        let items = LedgerDisplayFormatting.count(hiddenItemCount, singular: "item", plural: "items")
        return "\(sections) · \(items)"
    }
}

private struct TimelineComposerInset<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .ledgerAdaptiveWidth(.readable)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(Color.secondary.opacity(0.18))
            }
    }
}

private struct ChatSuggestionBar: View {
    let onSelect: (ChatSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatSuggestion.allCases, id: \.self) { suggestion in
                    Button(suggestion.title) {
                        onSelect(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
            .navigationTitle(AppTab.log.title)
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
    .environmentObject(AppSessionState())
}
