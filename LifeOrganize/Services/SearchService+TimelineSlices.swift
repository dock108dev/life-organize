import Foundation

extension SearchService {
    func timelineSliceResults(for query: LocalSearchQuery, records: [LocalSearchRecord]) -> [LocalSearchResult] {
        guard query.scopes.contains(.timelineSlice) else { return [] }

        var results: [LocalSearchResult] = []
        if let global = globalTimelineSliceResult(for: query, records: records) {
            results.append(global)
        }
        results.append(contentsOf: linkedThingTimelineSliceResults(for: query, records: records))
        return results
    }

    private func globalTimelineSliceResult(for query: LocalSearchQuery, records: [LocalSearchRecord]) -> LocalSearchResult? {
        guard let dateRange = query.dateRange else { return nil }
        let matches = records.filter { record in
            record.kind != .timelineSlice
                && record.isIncludedBySearchFilters(query)
                && record.matchesSearchText(query.normalizedText)
        }
        guard !matches.isEmpty else { return nil }

        let title = query.rangeTitle ?? Self.dateRangeTitle(dateRange)
        let descriptor = TimelineSliceReplayDescriptor(
            title: query.normalizedText.isEmpty ? title : "\(title) results",
            query: TimelineSliceQuery(dateRange: dateRange, textFilter: query.textFilter)
        )
        return result(
            descriptor: descriptor,
            title: descriptor.title,
            subtitle: "Timeline slice",
            body: Self.typeMixText(for: matches),
            linkedThingId: nil,
            linkedThingName: nil,
            dateRange: dateRange,
            score: query.normalizedText.isEmpty ? 240 : 190
        )
    }

    private func linkedThingTimelineSliceResults(for query: LocalSearchQuery, records: [LocalSearchRecord]) -> [LocalSearchResult] {
        guard query.dateRange != nil || query.linkedThingIdFilter != nil else { return [] }

        let thingRecords = records
            .filter { $0.kind == .thing }
            .filter { record in
                if let linkedThingIdFilter = query.linkedThingIdFilter {
                    return record.id == linkedThingIdFilter
                }
                return record.matchesSearchText(query.normalizedText)
            }

        guard !thingRecords.isEmpty else { return [] }

        return thingRecords.compactMap { thingRecord in
            let matches = records.filter { record in
                record.kind != .timelineSlice
                    && record.linkedThingId == thingRecord.id
                    && record.isIncludedBySearchFilters(query)
                    && record.matchesSearchText(query.normalizedText, allowingThingMatch: thingRecord)
            }
            guard !matches.isEmpty else { return nil }

            let descriptorQuery = TimelineSliceQuery(
                dateRange: query.dateRange,
                linkedThingFilter: .id(thingRecord.id),
                textFilter: query.normalizedText == SearchService.normalizeForLocalSearch(thingRecord.title) ? nil : query.textFilter
            )
            let title = linkedThingTimelineTitle(thingName: thingRecord.title, query: query)
            let descriptor = TimelineSliceReplayDescriptor(title: title, query: descriptorQuery)
            return result(
                descriptor: descriptor,
                title: title,
                subtitle: "Timeline slice",
                body: Self.typeMixText(for: matches),
                linkedThingId: thingRecord.id,
                linkedThingName: thingRecord.title,
                dateRange: query.dateRange,
                score: query.dateRange == nil ? 170 : 220
            )
        }
    }

    private func result(
        descriptor: TimelineSliceReplayDescriptor,
        title: String,
        subtitle: String,
        body: String?,
        linkedThingId: UUID?,
        linkedThingName: String?,
        dateRange: TimelineSliceDateRange?,
        score: Double
    ) -> LocalSearchResult {
        let fields = [
            LocalSearchField(key: .timeline, rawValue: title, weight: 105),
            LocalSearchField(key: .body, rawValue: body, weight: 45),
            LocalSearchField(key: .linkedThingName, rawValue: linkedThingName, weight: 80)
        ].filter { !$0.normalizedValue.isEmpty }
        let record = LocalSearchRecord(
            id: Self.deterministicUUID("timeline|\(title)|\(Self.queryKey(descriptor.query))"),
            kind: .timelineSlice,
            title: title,
            subtitle: subtitle,
            body: body,
            searchableFields: fields,
            createdAt: dateRange?.start ?? .distantPast,
            occurredAt: dateRange?.start,
            updatedAt: nil,
            linkedThingId: linkedThingId,
            linkedThingName: linkedThingName,
            isActiveRule: nil,
            ruleBadge: nil,
            ruleLane: nil,
            timelineDateRange: dateRange,
            navigationTarget: .timelineSlice(descriptor)
        )
        return LocalSearchResult(record: record, matchedFields: [.timeline], score: score)
    }

    private func linkedThingTimelineTitle(thingName: String, query: LocalSearchQuery) -> String {
        if let rangeTitle = query.rangeTitle {
            return "\(thingName) \(rangeTitle.lowercased())"
        }
        if let dateRange = query.dateRange {
            return "\(thingName) \(Self.dateRangeTitle(dateRange).lowercased())"
        }
        return "\(thingName) timeline"
    }

    private static func typeMixText(for records: [LocalSearchRecord]) -> String? {
        let counts = Dictionary(grouping: records, by: \.kind).mapValues(\.count)
        return [
            typeMixPart(kind: .thing, count: counts[.thing]),
            typeMixPart(kind: .event, count: counts[.event]),
            typeMixPart(kind: .rule, count: counts[.rule]),
            typeMixPart(kind: .note, count: counts[.note]),
            typeMixPart(kind: .chatMessage, count: counts[.chatMessage])
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        .nilIfEmpty
    }

    private static func typeMixPart(kind: LocalSearchEntityKind, count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        let singular: String
        let plural: String
        switch kind {
        case .thing:
            singular = "thing"
            plural = "things"
        case .event:
            singular = "event"
            plural = "events"
        case .rule:
            singular = "reminder"
            plural = "reminders"
        case .note:
            singular = "note"
            plural = "notes"
        case .chatMessage:
            singular = "message"
            plural = "messages"
        case .timelineSlice:
            return nil
        }
        return LedgerDisplayFormatting.count(count, singular: singular, plural: plural)
    }

    private static func dateRangeTitle(_ range: TimelineSliceDateRange) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.date(byAdding: .second, value: -1, to: range.endExclusive) ?? range.endExclusive
        if calendar.component(.month, from: range.start) == calendar.component(.month, from: end),
           calendar.component(.year, from: range.start) == calendar.component(.year, from: end),
           calendar.component(.day, from: range.start) == 1,
           calendar.component(.day, from: end) >= 28 {
            return DateFormatting.string(from: range.start, format: "MMMM yyyy", calendar: calendar, timeZone: calendar.timeZone)
        }
        if calendar.component(.year, from: range.start) == calendar.component(.year, from: end),
           calendar.component(.month, from: range.start) == 1,
           calendar.component(.month, from: end) == 12 {
            return DateFormatting.string(from: range.start, format: "yyyy", calendar: calendar, timeZone: calendar.timeZone)
        }
        let startText = DateFormatting.string(from: range.start, format: "MMM d, yyyy", calendar: calendar, timeZone: calendar.timeZone)
        let endText = DateFormatting.string(from: end, format: "MMM d, yyyy", calendar: calendar, timeZone: calendar.timeZone)
        return "\(startText)-\(endText)"
    }

    private static func deterministicUUID(_ value: String) -> UUID {
        let high = fnv1a64(value, seed: 0xcbf2_9ce4_8422_2325)
        let low = fnv1a64(value, seed: 0x8422_2325_cbf2_9ce4)
        let uuidString = String(
            format: "%08llx-%04llx-%04llx-%04llx-%012llx",
            high >> 32,
            (high >> 16) & 0xffff,
            high & 0xffff,
            low >> 48,
            low & 0xffff_ffff_ffff
        )
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private static func queryKey(_ query: TimelineSliceQuery) -> String {
        let start = query.dateRange?.start.timeIntervalSince1970.description ?? "none"
        let end = query.dateRange?.endExclusive.timeIntervalSince1970.description ?? "none"
        let thing: String
        switch query.linkedThingFilter {
        case .id(let id):
            thing = id.uuidString
        case .text(let text):
            thing = text
        case nil:
            thing = "none"
        }
        return [start, end, thing, query.textFilter ?? ""].joined(separator: "|")
    }

    private static func fnv1a64(_ value: String, seed: UInt64) -> UInt64 {
        value.utf8.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
    }
}

private extension LocalSearchRecord {
    func isIncludedBySearchFilters(_ query: LocalSearchQuery) -> Bool {
        guard query.scopes == [.timelineSlice] || query.scopes.contains(kind) else { return false }
        if query.includeInactiveRules == false, isActiveRule == false {
            return false
        }
        if let linkedThingIdFilter = query.linkedThingIdFilter, linkedThingId != linkedThingIdFilter {
            return false
        }
        if let dateRange = query.dateRange, !matches(dateRange) {
            return false
        }
        return true
    }

    func matchesSearchText(_ normalizedText: String, allowingThingMatch thingRecord: LocalSearchRecord? = nil) -> Bool {
        guard !normalizedText.isEmpty else { return true }
        if searchableFields.contains(where: { $0.normalizedValue.contains(normalizedText) }) {
            return true
        }
        guard let thingRecord, linkedThingId == thingRecord.id else { return false }
        return thingRecord.matchesSearchText(normalizedText)
    }

    func matches(_ range: TimelineSliceDateRange) -> Bool {
        if let timelineDateRange {
            return timelineDateRange.start < range.endExclusive && timelineDateRange.endExclusive > range.start
        }
        return range.contains(displayDate)
    }
}

extension Array where Element == LocalSearchResult {
    func uniquedByID() -> [LocalSearchResult] {
        var seen = Set<String>()
        return filter { result in
            seen.insert(result.id).inserted
        }
    }
}
