import SwiftUI

enum LedgerFeedTimelineLayout {
    static let sectionSpacing: CGFloat = 16
    static let feedTopPadding: CGFloat = 4
    static let feedBottomPadding: CGFloat = 10
    static let sectionContentSpacing: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 6
    static let rowVerticalPadding: CGFloat = 5
    static let rowContentSpacing: CGFloat = 2
    static let rowColumnSpacing: CGFloat = 8
    static let rowBadgeGap: CGFloat = 4
    static let timestampWidth: CGFloat = 56
    static let markerSize: CGFloat = 4
    static let timestampTopPadding: CGFloat = 0
    static let markerTopPadding: CGFloat = 7
    static let rowChrome = LedgerTimelineRowChromeLayout(
        rowHorizontalPadding: rowHorizontalPadding,
        rowVerticalPadding: rowVerticalPadding,
        rowColumnSpacing: rowColumnSpacing,
        timestampWidth: timestampWidth,
        markerSize: markerSize,
        timestampTopPadding: timestampTopPadding,
        markerTopPadding: markerTopPadding
    )
    static let dividerLeadingPadding = rowChrome.dividerLeadingPadding
}

struct LedgerFeedSectionView: View {
    let section: LedgerFeedSection
    let reviewItems: [LedgerReviewItem]
    let deviceTokenStore: any DeviceTokenStore
    let onAddKey: () -> Void
    let onReviewItemError: (String) -> Void
    @ScaledMetric(relativeTo: .caption2) private var timestampWidth = LedgerFeedTimelineLayout.timestampWidth
    @ScaledMetric(relativeTo: .caption2) private var markerSize = LedgerFeedTimelineLayout.markerSize

    var body: some View {
        LedgerTimelineSectionChrome(
            title: section.title,
            subtitle: section.subtitle,
            summaryText: section.summary.displayText(mode: .compact),
            spacing: LedgerFeedTimelineLayout.sectionContentSpacing
        ) {
            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    let reviewPresentation = reviewPresentation(for: item)
                    LedgerFeedRowLink(
                        item: item,
                        reviewPresentation: reviewPresentation,
                        deviceTokenStore: deviceTokenStore,
                        onAddKey: onAddKey,
                        onReviewItemError: onReviewItemError
                    )
                    .id(item.id)

                    if item.id != section.items.last?.id {
                        TimelineSectionRowDivider(leadingPadding: rowLayout.dividerLeadingPadding)
                    }
                }
            }
        }
    }

    private var rowLayout: LedgerTimelineRowChromeLayout {
        LedgerTimelineRowChromeLayout(
            rowHorizontalPadding: LedgerFeedTimelineLayout.rowHorizontalPadding,
            rowVerticalPadding: LedgerFeedTimelineLayout.rowVerticalPadding,
            rowColumnSpacing: LedgerFeedTimelineLayout.rowColumnSpacing,
            timestampWidth: timestampWidth,
            markerSize: markerSize,
            timestampTopPadding: LedgerFeedTimelineLayout.timestampTopPadding,
            markerTopPadding: LedgerFeedTimelineLayout.markerTopPadding
        )
    }

    private func reviewPresentation(for item: LedgerFeedItem) -> LedgerReviewItemPresentation? {
        guard let target = item.reviewItemTarget else { return nil }
        return LedgerReviewItemPresentationService().primaryPresentation(
            for: target.type,
            targetID: target.id,
            in: reviewItems
        )
    }
}

private struct LedgerFeedRowLink: View {
    let item: LedgerFeedItem
    let reviewPresentation: LedgerReviewItemPresentation?
    let deviceTokenStore: any DeviceTokenStore
    let onAddKey: () -> Void
    let onReviewItemError: (String) -> Void

    var body: some View {
        if let reviewPresentation, let origin = item.reviewOrigin {
            NavigationLink {
                LedgerReviewQueueView(
                    origin: origin,
                    focusedItemID: reviewPresentation.item.id,
                    deviceTokenStore: deviceTokenStore,
                    onAddKey: onAddKey
                )
            } label: {
                LedgerFeedRow(item: item, reviewPresentation: reviewPresentation)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(item.accessibilityIdentifier)
            .ledgerReviewItemContextMenu(reviewPresentation.item, onError: onReviewItemError)
        } else {
            switch item {
            case .event(let event):
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    LedgerFeedRow(item: item, reviewPresentation: reviewPresentation)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.accessibilityIdentifier)
                .ledgerReviewItemContextMenu(reviewPresentation?.item, onError: onReviewItemError)
            default:
                LedgerFeedRow(item: item, reviewPresentation: reviewPresentation)
                    .accessibilityIdentifier(item.accessibilityIdentifier)
                    .ledgerReviewItemContextMenu(reviewPresentation?.item, onError: onReviewItemError)
            }
        }
    }
}

private struct LedgerFeedRow: View {
    let item: LedgerFeedItem
    let reviewPresentation: LedgerReviewItemPresentation?
    @ScaledMetric(relativeTo: .caption2) private var timestampWidth = LedgerFeedTimelineLayout.timestampWidth
    @ScaledMetric(relativeTo: .caption2) private var markerSize = LedgerFeedTimelineLayout.markerSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LedgerTimelineRowContainer(layout: rowLayout) {
            if isQuietStatusRow {
                quietStatusRow
            } else {
                ViewThatFits(in: .horizontal) {
                    wideRow
                    compactRow
                }
            }
        }
    }

    private var content: LedgerFeedRowContent {
        LedgerFeedRowContent(item: item)
    }

    private var rowLayout: LedgerTimelineRowChromeLayout {
        LedgerTimelineRowChromeLayout(
            rowHorizontalPadding: LedgerFeedTimelineLayout.rowHorizontalPadding,
            rowVerticalPadding: LedgerFeedTimelineLayout.rowVerticalPadding,
            rowColumnSpacing: LedgerFeedTimelineLayout.rowColumnSpacing,
            timestampWidth: timestampWidth,
            markerSize: markerSize,
            timestampTopPadding: LedgerFeedTimelineLayout.timestampTopPadding,
            markerTopPadding: LedgerFeedTimelineLayout.markerTopPadding
        )
    }

    private var wideRow: some View {
        LedgerTimelineRowShell(
            timestampText: content.timestampText,
            tone: sourceTone,
            layout: rowLayout,
            timestampWeight: timestampWeight
        ) {
            VStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.rowContentSpacing) {
                if shouldSeparateMetadata {
                    metadataBadges
                    primaryLabel
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: LedgerFeedTimelineLayout.rowBadgeGap) {
                        metadataBadges
                            .fixedSize(horizontal: true, vertical: false)
                        primaryLabel
                    }
                }
                detailLabels
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactRow: some View {
        LedgerTimelineRowShell(
            timestampText: content.timestampText,
            tone: sourceTone,
            layout: rowLayout,
            timestampWeight: timestampWeight
        ) {
            VStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.rowContentSpacing) {
                metadataBadges
                primaryLabel
                detailLabels
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quietStatusRow: some View {
        LedgerTimelineRowShell(
            timestampText: content.timestampText,
            tone: .muted,
            layout: rowLayout,
            timestampWeight: .regular
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                quietStackedStatusContent
            } else {
                ViewThatFits(in: .horizontal) {
                    quietInlineStatusContent
                    quietStackedStatusContent
                }
            }
        }
    }

    private var quietInlineStatusContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: LedgerFeedTimelineLayout.rowBadgeGap) {
            sourceLabel
                .fixedSize(horizontal: true, vertical: false)

            statusSummaryText
        }
    }

    private var quietStackedStatusContent: some View {
        VStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.rowContentSpacing) {
            sourceLabel
            statusSummaryText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSummaryText: some View {
        Text(content.primaryText.ledgerFeedStatusSummaryText)
            .font(LedgerVisualSystem.Typography.rowSecondary)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var metadataBadges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: LedgerFeedTimelineLayout.rowBadgeGap) {
                sourceLabel

                if let statusBadge {
                    statusLabel(statusBadge)
                }
            }

            VStack(alignment: .leading, spacing: LedgerFeedTimelineLayout.rowBadgeGap) {
                sourceLabel

                if let statusBadge {
                    statusLabel(statusBadge)
                }
            }
        }
    }

    private var sourceLabel: some View {
        LedgerFeedMetadataLabel(badge: content.sourceBadge)
    }

    private var primaryLabel: some View {
        LedgerTimelinePrimaryText(text: content.primaryText, weight: primaryWeight)
    }

    @ViewBuilder
    private var detailLabels: some View {
        if let detailText = content.detailText {
            LedgerTimelineDetailText(text: detailText)
        }

        if let linkedThingText = content.linkedThingText {
            LedgerTimelineLinkedThingPill(text: linkedThingText, size: .micro)
        }

        if shouldShowReviewLine, let reviewPresentation {
            let line = reviewPresentation.rowLine
            Text(line.text)
                .font(LedgerVisualSystem.Typography.rowSecondary)
                .foregroundStyle(line.tone.foreground)
                .lineLimit(line.resolvedLineLimit(for: dynamicTypeSize))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusLabel(_ badge: LedgerBadgePresentation) -> some View {
        LedgerFeedMetadataLabel(badge: badge, allowsAccessibilityWrapping: true)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadge: LedgerBadgePresentation? {
        if let reviewPresentation {
            return reviewPresentation.badge
        }
        if content.secondaryBadge?.semantic == .actionReview {
            return nil
        }
        return content.secondaryBadge
    }

    private var sourceTone: LedgerTone {
        content.sourceBadge.tone
    }

    private var primaryWeight: Font.Weight {
        switch content.source {
        case .user, .status, .system:
            return .regular
        case .event, .reminder, .note:
            return .medium
        }
    }

    private var timestampWeight: Font.Weight {
        isQuietStatusRow ? .regular : .medium
    }

    private var isQuietStatusRow: Bool {
        switch content.source {
        case .status, .system:
            return true
        case .user, .event, .reminder, .note:
            return false
        }
    }

    private var shouldShowReviewLine: Bool {
        guard reviewPresentation != nil else { return false }
        switch content.source {
        case .user:
            return false
        case .status, .system, .event, .reminder, .note:
            return true
        }
    }

    private var shouldSeparateMetadata: Bool {
        statusBadge != nil || dynamicTypeSize.isAccessibilitySize
    }
}

private struct LedgerFeedMetadataLabel: View {
    let badge: LedgerBadgePresentation
    var allowsAccessibilityWrapping = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(badge.label)
            .font(LedgerVisualSystem.Typography.rowFooter.weight(.medium))
            .foregroundStyle(badge.tone.foreground.opacity(badge.tone == .muted ? 0.62 : 0.92))
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .minimumScaleFactor(allowsAccessibilityWrapping && dynamicTypeSize.isAccessibilitySize ? 0.9 : 0.85)
            .fixedSize(horizontal: false, vertical: allowsAccessibilityWrapping && dynamicTypeSize.isAccessibilitySize)
            .accessibilityLabel(badge.label)
    }

    private var lineLimit: Int {
        allowsAccessibilityWrapping && dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }
}

private extension String {
    var ledgerFeedStatusSummaryText: String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed
            .replacingOccurrences(of: "Some saved details need review.", with: "Needs review.")
            .replacingOccurrences(of: "Open the timeline entry to review the saved text.", with: "Review saved text.")
            .replacingOccurrences(of: "Open the log entry to review the saved text.", with: "Review saved text.")
            .replacingOccurrences(of: "Events saved:", with: "Events:")
            .replacingOccurrences(of: "Event saved:", with: "Event:")
            .replacingOccurrences(of: "Reminders saved:", with: "Reminders:")
            .replacingOccurrences(of: "Reminder saved:", with: "Reminder:")
            .replacingOccurrences(of: "Restrictions saved:", with: "Restrictions:")
            .replacingOccurrences(of: "Restriction saved:", with: "Restriction:")
            .replacingOccurrences(of: "Notes saved:", with: "Notes:")
            .replacingOccurrences(of: "Note saved:", with: "Note:")
            .replacingOccurrences(of: "Things saved:", with: "Things:")
            .replacingOccurrences(of: "Thing saved:", with: "Thing:")
            .replacingOccurrences(of: "Preference saved:", with: "Preference:")
            .replacingOccurrences(of: "Saved for review.", with: "For review.")
    }
}
