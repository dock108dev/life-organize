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
        body: "Capture anything worth remembering. LifeOrganize turns it into history, Things, and follow-up reminders.",
        secondaryBody: "Try a note, a task, a receipt, or “what is due today?”"
    )

    static let things = LedgerEmptyStateContent(
        symbolName: "tray",
        title: "No saved things yet",
        body: "Things are people, pets, projects, places, and accounts collected from your timeline.",
        secondaryBody: "Start from the timeline, or add one directly."
    )

    static let rules = LedgerEmptyStateContent(
        symbolName: "checklist",
        title: "Nothing to carry forward yet",
        body: "Carry Forward keeps ongoing work and reminders from getting lost.",
        secondaryBody: "Add a reminder, or capture something that should resurface later."
    )

    static let searchLanding = LedgerEmptyStateContent(
        symbolName: "magnifyingglass",
        title: "Search",
        body: "Look up a detail, date, place, or note."
    )

    static let noSearchResults = LedgerEmptyStateContent(
        symbolName: "magnifyingglass",
        title: "No results",
        body: "Try a shorter phrase or a different detail."
    )

    static let noThingSearchResults = LedgerEmptyStateContent(
        symbolName: "tray",
        title: "No matching things",
        body: "Try another name or detail."
    )

    static let reviewAllCaughtUp = LedgerEmptyStateContent(
        symbolName: "text.badge.checkmark",
        title: "All caught up",
        body: "Nothing needs a decision right now."
    )

    static let reviewContextEmpty = LedgerEmptyStateContent(
        symbolName: "text.badge.checkmark",
        title: "Nothing to review here",
        body: "Nothing needs a decision right now."
    )
}

struct LedgerCenteredEmptyState<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LedgerScreenBackground().ignoresSafeArea())
    }
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
        .frame(maxWidth: LedgerAdaptiveLayout.EmptyState.contentMaxWidth)
        .padding(.horizontal, LedgerAdaptiveLayout.EmptyState.horizontalPadding)
        .padding(.vertical, LedgerAdaptiveLayout.EmptyState.verticalPadding)
        .frame(maxWidth: LedgerAdaptiveLayout.EmptyState.surfaceMaxWidth)
        .ledgerSurface(cornerRadius: LedgerAdaptiveLayout.EmptyState.cornerRadius)
        .frame(maxWidth: .infinity)
    }
}

extension LedgerEmptyStateView where Actions == EmptyView {
    init(content: LedgerEmptyStateContent) {
        self.content = content
        self.actions = EmptyView()
    }
}

struct LedgerNoSelectionPlaceholderView: View {
    let title: String
    let symbolName: String
    let description: String?

    init(_ title: String, systemImage symbolName: String, description: String? = nil) {
        self.title = title
        self.symbolName = symbolName
        self.description = description
    }

    var body: some View {
        VStack(spacing: LedgerVisualSystem.Spacing.section) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 54, height: 54)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: LedgerAdaptiveLayout.EmptyState.contentMaxWidth)
        .padding(.horizontal, LedgerAdaptiveLayout.EmptyState.horizontalPadding)
        .padding(.vertical, LedgerAdaptiveLayout.EmptyState.secondaryVerticalPadding)
        .frame(maxWidth: LedgerAdaptiveLayout.EmptyState.surfaceMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
