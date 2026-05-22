import SwiftUI

struct LedgerEmptyStateContent: Equatable {
    let symbolName: String
    let title: String
    let body: String
    let secondaryBody: String?

    init(symbolName: String, title: String, body: String, secondaryBody: String? = nil) {
        self.symbolName = symbolName
        self.title = title
        self.body = body
        self.secondaryBody = secondaryBody
    }
}

extension LedgerEmptyStateContent {
    static let chat = LedgerEmptyStateContent(
        symbolName: "clock",
        title: "Timeline",
        body: "Tell me what happened or ask what is due."
    )

    static let things = LedgerEmptyStateContent(
        symbolName: "tray",
        title: "No saved things yet",
        body: "Add one directly or start from the timeline."
    )

    static let rules = LedgerEmptyStateContent(
        symbolName: "checklist",
        title: "Nothing to carry forward yet",
        body: "Add a reminder or capture something that should resurface."
    )

    static let settingsNoDeviceToken = LedgerEmptyStateContent(
        symbolName: "server.rack",
        title: "AI service token",
        body: "Entries stay local on this device. A private token lets the backend organize new details."
    )

    static let searchLanding = LedgerEmptyStateContent(
        symbolName: "magnifyingglass",
        title: "Search",
        body: "Look up a detail, date, place, or note."
    )

    static let noSearchResults = LedgerEmptyStateContent(
        symbolName: "magnifyingglass",
        title: "No results",
        body: "Try a shorter phrase or a different detail from the entry."
    )

    static let noThingSearchResults = LedgerEmptyStateContent(
        symbolName: "tray",
        title: "No matching things",
        body: "Try another name or detail."
    )
}

struct LedgerEmptyStateView<Actions: View>: View {
    let content: LedgerEmptyStateContent
    let actions: Actions

    init(content: LedgerEmptyStateContent, @ViewBuilder actions: () -> Actions) {
        self.content = content
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: LedgerVisualSystem.Spacing.section) {
            Image(systemName: content.symbolName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(LedgerPalette.accent)
                .frame(width: 62, height: 62)
                .background(LedgerPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(LedgerPalette.accent.opacity(0.16), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(content.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(content.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let secondaryBody = content.secondaryBody {
                    Text(secondaryBody)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }

            actions
                .font(.subheadline)
                .padding(.top, 4)
        }
        .frame(maxWidth: LedgerVisualSystem.Spacing.emptyStateWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .ledgerSurface(cornerRadius: 18)
        .padding(.horizontal, 16)
    }
}

extension LedgerEmptyStateView where Actions == EmptyView {
    init(content: LedgerEmptyStateContent) {
        self.content = content
        self.actions = EmptyView()
    }
}
