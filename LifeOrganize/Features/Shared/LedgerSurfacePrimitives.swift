import SwiftUI

extension LedgerVisualSystem {
    enum Icon {
        static let toolbar: Font = .body.weight(.semibold)
        static let sidebar: Font = .subheadline.weight(.medium)
        static let emptyState: Font = .title3.weight(.medium)
        static let warningReview: Font = .subheadline.weight(.semibold)
        static let cardList: Font = .caption.weight(.semibold)
        static let sectionHeader: Font = .caption.weight(.semibold)
    }
}

enum LedgerIconContext: CaseIterable {
    case toolbar
    case sidebar
    case emptyState
    case warningReview
    case cardList
    case sectionHeader

    var font: Font {
        switch self {
        case .toolbar:
            return LedgerVisualSystem.Icon.toolbar
        case .sidebar:
            return LedgerVisualSystem.Icon.sidebar
        case .emptyState:
            return LedgerVisualSystem.Icon.emptyState
        case .warningReview:
            return LedgerVisualSystem.Icon.warningReview
        case .cardList:
            return LedgerVisualSystem.Icon.cardList
        case .sectionHeader:
            return LedgerVisualSystem.Icon.sectionHeader
        }
    }

    var frameSize: CGFloat {
        switch self {
        case .toolbar, .sidebar, .warningReview:
            return 18
        case .emptyState:
            return 28
        case .cardList, .sectionHeader:
            return 16
        }
    }
}

struct LedgerIcon: View {
    let systemName: String
    var context: LedgerIconContext
    var tone: LedgerTone?

    var body: some View {
        Image(systemName: systemName)
            .font(context.font)
            .foregroundStyle(tone?.foreground ?? Color.secondary)
            .frame(width: context.frameSize, height: context.frameSize)
            .accessibilityHidden(true)
    }
}

extension LedgerRow {
    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        surfaceDensity: LedgerSurfaceDensity,
        emphasis: LedgerRowEmphasis = .normal,
        @ViewBuilder badges: () -> Badges,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            primary: primary,
            secondary: secondary,
            footer: footer,
            density: surfaceDensity.rowDensity,
            emphasis: emphasis,
            badges: badges,
            accessory: accessory
        )
    }
}

extension LedgerRow where Badges == EmptyView, Accessory == EmptyView {
    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        surfaceDensity: LedgerSurfaceDensity,
        emphasis: LedgerRowEmphasis = .normal
    ) {
        self.init(
            primary: primary,
            secondary: secondary,
            footer: footer,
            density: surfaceDensity.rowDensity,
            emphasis: emphasis
        )
    }
}

extension LedgerRow where Accessory == EmptyView {
    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        surfaceDensity: LedgerSurfaceDensity,
        emphasis: LedgerRowEmphasis = .normal,
        @ViewBuilder badges: () -> Badges
    ) {
        self.init(
            primary: primary,
            secondary: secondary,
            footer: footer,
            density: surfaceDensity.rowDensity,
            emphasis: emphasis,
            badges: badges,
            accessory: { EmptyView() }
        )
    }
}

struct LedgerSectionTitle<Accessory: View>: View {
    let title: String
    var icon: String?
    var tone: LedgerTone = .link
    let accessory: Accessory

    init(
        title: String,
        icon: String? = nil,
        tone: LedgerTone = .link,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.icon = icon
        self.tone = tone
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LedgerVisualSystem.Spacing.iconTextGap) {
            if let icon {
                LedgerIcon(systemName: icon, context: .sectionHeader, tone: tone)
            }

            LedgerSectionHeader(title: title)

            Spacer(minLength: LedgerVisualSystem.Spacing.iconTextGap)

            accessory
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension LedgerSectionTitle where Accessory == EmptyView {
    init(title: String, icon: String? = nil, tone: LedgerTone = .link) {
        self.init(title: title, icon: icon, tone: tone) {
            EmptyView()
        }
    }
}

struct LedgerWorkspaceSplitDivider: View {
    var body: some View {
        Divider()
            .overlay(LedgerPalette.hairline.opacity(LedgerAdaptiveLayout.Workspace.splitDividerOpacity))
    }
}

private struct LedgerWorkspaceDetailPaneModifier: ViewModifier {
    let accessibilityIdentifier: String

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LedgerScreenBackground().ignoresSafeArea())
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

extension View {
    func ledgerWorkspaceDetailPane(_ accessibilityIdentifier: String) -> some View {
        modifier(LedgerWorkspaceDetailPaneModifier(accessibilityIdentifier: accessibilityIdentifier))
    }
}
