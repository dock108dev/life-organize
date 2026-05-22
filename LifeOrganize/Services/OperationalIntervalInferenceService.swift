import Foundation

struct OperationalIntervalInferenceService {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    var ruleStatus: RuleStatusService = RuleStatusService()

    func inferences(
        for thing: Thing,
        now: Date = Date(),
        includeSuppressed: Bool = false
    ) -> [OperationalIntervalInference] {
        let eventGroups = Dictionary(grouping: comparableEvents(for: thing), by: \.track)
        let candidates = eventGroups.compactMap { track, events in
            inference(for: track, events: events, thing: thing, now: now)
        }

        return candidates.compactMap { candidate in
            let suppression = suppressionReason(for: candidate, rules: thing.rules, now: now)
            if let suppression {
                return includeSuppressed ? candidate.suppressed(reason: suppression) : nil
            }
            return candidate
        }
        .sorted { lhs, rhs in
            if lhs.confidence.score != rhs.confidence.score {
                return lhs.confidence.score > rhs.confidence.score
            }
            return lhs.title < rhs.title
        }
    }

    private func comparableEvents(for thing: Thing) -> [TrackedEvent] {
        thing.events.compactMap { event in
            guard let track = OperationalIntervalTrack(event: event, thing: thing) else {
                return nil
            }
            return TrackedEvent(event: event, track: track)
        }
    }

    private func inference(
        for track: OperationalIntervalTrack,
        events trackedEvents: [TrackedEvent],
        thing: Thing,
        now: Date
    ) -> OperationalIntervalInference? {
        let events = trackedEvents.map(\.event).sorted { $0.occurredAt < $1.occurredAt }
        guard let latest = events.last else { return nil }

        let calendarEstimate = calendarEstimate(for: events)
        let mileageEstimate = mileageEstimate(for: events, track: track)
        guard calendarEstimate != nil || mileageEstimate != nil else {
            return nil
        }

        let confidence = confidenceLevel(
            calendarEstimate: calendarEstimate,
            mileageEstimate: mileageEstimate,
            eventCount: events.count
        )
        let adjustedCalendarEstimate = calendarEstimate.map {
            CalendarEstimate(
                intervalDays: $0.intervalDays,
                nextRange: range(
                    around: date(byAddingDays: $0.intervalDays, to: latest.occurredAt),
                    intervalDays: $0.intervalDays,
                    confidence: confidence
                ),
                sourceEventID: $0.sourceEventID,
                sourceText: $0.sourceText,
                isExplicit: $0.isExplicit
            )
        }
        let title = "\(track.displayName) pattern"
        return OperationalIntervalInference(
            thingID: thing.id,
            thingName: thing.name,
            track: track,
            title: title,
            calendarIntervalDays: adjustedCalendarEstimate?.intervalDays,
            nextExpectedDateRange: adjustedCalendarEstimate?.nextRange,
            mileageInterval: mileageEstimate?.intervalMiles,
            nextExpectedMileage: mileageEstimate?.nextMileage,
            confidence: confidence,
            evidence: evidenceRecords(
                events: events,
                calendarEstimate: adjustedCalendarEstimate,
                mileageEstimate: mileageEstimate
            ),
            operationalReason: track.operationalReason,
            latestEventID: latest.id,
            suppressionReason: nil
        )
    }

    private func calendarEstimate(for events: [LedgerEvent]) -> CalendarEstimate? {
        if let explicit = latestExplicitCalendarInterval(from: events),
           let latest = events.last {
            let intervalDays = max(1, Int(explicit.value.rounded()))
            let next = date(byAddingDays: intervalDays, to: latest.occurredAt)
            return CalendarEstimate(
                intervalDays: intervalDays,
                nextRange: range(around: next, intervalDays: intervalDays, confidence: .strong),
                sourceEventID: explicit.event.id,
                sourceText: explicit.sourceText,
                isExplicit: true
            )
        }

        let gaps = dayGaps(for: events).filter { $0 >= 3 && $0 <= 730 }
        guard !gaps.isEmpty, events.count >= 2, let latest = events.last else {
            return nil
        }
        let intervalDays = max(1, Int(Self.median(gaps.map(Double.init)).rounded()))
        let confidence = gaps.count == 1 ? OperationalIntervalConfidence.weak : .medium
        let next = date(byAddingDays: intervalDays, to: latest.occurredAt)
        return CalendarEstimate(
            intervalDays: intervalDays,
            nextRange: range(around: next, intervalDays: intervalDays, confidence: confidence),
            sourceEventID: latest.id,
            sourceText: nil,
            isExplicit: false
        )
    }

    private func mileageEstimate(for events: [LedgerEvent], track: OperationalIntervalTrack) -> MileageEstimate? {
        guard track.supportsMileage else { return nil }
        if let explicit = latestExplicitMileageInterval(from: events),
           let anchorMileage = mileageValue(for: explicit.event) {
            let intervalMiles = max(1, Int(explicit.value.rounded()))
            return MileageEstimate(
                intervalMiles: intervalMiles,
                nextMileage: Int((anchorMileage + Double(intervalMiles)).rounded()),
                sourceEventID: explicit.event.id,
                sourceText: explicit.sourceText,
                isExplicit: true
            )
        }

        let mileageEvents = events.compactMap { event -> (LedgerEvent, Double)? in
            guard let mileage = mileageValue(for: event) else { return nil }
            return (event, mileage)
        }
        guard mileageEvents.count >= 2 else { return nil }

        let gaps = zip(mileageEvents, mileageEvents.dropFirst()).compactMap { previous, current -> Double? in
            let gap = current.1 - previous.1
            return gap > 0 ? gap : nil
        }
        guard !gaps.isEmpty, let latest = mileageEvents.last else { return nil }
        let intervalMiles = max(1, Int(Self.median(gaps).rounded()))
        return MileageEstimate(
            intervalMiles: intervalMiles,
            nextMileage: Int((latest.1 + Double(intervalMiles)).rounded()),
            sourceEventID: latest.0.id,
            sourceText: nil,
            isExplicit: false
        )
    }

    private func evidenceRecords(
        events: [LedgerEvent],
        calendarEstimate: CalendarEstimate?,
        mileageEstimate: MileageEstimate?
    ) -> [OperationalIntervalEvidenceRecord] {
        var records = events.map { event in
            OperationalIntervalEvidenceRecord(
                source: .event,
                sourceID: event.id,
                occurredAt: event.occurredAt,
                summary: event.title,
                detail: EventMetadataDisplayFormatter.summary(for: event.metadataEntries, eventType: event.eventType, limit: 3)
                    ?? event.rawText.nilIfEmpty
            )
        }

        if let calendarEstimate {
            records.append(
                OperationalIntervalEvidenceRecord(
                    source: .derivedCalendarInterval,
                    sourceID: calendarEstimate.sourceEventID,
                    occurredAt: nil,
                    summary: "\(calendarEstimate.intervalDays)-day interval",
                    detail: calendarEstimate.sourceText ?? "Derived from comparable event dates"
                )
            )
        }

        if let mileageEstimate {
            records.append(
                OperationalIntervalEvidenceRecord(
                    source: .derivedMileageInterval,
                    sourceID: mileageEstimate.sourceEventID,
                    occurredAt: nil,
                    summary: "\(mileageEstimate.intervalMiles)-mile interval",
                    detail: mileageEstimate.sourceText ?? "Derived from comparable mileage records"
                )
            )
        }

        return records
    }

    private func suppressionReason(
        for inference: OperationalIntervalInference,
        rules: [LedgerRule],
        now: Date
    ) -> String? {
        rules.first { rule in
            guard rule.ruleType.isReminderLike else { return false }
            switch ruleStatus.status(for: rule, at: now) {
            case .active, .scheduled:
                return inference.track.matches(rule: rule)
            case .expired, .inactive:
                return false
            }
        }.map { rule in
            "Existing \(ruleStatus.status(for: rule, at: now).rawValue) reminder covers this operational cadence: \(rule.title)"
        }
    }

    private func dayGaps(for events: [LedgerEvent]) -> [Int] {
        zip(events, events.dropFirst()).compactMap { previous, current in
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: previous.occurredAt),
                to: calendar.startOfDay(for: current.occurredAt)
            ).day
        }
    }

    private func date(byAddingDays days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }

    private func range(
        around expectedDate: Date,
        intervalDays: Int,
        confidence: OperationalIntervalConfidence
    ) -> DateInterval {
        let tolerance: Int
        switch confidence.level {
        case .strong:
            tolerance = max(1, Int((Double(intervalDays) * 0.05).rounded()))
        case .medium:
            tolerance = max(2, Int((Double(intervalDays) * 0.10).rounded()))
        case .weak:
            tolerance = max(3, Int((Double(intervalDays) * 0.20).rounded()))
        }
        let start = date(byAddingDays: -tolerance, to: expectedDate)
        let end = date(byAddingDays: tolerance, to: expectedDate)
        return DateInterval(start: start, end: end)
    }

    private func confidenceLevel(
        calendarEstimate: CalendarEstimate?,
        mileageEstimate: MileageEstimate?,
        eventCount: Int
    ) -> OperationalIntervalConfidence {
        if calendarEstimate?.isExplicit == true || mileageEstimate?.isExplicit == true {
            return .strong
        }
        if eventCount >= 4 || (calendarEstimate != nil && mileageEstimate != nil && eventCount >= 3) {
            return .strong
        }
        if eventCount >= 3 {
            return .medium
        }
        return .weak
    }

    private func latestExplicitCalendarInterval(from events: [LedgerEvent]) -> ExplicitInterval? {
        latestExplicitInterval(from: events, key: .calendarInterval)
            ?? latestTextInterval(from: events, unitKind: .calendar)
    }

    private func latestExplicitMileageInterval(from events: [LedgerEvent]) -> ExplicitInterval? {
        latestExplicitInterval(from: events, key: .mileageInterval)
            ?? latestTextInterval(from: events, unitKind: .mileage)
    }

    private func latestExplicitInterval(from events: [LedgerEvent], key: LedgerEventMetadataKey) -> ExplicitInterval? {
        events.reversed().compactMap { event in
            event.metadataEntries.first { $0.key == key && $0.numberValue != nil }.flatMap { entry in
                entry.numberValue.map {
                    ExplicitInterval(event: event, value: normalizedIntervalValue($0, unit: entry.unit, key: key), sourceText: entry.sourceText)
                }
            }
        }.first
    }

    private func latestTextInterval(from events: [LedgerEvent], unitKind: ExplicitIntervalUnitKind) -> ExplicitInterval? {
        events.reversed().compactMap { event in
            Self.explicitInterval(in: [event.title, event.rawText, event.note].compactMap { $0 }.joined(separator: " "), unitKind: unitKind)
                .map { ExplicitInterval(event: event, value: $0.value, sourceText: $0.sourceText) }
        }.first
    }

    private func normalizedIntervalValue(_ value: Double, unit: String?, key: LedgerEventMetadataKey) -> Double {
        guard key == .calendarInterval else { return value }
        switch unit?.lowercased() {
        case "week", "weeks", "wk", "wks":
            return value * 7
        case "month", "months", "mo", "mos":
            return value * 30
        case "year", "years", "yr", "yrs":
            return value * 365
        default:
            return value
        }
    }

    private func mileageValue(for event: LedgerEvent) -> Double? {
        event.metadataEntries.first { $0.key == .mileage }?.numberValue
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func explicitInterval(in text: String, unitKind: ExplicitIntervalUnitKind) -> (value: Double, sourceText: String)? {
        let pattern: String
        switch unitKind {
        case .calendar:
            pattern = #"(?i)\bevery\s+([0-9]+(?:\.[0-9]+)?)\s*(day|days|week|weeks|month|months|year|years)\b"#
        case .mileage:
            pattern = #"(?i)\bevery\s+([0-9][0-9,]*(?:\.[0-9]+)?)\s*(mile|miles|mi)\b"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let fullRange = Range(match.range(at: 0), in: text)
        else { return nil }

        let rawNumber = String(text[numberRange]).replacingOccurrences(of: ",", with: "")
        guard var value = Double(rawNumber) else { return nil }
        if unitKind == .calendar {
            switch String(text[unitRange]).lowercased() {
            case "week", "weeks":
                value *= 7
            case "month", "months":
                value *= 30
            case "year", "years":
                value *= 365
            default:
                break
            }
        }
        return (value, String(text[fullRange]))
    }
}

private struct TrackedEvent {
    let event: LedgerEvent
    let track: OperationalIntervalTrack
}

private struct CalendarEstimate {
    let intervalDays: Int
    let nextRange: DateInterval
    let sourceEventID: UUID
    let sourceText: String?
    let isExplicit: Bool
}

private struct MileageEstimate {
    let intervalMiles: Int
    let nextMileage: Int
    let sourceEventID: UUID
    let sourceText: String?
    let isExplicit: Bool
}

private struct ExplicitInterval {
    let event: LedgerEvent
    let value: Double
    let sourceText: String?
}

private enum ExplicitIntervalUnitKind {
    case calendar
    case mileage
}
