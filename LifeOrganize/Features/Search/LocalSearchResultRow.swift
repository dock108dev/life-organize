import SwiftUI

struct LocalSearchResultRowPresentation: Equatable {
    let primaryText: String
    let secondaryLines: [LedgerRowLine]
    let footerText: String?
    let kindPillText: String
    let kindPillTone: LedgerTone
    let rulePillText: String?
    let rulePillTone: LedgerTone?
    let badges: [LedgerBadgePresentation]
    let accessibilityLabel: String
    let dateText: String

    init(result: LocalSearchResult) {
        let kindBadge = LedgerBadgePresentation.searchCategory(for: result.sourceKind)
        let ruleBadge = result.ruleLane.map { lane in
            let badge = LedgerBadgePresentation.reminderStatus(for: lane)
            return LedgerBadgePresentation(
                semantic: badge.semantic,
                label: result.ruleBadge,
                tone: badge.tone,
                priority: badge.priority
            )
        }
        let rowSecondaryLines = Self.secondaryLines(for: result)
        let candidateBadges = [kindBadge, ruleBadge].compactMap(\.self)
        let visibleBadges = LedgerBadgePresentation.primaryBadges(from: candidateBadges)
        let hiddenBadges = LedgerBadgePresentation.hiddenBadges(from: candidateBadges, visibleBadges: visibleBadges)
        let rowDateText = Self.dateText(for: result)

        primaryText = result.title
        secondaryLines = rowSecondaryLines
        footerText = result.productContextText
        kindPillText = kindBadge.label
        kindPillTone = kindBadge.tone
        rulePillText = result.ruleBadge
        rulePillTone = ruleBadge?.tone
        badges = visibleBadges
        accessibilityLabel = (
            [result.title]
                + visibleBadges.map(\.label)
                + hiddenBadges.map(\.label)
                + rowSecondaryLines.map(\.text)
                + [result.productContextText].compactMap(\.self)
        )
            .compactMap(\.nilIfEmpty)
            .joined(separator: ". ")
        dateText = rowDateText
    }

    private static func secondaryLines(for result: LocalSearchResult) -> [LedgerRowLine] {
        let dateText = dateText(for: result)
        var lines = [LedgerRowLine(text: dateText, tone: .muted, role: .metadata)]
        var shownText = [result.title, dateText]

        if let subtitle = result.subtitle,
           !subtitle.isEmpty,
           result.sourceKind != .timelineSlice,
           !isDuplicate(subtitle, ofAny: shownText) {
            lines.append(LedgerRowLine(text: subtitle, role: .contentPreview))
            shownText.append(subtitle)
        }

        if let body = result.body,
           !body.isEmpty,
           !isDuplicate(body, ofAny: shownText),
           !bodyRepeatsTitle(body, title: result.title) {
            lines.append(LedgerRowLine(text: body, role: .contentPreview, lineLimit: 2))
        }
        return lines
    }

    private static func isDuplicate(_ text: String, ofAny values: [String]) -> Bool {
        let normalizedText = SearchService.normalizeForLocalSearch(text)
        guard !normalizedText.isEmpty else { return true }
        return values.contains { SearchService.normalizeForLocalSearch($0) == normalizedText }
    }

    private static func bodyRepeatsTitle(_ body: String, title: String) -> Bool {
        let normalizedBody = SearchService.normalizeForLocalSearch(body)
        let normalizedTitle = SearchService.normalizeForLocalSearch(title)
        guard !normalizedBody.isEmpty, !normalizedTitle.isEmpty else { return true }
        return normalizedBody == normalizedTitle || normalizedBody.hasPrefix("\(normalizedTitle) ")
    }

    private static func dateText(for result: LocalSearchResult) -> String {
        guard let range = result.record.timelineDateRange else {
            return DateFormatting.shortDate.string(from: result.date)
        }
        let calendar = Calendar.autoupdatingCurrent
        return DateFormatting.inclusiveDateRangeSummary(
            start: range.start,
            endExclusive: range.endExclusive,
            calendar: calendar
        )
    }
}

struct LocalSearchResultRow: View {
    let result: LocalSearchResult
    var isSelected = false

    private var presentation: LocalSearchResultRowPresentation {
        LocalSearchResultRowPresentation(result: result)
    }

    var body: some View {
        let presentation = presentation

        LedgerRow(
            primary: presentation.primaryText,
            secondary: presentation.secondaryLines,
            footer: presentation.footerText,
            density: LedgerSurfaceDensity.searchResultRow.rowDensity,
            emphasis: isSelected ? .active : .normal
        ) {
            ForEach(presentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
