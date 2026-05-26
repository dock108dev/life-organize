import SwiftUI

struct LedgerTimelineRowChromeLayout: Equatable {
    let rowHorizontalPadding: CGFloat
    let rowVerticalPadding: CGFloat
    let rowColumnSpacing: CGFloat
    let timestampWidth: CGFloat
    let markerSize: CGFloat
    let timestampTopPadding: CGFloat
    let markerTopPadding: CGFloat

    var dividerLeadingPadding: CGFloat {
        rowHorizontalPadding + timestampWidth + rowColumnSpacing + markerSize + rowColumnSpacing
    }
}

struct LedgerTimelineSectionChrome<Rows: View>: View {
    let title: String
    let subtitle: String?
    let summaryText: String
    let spacing: CGFloat
    let rows: Rows
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String?,
        summaryText: String,
        spacing: CGFloat,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.subtitle = subtitle
        self.summaryText = summaryText
        self.spacing = spacing
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            VStack(alignment: .leading, spacing: 1) {
                header

                Text(summaryText)
                    .font(LedgerVisualSystem.Typography.metadataDetail)
                    .foregroundStyle(.tertiary)
                    .lineLimit(Self.summaryLineLimit(for: dynamicTypeSize))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)

            rows
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .ledgerSurface(cornerRadius: 14)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 1) {
                LedgerSectionHeader(title: title)
                subtitleText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LedgerSectionHeader(title: title)
                subtitleText
            }
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle {
            Text(subtitle)
                .font(LedgerVisualSystem.Typography.metadataDetail.weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(Self.subtitleLineLimit(for: dynamicTypeSize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func subtitleLineLimit(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    static func summaryLineLimit(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }
}

struct LedgerTimelineRowContainer<Content: View>: View {
    let layout: LedgerTimelineRowChromeLayout
    let content: Content

    init(layout: LedgerTimelineRowChromeLayout, @ViewBuilder content: () -> Content) {
        self.layout = layout
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, layout.rowHorizontalPadding)
            .padding(.vertical, layout.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct LedgerTimelineRowShell<Content: View>: View {
    let timestampText: String
    let tone: LedgerTone
    let layout: LedgerTimelineRowChromeLayout
    let timestampWeight: Font.Weight
    let content: Content

    init(
        timestampText: String,
        tone: LedgerTone,
        layout: LedgerTimelineRowChromeLayout,
        timestampWeight: Font.Weight = .medium,
        @ViewBuilder content: () -> Content
    ) {
        self.timestampText = timestampText
        self.tone = tone
        self.layout = layout
        self.timestampWeight = timestampWeight
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: layout.rowColumnSpacing) {
            LedgerTimelineTimestampLabel(
                text: timestampText,
                width: layout.timestampWidth,
                weight: timestampWeight
            )
            .padding(.top, layout.timestampTopPadding)

            LedgerTimelineMarker(tone: tone, size: layout.markerSize)
                .padding(.top, layout.markerTopPadding)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LedgerTimelineTimestampLabel: View {
    let text: String
    let width: CGFloat
    let weight: Font.Weight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            wrappedTimestamp
        } else {
            singleLineTimestamp
        }
    }

    private var singleLineTimestamp: some View {
        Text(text)
            .font(LedgerVisualSystem.Typography.rowFooter.weight(weight).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .frame(width: width, alignment: .leading)
            .accessibilityLabel(text)
    }

    private var wrappedTimestamp: some View {
        Text(Self.accessibilityWrappedText(for: text))
            .font(LedgerVisualSystem.Typography.rowFooter.weight(weight).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.9)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }

    static func accessibilityWrappedText(for text: String) -> String {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count > 1 else { return text }
        return parts.map(String.init).joined(separator: "\n")
    }
}

struct LedgerTimelineMarker: View {
    let tone: LedgerTone
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [tone.foreground, tone.foreground.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(tone.foreground.opacity(0.18), lineWidth: 3)
            }
            .accessibilityHidden(true)
    }
}

struct LedgerTimelinePrimaryText: View {
    let text: String
    let weight: Font.Weight

    var body: some View {
        Text(text)
            .font(LedgerVisualSystem.Typography.rowCompactPrimary.weight(weight))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LedgerTimelineDetailText: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(LedgerVisualSystem.Typography.rowSecondary)
            .foregroundStyle(.secondary)
            .lineLimit(Self.lineLimit(for: dynamicTypeSize))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func lineLimit(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }
}

struct LedgerTimelineLinkedThingPill: View {
    let text: String
    var size: LedgerPillSize = .standard

    var body: some View {
        LedgerPill(text: text, tone: .link, size: size)
    }
}
