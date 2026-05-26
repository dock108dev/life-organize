import SwiftUI

enum LedgerVisualSystem {
    enum Spacing {
        static let rowCompact: CGFloat = 2
        static let rowStandard: CGFloat = 4
        static let rowAccessoryGap: CGFloat = 10
        static let rowBadgeGap: CGFloat = 5
        static let section: CGFloat = 10
        static let noticeContentGap: CGFloat = 8
        static let noticeActionGap: CGFloat = 6
    }

    enum Padding {
        static let rowCompactVertical: CGFloat = 6
        static let rowStandardVertical: CGFloat = 2
        static let rowHorizontal: CGFloat = 8
        static let pillMicroHorizontal: CGFloat = 4
        static let pillMicroVertical: CGFloat = 1
        static let pillSmallHorizontal: CGFloat = 6
        static let pillSmallVertical: CGFloat = 2
        static let pillStandardHorizontal: CGFloat = 7
        static let pillStandardVertical: CGFloat = 3
        static let noticeHorizontal: CGFloat = 12
        static let noticeVertical: CGFloat = 8
    }

    enum Typography {
        static let rowCompactPrimary: Font = .subheadline
        static let rowPrimary: Font = .subheadline
        static let rowDetailPrimary: Font = .body
        static let rowSecondary: Font = .caption2
        static let rowFooter: Font = .caption2
        static let metadataLabel: Font = .caption2.weight(.medium)
        static let metadataValue: Font = .subheadline
        static let metadataDetail: Font = .caption2
        static let sectionHeader: Font = .caption.weight(.medium)
        static let pillMicro: Font = .caption2
        static let pillSmall: Font = .caption2
        static let pillStandard: Font = .caption
        static let noticeMessage: Font = .caption
        static let noticeAction: Font = .caption.weight(.medium)
    }
}

enum LedgerTone: Equatable {
    case neutral
    case link
    case success
    case attention
    case info
    case muted
    case note
    case danger

    var foreground: Color {
        switch self {
        case .neutral:
            return .secondary
        case .link:
            return LedgerPalette.accent
        case .success:
            return LedgerPalette.green
        case .attention:
            return LedgerPalette.amber
        case .info:
            return LedgerPalette.teal
        case .muted:
            return .secondary
        case .note:
            return LedgerPalette.plum
        case .danger:
            return LedgerPalette.coral
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return .secondary.opacity(0.08)
        case .link:
            return .blue.opacity(0.08)
        case .success:
            return .green.opacity(0.08)
        case .attention:
            return .orange.opacity(0.10)
        case .info:
            return .teal.opacity(0.09)
        case .muted:
            return Color(.quaternarySystemFill)
        case .note:
            return .purple.opacity(0.08)
        case .danger:
            return .red.opacity(0.10)
        }
    }
}

enum LedgerPillSize {
    case micro
    case small
    case standard

    var font: Font {
        switch self {
        case .micro:
            return LedgerVisualSystem.Typography.pillMicro
        case .small:
            return LedgerVisualSystem.Typography.pillSmall
        case .standard:
            return LedgerVisualSystem.Typography.pillStandard
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .micro:
            return LedgerVisualSystem.Padding.pillMicroHorizontal
        case .small:
            return LedgerVisualSystem.Padding.pillSmallHorizontal
        case .standard:
            return LedgerVisualSystem.Padding.pillStandardHorizontal
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .micro:
            return LedgerVisualSystem.Padding.pillMicroVertical
        case .small:
            return LedgerVisualSystem.Padding.pillSmallVertical
        case .standard:
            return LedgerVisualSystem.Padding.pillStandardVertical
        }
    }
}

struct LedgerPill: View {
    let text: String
    let tone: LedgerTone
    var size: LedgerPillSize = .standard

    var body: some View {
        Text(text)
            .font(size.font)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(tone.background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tone.foreground.opacity(0.16), lineWidth: 0.75)
            }
            .accessibilityLabel(text)
    }
}

enum LedgerRowDensity {
    case compact
    case standard
    case detail

    var verticalSpacing: CGFloat {
        switch self {
        case .compact:
            return LedgerVisualSystem.Spacing.rowCompact
        case .standard, .detail:
            return LedgerVisualSystem.Spacing.rowStandard
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return LedgerVisualSystem.Padding.rowCompactVertical
        case .standard, .detail:
            return LedgerVisualSystem.Padding.rowStandardVertical
        }
    }

    var primaryFont: Font {
        switch self {
        case .compact:
            return LedgerVisualSystem.Typography.rowCompactPrimary
        case .standard:
            return LedgerVisualSystem.Typography.rowPrimary
        case .detail:
            return LedgerVisualSystem.Typography.rowDetailPrimary
        }
    }
}

enum LedgerSurfaceDensity {
    case feedRow
    case thingsRow
    case searchResultRow
    case reminderRow
    case detailSummary

    var rowDensity: LedgerRowDensity {
        switch self {
        case .feedRow:
            return .compact
        case .reminderRow:
            return .standard
        case .thingsRow, .searchResultRow:
            return .compact
        case .detailSummary:
            return .detail
        }
    }
}

enum LedgerRowEmphasis {
    case normal
    case active
    case inactive
    case attention

    var primaryWeight: Font.Weight {
        switch self {
        case .normal, .inactive:
            return .regular
        case .active, .attention:
            return .medium
        }
    }

    var primaryTone: LedgerTone? {
        switch self {
        case .normal, .active:
            return nil
        case .inactive:
            return .muted
        case .attention:
            return .attention
        }
    }
}

struct LedgerRowLine: Equatable {
    let text: String
    var tone: LedgerTone = .neutral
    var role: LedgerRowLineRole = .contentPreview
    var lineLimit: Int?

    func resolvedLineLimit(for dynamicTypeSize: DynamicTypeSize) -> Int? {
        switch role {
        case .metadata:
            return 1
        case .contentPreview:
            if dynamicTypeSize.isAccessibilitySize {
                return max(lineLimit ?? 2, 3)
            }
            return lineLimit ?? 2
        case .contentDetail:
            return nil
        }
    }
}

enum LedgerRowLineRole: Equatable {
    case metadata
    case contentPreview
    case contentDetail
}

struct LedgerRow<Badges: View, Accessory: View>: View {
    let primary: String
    var secondary: [LedgerRowLine] = []
    var footer: String?
    var density: LedgerRowDensity = .standard
    var emphasis: LedgerRowEmphasis = .normal
    let badges: Badges
    let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        density: LedgerRowDensity = .standard,
        emphasis: LedgerRowEmphasis = .normal,
        @ViewBuilder badges: () -> Badges,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.primary = primary
        self.secondary = secondary
        self.footer = footer
        self.density = density
        self.emphasis = emphasis
        self.badges = badges()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: LedgerVisualSystem.Spacing.rowAccessoryGap) {
            VStack(alignment: .leading, spacing: density.verticalSpacing) {
                primaryAndBadges

                ForEach(Array(secondary.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(LedgerVisualSystem.Typography.rowSecondary)
                        .foregroundStyle(line.tone.foreground)
                        .lineLimit(line.resolvedLineLimit(for: dynamicTypeSize))
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let footer, !footer.isEmpty {
                    Text(footer)
                        .font(LedgerVisualSystem.Typography.rowFooter)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
        .padding(.vertical, density.verticalPadding)
        .padding(.horizontal, LedgerVisualSystem.Padding.rowHorizontal)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowBorder, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var primaryAndBadges: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                primaryText
                badges
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                primaryText
                badges
            }
        }
    }

    private var primaryText: some View {
        Text(primary)
            .font(density.primaryFont.weight(emphasis.primaryWeight))
            .foregroundStyle(emphasis.primaryTone?.foreground ?? Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rowBackground: Color {
        switch emphasis {
        case .active, .attention:
            return LedgerTone.attention.background.opacity(0.72)
        case .inactive:
            return LedgerPalette.surface.opacity(0.44)
        case .normal:
            return LedgerPalette.surfaceStrong.opacity(0.54)
        }
    }

    private var rowBorder: Color {
        switch emphasis {
        case .active, .attention:
            return LedgerTone.attention.foreground.opacity(0.18)
        case .inactive:
            return LedgerPalette.hairline.opacity(0.7)
        case .normal:
            return LedgerPalette.hairline
        }
    }
}

extension LedgerRow where Badges == EmptyView, Accessory == EmptyView {
    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        density: LedgerRowDensity = .standard,
        emphasis: LedgerRowEmphasis = .normal
    ) {
        self.init(
            primary: primary,
            secondary: secondary,
            footer: footer,
            density: density,
            emphasis: emphasis,
            badges: { EmptyView() },
            accessory: { EmptyView() }
        )
    }
}

extension LedgerRow where Accessory == EmptyView {
    init(
        primary: String,
        secondary: [LedgerRowLine] = [],
        footer: String? = nil,
        density: LedgerRowDensity = .standard,
        emphasis: LedgerRowEmphasis = .normal,
        @ViewBuilder badges: () -> Badges
    ) {
        self.init(
            primary: primary,
            secondary: secondary,
            footer: footer,
            density: density,
            emphasis: emphasis,
            badges: badges,
            accessory: { EmptyView() }
        )
    }
}

struct LedgerSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(LedgerVisualSystem.Typography.sectionHeader)
            .foregroundStyle(LedgerPalette.accent.opacity(0.74))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LedgerEmptySectionRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}

extension LedgerTone {
    init(feedSource: LedgerFeedRowContent.Source) {
        self = LedgerBadgePresentation.feedSource(for: feedSource).tone
    }

    init(feedSecondaryTone: LedgerFeedRowContent.SecondaryTone) {
        switch feedSecondaryTone {
        case .neutral:
            self = .neutral
        case .muted:
            self = .muted
        case .info:
            self = .info
        case .attention:
            self = .attention
        case .danger:
            self = .danger
        }
    }
}
