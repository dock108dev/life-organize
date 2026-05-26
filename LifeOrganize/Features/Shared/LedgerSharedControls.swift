import SwiftUI

struct LedgerNoticeBanner: View {
    let icon: String
    let message: String
    var tone: LedgerTone = .neutral
    var actionTitle: String?
    var accessibilityIdentifier: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: LedgerVisualSystem.Spacing.noticeContentGap) {
            Image(systemName: icon)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)

            Text(message)
                .font(LedgerVisualSystem.Typography.noticeMessage)
                .foregroundStyle(tone == .neutral ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: LedgerVisualSystem.Spacing.noticeActionGap)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LedgerVisualSystem.Typography.noticeAction)
            }
        }
        .padding(.horizontal, LedgerVisualSystem.Padding.noticeHorizontal)
        .padding(.vertical, LedgerVisualSystem.Padding.noticeVertical)
        .background(tone == .neutral ? LedgerPalette.surface : tone.background.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tone.foreground.opacity(tone == .neutral ? 0.08 : 0.18), lineWidth: 1)
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct LedgerSearchResultsList: View {
    let results: [LocalSearchResult]
    var emptyContent: LedgerEmptyStateContent = .noSearchResults
    var onSelect: ((LocalSearchResult) -> Void)?

    var body: some View {
        if results.isEmpty {
            LedgerEmptyStateView(content: emptyContent)
        } else {
            List(results) { result in
                searchResultRow(result)
                .accessibilityIdentifier("ledger-search-result-\(result.sourceKind.rawValue)-\(result.stableID.uuidString)")
                .accessibilityLabel("\(result.sourceKind.displayName): \(result.title)")
                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier("ledger-search-results-list")
        }
    }

    @ViewBuilder
    private func searchResultRow(_ result: LocalSearchResult) -> some View {
        if let onSelect {
            Button {
                onSelect(result)
            } label: {
                LocalSearchResultRow(result: result)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: result) {
                LocalSearchResultRow(result: result)
            }
        }
    }
}

struct LedgerToolbarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var accessibilityValue: String?
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(isActive ? LedgerTone.attention.background : LedgerPalette.surface.opacity(0.0), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isActive ? LedgerTone.attention.foreground.opacity(0.20) : Color.clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? LedgerTone.attention.foreground : .secondary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}
