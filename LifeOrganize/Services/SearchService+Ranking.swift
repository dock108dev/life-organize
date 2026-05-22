import Foundation

extension LocalSearchResult {
    var productContextText: String? {
        guard let linkedThingName, sourceKind != .thing else { return nil }
        switch sourceKind {
        case .rule:
            return "For \(linkedThingName)"
        case .event, .note:
            return "Related to \(linkedThingName)"
        case .timelineSlice:
            return "Timeline for \(linkedThingName)"
        case .thing, .chatMessage:
            return nil
        }
    }
}

extension SearchService {
    func result(for record: LocalSearchRecord, query: LocalSearchQuery) -> LocalSearchResult? {
        guard query.scopes.contains(record.kind) else { return nil }
        if query.includeInactiveRules == false, record.isActiveRule == false {
            return nil
        }
        if let linkedThingIdFilter = query.linkedThingIdFilter, record.linkedThingId != linkedThingIdFilter {
            return nil
        }
        if let dateRange = query.dateRange, !record.matches(dateRange) {
            return nil
        }

        let matchedFields = query.normalizedText.isEmpty
            ? []
            : record.searchableFields.filter { field in
                field.normalizedValue.contains(query.normalizedText)
            }
        guard !matchedFields.isEmpty || query.normalizedText.isEmpty else { return nil }

        let score = relevanceScore(for: record, matchedFields: matchedFields, query: query)
        return LocalSearchResult(
            record: record,
            matchedFields: Array(Set(matchedFields.map(\.key))).sorted { $0.rawValue < $1.rawValue },
            score: score
        )
    }

    private func relevanceScore(
        for record: LocalSearchRecord,
        matchedFields: [LocalSearchField],
        query: LocalSearchQuery
    ) -> Double {
        let exactBoost = matchedFields.contains { $0.normalizedValue == query.normalizedText } ? 25.0 : 0.0
        let shortQueryPenalty = query.normalizedText.count <= 2 ? 0.25 : 1.0
        let fieldScore = (matchedFields.map(\.weight).max() ?? 0) * shortQueryPenalty
        let matchBreadthBoost = min(max(Double(matchedFields.count - 1) * 2.0, 0), 8.0)

        return fieldScore
            + exactBoost
            + matchBreadthBoost
            + structuredRecordBoost(for: record)
            + dateRangeBoost(for: record, query: query)
            + linkedThingBoost(for: matchedFields)
            + temporalBoost(for: record, now: query.now)
    }

    private func structuredRecordBoost(for record: LocalSearchRecord) -> Double {
        switch record.kind {
        case .thing, .event, .rule, .note:
            12
        case .chatMessage:
            -10
        case .timelineSlice:
            35
        }
    }

    private func dateRangeBoost(for record: LocalSearchRecord, query: LocalSearchQuery) -> Double {
        guard query.dateRange != nil else { return 0 }
        switch record.kind {
        case .timelineSlice:
            return query.normalizedText.isEmpty ? 120 : 60
        case .event, .rule, .note, .chatMessage:
            return 18
        case .thing:
            return 6
        }
    }

    private func linkedThingBoost(for matchedFields: [LocalSearchField]) -> Double {
        matchedFields.contains { $0.key == .linkedThingName || $0.key == .alias } ? 14 : 0
    }

    private func temporalBoost(for record: LocalSearchRecord, now: Date) -> Double {
        let distance = abs(record.displayDate.timeIntervalSince(now))
        let dayDistance = distance / 86_400
        switch record.kind {
        case .event:
            return recentPastBoost(for: record.displayDate, now: now, dayDistance: dayDistance, maximum: 18)
        case .rule:
            if record.isActiveRule == true {
                return 22
            }
            return futureUsefulnessBoost(for: record.displayDate, now: now, dayDistance: dayDistance)
        case .note:
            return recentPastBoost(for: record.displayDate, now: now, dayDistance: dayDistance, maximum: 10)
        case .thing:
            return recentPastBoost(for: record.displayDate, now: now, dayDistance: dayDistance, maximum: 8)
        case .chatMessage:
            return recentPastBoost(for: record.displayDate, now: now, dayDistance: dayDistance, maximum: 4)
        case .timelineSlice:
            return recentPastBoost(for: record.displayDate, now: now, dayDistance: dayDistance, maximum: 12)
        }
    }

    private func recentPastBoost(for date: Date, now: Date, dayDistance: TimeInterval, maximum: Double) -> Double {
        guard date <= now else { return min(maximum, 3) }
        if dayDistance <= 30 { return maximum }
        if dayDistance <= 180 { return maximum * 0.6 }
        if dayDistance <= 365 { return maximum * 0.3 }
        return 0
    }

    private func futureUsefulnessBoost(for date: Date, now: Date, dayDistance: TimeInterval) -> Double {
        guard date >= now else { return 4 }
        if dayDistance <= 30 { return 20 }
        if dayDistance <= 180 { return 16 }
        if dayDistance <= 365 { return 10 }
        return 6
    }
}

private extension LocalSearchRecord {
    func matches(_ range: TimelineSliceDateRange) -> Bool {
        if let timelineDateRange {
            return timelineDateRange.start < range.endExclusive && timelineDateRange.endExclusive > range.start
        }
        return range.contains(displayDate)
    }
}
