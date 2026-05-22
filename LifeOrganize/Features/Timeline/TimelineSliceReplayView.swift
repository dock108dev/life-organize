import SwiftData
import SwiftUI

enum TimelineSliceReplayLayout {
    static let timestampWidth: CGFloat = 62
    static let markerSize: CGFloat = 6
    static let timestampTopPadding: CGFloat = 1
    static let markerTopPadding: CGFloat = 6
    static let rowChrome = LedgerTimelineRowChromeLayout(
        rowHorizontalPadding: LedgerVisualSystem.Padding.rowHorizontal,
        rowVerticalPadding: LedgerVisualSystem.Padding.rowCompactVertical,
        rowColumnSpacing: LedgerVisualSystem.Spacing.rowAccessoryGap,
        timestampWidth: timestampWidth,
        markerSize: markerSize,
        timestampTopPadding: timestampTopPadding,
        markerTopPadding: markerTopPadding
    )
    static let dividerLeadingPadding = rowChrome.dividerLeadingPadding
}

struct TimelineSliceReplayModel {
    let title: String
    let context: TimelineSliceReplayContext
    let sections: [TimelineSliceReplaySection]

    init(title: String, query: TimelineSliceQuery, rows: [TimelineSliceRow], calendar: Calendar, now: Date) {
        self.title = title
        context = TimelineSliceReplayContext(query: query, rows: rows, calendar: calendar)

        let grouped = Dictionary(grouping: rows) { row in
            calendar.startOfDay(for: row.timelineDate)
        }
        sections = grouped.keys.sorted(by: >).map { day in
            let rows = grouped[day, default: []]
            return TimelineSliceReplaySection(day: day, rows: rows, calendar: calendar, now: now)
        }
    }

    var isEmpty: Bool {
        sections.allSatisfy(\.rows.isEmpty)
    }
}

struct TimelineSliceReplayContext: Equatable {
    let dateRangeText: String?
    let itemCountText: String
    let typeMixText: String

    var text: String {
        [dateRangeText, itemCountText, typeMixText]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " · ")
    }

    init(query: TimelineSliceQuery, rows: [TimelineSliceRow], calendar: Calendar) {
        dateRangeText = query.dateRange.map { Self.dateRangeText(for: $0, calendar: calendar) }
        itemCountText = LedgerDisplayFormatting.count(rows.count, singular: "item", plural: "items")
        typeMixText = Self.typeMixText(for: rows)
    }

    private static func dateRangeText(for range: TimelineSliceDateRange, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .second, value: -1, to: range.endExclusive) ?? range.endExclusive
        let format = calendar.component(.year, from: range.start) == calendar.component(.year, from: end) ? "MMM d" : "MMM d, yyyy"
        let startText = DateFormatting.string(from: range.start, format: format, calendar: calendar, timeZone: calendar.timeZone)
        let endText = DateFormatting.string(from: end, format: format, calendar: calendar, timeZone: calendar.timeZone)
        return startText == endText ? startText : "\(startText)-\(endText)"
    }

    fileprivate static func typeMixText(for rows: [TimelineSliceRow]) -> String {
        let counts = Dictionary(grouping: rows, by: \.sourceKind).mapValues(\.count)
        return TimelineSliceRecordKind.replaySummaryOrder.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return "\(count) \(kind.replaySummaryLabel(count: count))"
        }
        .joined(separator: ", ")
    }
}

struct TimelineSliceReplaySection: Identifiable {
    let day: Date
    let title: String
    let subtitle: String?
    let summary: TimelineSliceReplaySectionSummary
    let rows: [TimelineSliceRow]

    var id: String {
        DateFormatting.dateOnlyString(day)
    }

    init(day: Date, rows: [TimelineSliceRow], calendar: Calendar, now: Date) {
        self.day = calendar.startOfDay(for: day)
        let title = LedgerTimelineSectionTitle(day: day, calendar: calendar, now: now)
        self.title = title.primary
        subtitle = title.secondary
        summary = TimelineSliceReplaySectionSummary(rows: rows, calendar: calendar)
        self.rows = rows
    }
}

struct TimelineSliceReplaySectionSummary: Equatable {
    let itemCountText: String
    let timeRangeText: String
    let typeMixText: String

    var text: String {
        summaryText.text
    }

    func displayText(mode: TimelineSectionSummaryDisplayMode) -> String {
        summaryText.displayText(mode: mode)
    }

    init(rows: [TimelineSliceRow], calendar: Calendar) {
        itemCountText = LedgerDisplayFormatting.count(rows.count, singular: "item", plural: "items")
        timeRangeText = TimelineSectionSummaryFormatting.timeRangeText(for: rows.map(\.timelineDate), calendar: calendar)
        typeMixText = TimelineSliceReplayContext.typeMixText(for: rows)
    }

    private var summaryText: TimelineSectionSummaryText {
        TimelineSectionSummaryText(
            itemCountText: itemCountText,
            timeRangeText: timeRangeText,
            typeMixText: typeMixText
        )
    }

}

struct TimelineSliceReplayRowContent: Equatable {
    let timestampText: String
    let sourceLabel: String
    let sourceBadge: LedgerBadgePresentation
    let sourceTone: LedgerTone
    let dateKindLabel: String
    let primaryText: String
    let detailText: String?
    let linkedThingText: String?
    let relationshipText: String?
    let navigationTarget: LocalSearchNavigationTarget

    init(row: TimelineSliceRow, timeFormatter: DateFormatter = DateFormatting.ledgerTime) {
        timestampText = timeFormatter.string(from: row.timelineDate)
        sourceBadge = LedgerBadgePresentation.timelineCategory(for: row.sourceKind)
        sourceLabel = sourceBadge.label
        sourceTone = sourceBadge.tone
        dateKindLabel = row.dateKind.displayName
        primaryText = row.displayLabel
        detailText = row.summaryText.nilIfEmpty
        let linkedNames = row.linkedThings.map(\.name).filter { !$0.isEmpty }
        linkedThingText = linkedNames.isEmpty ? nil : linkedNames.joined(separator: ", ")
        relationshipText = row.relationshipContext?.sourceLabel.nilIfEmpty
        navigationTarget = row.navigationTarget
    }
}

struct TimelineSliceReplayView: View {
    @Query(sort: \Thing.updatedAt, order: .reverse) private var things: [Thing]
    @Query(sort: \LedgerEvent.occurredAt, order: .reverse) private var events: [LedgerEvent]
    @Query(sort: \LedgerRule.createdAt, order: .reverse) private var rules: [LedgerRule]
    @Query(sort: \LedgerNote.createdAt, order: .reverse) private var notes: [LedgerNote]
    @Query(sort: \ChatMessage.createdAt, order: .reverse) private var messages: [ChatMessage]
    @Query(sort: \EntityLink.createdAt, order: .reverse) private var entityLinks: [EntityLink]

    let descriptor: TimelineSliceReplayDescriptor
    let calendar: Calendar
    let now: Date

    init(descriptor: TimelineSliceReplayDescriptor, calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) {
        self.descriptor = descriptor
        self.calendar = calendar
        self.now = now
    }

    private var model: TimelineSliceReplayModel {
        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            query: descriptor.query,
            messages: messages,
            things: things,
            events: events,
            reminders: rules,
            notes: notes,
            entityLinks: entityLinks
        )
        return TimelineSliceReplayModel(title: descriptor.title, query: descriptor.query, rows: rows, calendar: calendar, now: now)
    }

    var body: some View {
        let model = model

        ScrollView {
            LazyVStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.section) {
                replayHeader(model)

                if model.isEmpty {
                    LedgerEmptyStateView(content: .timelineSliceReplay)
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(model.sections) { section in
                        TimelineSliceReplaySectionView(
                            section: section,
                            things: things,
                            events: events,
                            rules: rules,
                            notes: notes,
                            messages: messages
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func replayHeader(_ model: TimelineSliceReplayModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(model.context.text)
                .font(LedgerVisualSystem.Typography.rowSecondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}

private struct TimelineSliceReplaySectionView: View {
    let section: TimelineSliceReplaySection
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let messages: [ChatMessage]

    var body: some View {
        LedgerTimelineSectionChrome(
            title: section.title,
            subtitle: section.subtitle,
            summaryText: section.summary.displayText(mode: .compact),
            spacing: 6
        ) {
            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    NavigationLink {
                        LocalSearchDestinationView(
                            target: row.navigationTarget,
                            things: things,
                            events: events,
                            rules: rules,
                            notes: notes,
                            messages: messages
                        )
                    } label: {
                        TimelineSliceReplayRow(row: row)
                    }
                    .buttonStyle(.plain)

                    if row.id != section.rows.last?.id {
                        TimelineSectionRowDivider(leadingPadding: TimelineSliceReplayLayout.dividerLeadingPadding)
                    }
                }
            }
        }
    }
}

private struct TimelineSliceReplayRow: View {
    let row: TimelineSliceRow
    @ScaledMetric(relativeTo: .caption2) private var timestampWidth = TimelineSliceReplayLayout.timestampWidth
    @ScaledMetric(relativeTo: .caption2) private var markerSize = TimelineSliceReplayLayout.markerSize

    private var content: TimelineSliceReplayRowContent {
        TimelineSliceReplayRowContent(row: row)
    }

    private var rowLayout: LedgerTimelineRowChromeLayout {
        LedgerTimelineRowChromeLayout(
            rowHorizontalPadding: LedgerVisualSystem.Padding.rowHorizontal,
            rowVerticalPadding: LedgerVisualSystem.Padding.rowCompactVertical,
            rowColumnSpacing: LedgerVisualSystem.Spacing.rowAccessoryGap,
            timestampWidth: timestampWidth,
            markerSize: markerSize,
            timestampTopPadding: TimelineSliceReplayLayout.timestampTopPadding,
            markerTopPadding: TimelineSliceReplayLayout.markerTopPadding
        )
    }

    var body: some View {
        LedgerTimelineRowContainer(layout: rowLayout) {
            LedgerTimelineRowShell(
                timestampText: content.timestampText,
                tone: content.sourceTone,
                layout: rowLayout,
                timestampWeight: .semibold
            ) {
                VStack(alignment: .leading, spacing: LedgerVisualSystem.Spacing.rowCompact) {
                    HStack(alignment: .firstTextBaseline, spacing: LedgerVisualSystem.Spacing.rowBadgeGap) {
                        LedgerBadgePill(badge: content.sourceBadge, size: .small)
                        LedgerPill(text: content.dateKindLabel, tone: .neutral, size: .small)
                    }

                    LedgerTimelinePrimaryText(text: content.primaryText, weight: .medium)

                    if let detailText = content.detailText, detailText != content.primaryText {
                        LedgerTimelineDetailText(text: detailText)
                    }

                    if let linkedThingText = content.linkedThingText {
                        LedgerTimelineLinkedThingPill(text: linkedThingText)
                    }

                    if let relationshipText = content.relationshipText {
                        Text(relationshipText)
                            .font(LedgerVisualSystem.Typography.rowFooter)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private extension LedgerEmptyStateContent {
    static let timelineSliceReplay = LedgerEmptyStateContent(
        symbolName: "clock.arrow.circlepath",
        title: "No history in this slice",
        body: "Records will appear here when the selected dates or linked thing have matching timeline activity."
    )
}

extension LedgerTone {
    init(timelineRecordKind: TimelineSliceRecordKind) {
        self = LedgerBadgePresentation.timelineCategory(for: timelineRecordKind).tone
    }
}

private extension TimelineSliceRecordKind {
    static let replaySummaryOrder: [TimelineSliceRecordKind] = [.event, .reminder, .note, .message, .thing]

    func replaySummaryLabel(count: Int) -> String {
        switch self {
        case .message:
            count == 1 ? "message" : "messages"
        case .event:
            count == 1 ? "event" : "events"
        case .reminder:
            count == 1 ? "reminder" : "reminders"
        case .note:
            count == 1 ? "note" : "notes"
        case .thing:
            count == 1 ? "thing" : "things"
        }
    }
}
