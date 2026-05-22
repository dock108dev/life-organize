import SwiftData
import SwiftUI

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var reminders: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \LedgerReviewItem.updatedAt, order: .reverse) private var reviewItems: [LedgerReviewItem]
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isComposerFocused: Bool
    @State private var reviewItemErrorMessage: String?
    let hasOpenAIAPIKey: Bool
    let apiKeyStore: any APIKeyStore
    let onAddKey: () -> Void

    init(
        hasOpenAIAPIKey: Bool = false,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        onAddKey: @escaping () -> Void = {}
    ) {
        self.hasOpenAIAPIKey = hasOpenAIAPIKey
        self.apiKeyStore = apiKeyStore
        self.onAddKey = onAddKey
    }

    private var feedSections: [LedgerFeedSection] {
        LedgerFeedProjection().sections(
            messages: messages,
            events: events,
            reminders: reminders,
            notes: notes
        )
    }

    private var feedItemIDs: [String] {
        feedSections.flatMap { $0.items.map(\.id) }
    }

    private var isFeedEmpty: Bool {
        feedSections.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasOpenAIAPIKey {
                APIKeyNotice(onAddKey: onAddKey)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 1)
                        .id(ScrollAnchor.top)

                    if isFeedEmpty {
                        LedgerEmptyStateView(content: .chat)
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        LazyVStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.sectionSpacing) {
                            ForEach(feedSections) { section in
                                LedgerFeedSectionView(
                                    section: section,
                                    reviewItems: reviewItems,
                                    apiKeyStore: apiKeyStore,
                                    onAddKey: onAddKey,
                                    onReviewItemError: { reviewItemErrorMessage = $0 }
                                )
                            }
                        }
                        .padding(.horizontal, LedgerFeedTimelineLayout.feedHorizontalPadding)
                        .padding(.top, LedgerFeedTimelineLayout.feedTopPadding)
                        .padding(.bottom, LedgerFeedTimelineLayout.feedBottomPadding)
                    }
                }
                .accessibilityIdentifier("timeline-feed")
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if isFeedEmpty {
                            ChatSuggestionBar { suggestion in
                                viewModel.applySuggestion(suggestion)
                                isComposerFocused = true
                            }
                        }

                        ChatInputBar(
                            text: $viewModel.draft,
                            placeholder: viewModel.inputPlaceholder(hasOpenAIAPIKey: hasOpenAIAPIKey),
                            isCommittingSend: viewModel.isCommittingSend,
                            isOrganizing: viewModel.isOrganizing,
                            isFocused: $isComposerFocused
                        ) {
                            viewModel.sendDraft(
                                modelContext: modelContext,
                                apiKeyStore: apiKeyStore,
                                dataGeneration: sessionState.dataGeneration,
                                isDataGenerationCurrent: sessionState.isCurrentDataGeneration
                            ) { messageID in
                                isComposerFocused = !AppRuntimeConfiguration.current.isAutomationRuntime
                                scrollToMessage(messageID, proxy: proxy)
                            }
                        }
                    }
                }
                .onAppear {
                    isComposerFocused = !AppRuntimeConfiguration.current.isScreenshotMode
                    scrollToTop(proxy: proxy, animated: false)
                }
                .onChange(of: feedItemIDs) { _, _ in
                    scrollToTop(proxy: proxy)
                }
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
        let action = {
            proxy.scrollTo(ScrollAnchor.top, anchor: .top)
        }
        if animated && !AppRuntimeConfiguration.current.disablesAnimations {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private enum ScrollAnchor {
        static let top = "chat-top"
    }
}

private struct APIKeyNotice: View {
    let onAddKey: () -> Void

    var body: some View {
        LedgerNoticeBanner(
            icon: "wifi.exclamationmark",
            message: "Timeline capture is local on this device until the AI service is reachable.",
            actionTitle: "Settings",
            accessibilityIdentifier: "api-key-notice",
            action: onAddKey
        )
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
        .background(.bar)
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
