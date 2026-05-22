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
        primaryText = result.title
        secondaryLines = Self.secondaryLines(for: result)
        footerText = result.productContextText
        kindPillText = kindBadge.label
        kindPillTone = kindBadge.tone
        rulePillText = result.ruleBadge
        rulePillTone = ruleBadge?.tone
        badges = LedgerBadgePresentation.visibleBadges(from: [kindBadge, ruleBadge].compactMap(\.self), maxCount: 2)
        dateText = Self.dateText(for: result)
    }

    private static func secondaryLines(for result: LocalSearchResult) -> [LedgerRowLine] {
        let dateText = dateText(for: result)
        var lines = [LedgerRowLine(text: dateText, tone: .muted)]
        var shownText = [result.title, dateText]

        if let subtitle = result.subtitle,
           !subtitle.isEmpty,
           result.sourceKind != .timelineSlice,
           !isDuplicate(subtitle, ofAny: shownText) {
            lines.append(LedgerRowLine(text: subtitle))
            shownText.append(subtitle)
        }

        if let body = result.body,
           !body.isEmpty,
           !isDuplicate(body, ofAny: shownText),
           !bodyRepeatsTitle(body, title: result.title) {
            lines.append(LedgerRowLine(text: body, lineLimit: 2))
        }
        return lines
    }

    private static func isDuplicate(_ text: String, ofAny values: [String]) -> Bool {
        let normalizedText = normalizedForRowComparison(text)
        guard !normalizedText.isEmpty else { return true }
        return values.contains { normalizedForRowComparison($0) == normalizedText }
    }

    private static func bodyRepeatsTitle(_ body: String, title: String) -> Bool {
        let normalizedBody = normalizedForRowComparison(body)
        let normalizedTitle = normalizedForRowComparison(title)
        guard !normalizedBody.isEmpty, !normalizedTitle.isEmpty else { return true }
        return normalizedBody == normalizedTitle || normalizedBody.hasPrefix("\(normalizedTitle) ")
    }

    private static func normalizedForRowComparison(_ text: String) -> String {
        SearchService.normalizeForLocalSearch(text)
    }

    private static func dateText(for result: LocalSearchResult) -> String {
        guard let range = result.record.timelineDateRange else {
            return DateFormatting.shortDate.string(from: result.date)
        }
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.date(byAdding: .second, value: -1, to: range.endExclusive) ?? range.endExclusive
        let format = calendar.component(.year, from: range.start) == calendar.component(.year, from: end) ? "MMM d" : "MMM d, yyyy"
        let startText = DateFormatting.string(from: range.start, format: format, calendar: calendar, timeZone: calendar.timeZone)
        let endText = DateFormatting.string(from: end, format: format, calendar: calendar, timeZone: calendar.timeZone)
        return startText == endText ? startText : "\(startText)-\(endText)"
    }
}

struct LocalSearchResultRow: View {
    let result: LocalSearchResult

    private var presentation: LocalSearchResultRowPresentation {
        LocalSearchResultRowPresentation(result: result)
    }

    var body: some View {
        let presentation = presentation

        LedgerRow(
            primary: presentation.primaryText,
            secondary: presentation.secondaryLines,
            footer: presentation.footerText,
            density: LedgerSurfaceDensity.searchResultRow.rowDensity
        ) {
            ForEach(presentation.badges) { badge in
                LedgerBadgePill(badge: badge, size: .small)
            }
        }
    }
}
