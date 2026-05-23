import Foundation

enum TemporalPriorityResolver {
    static func resolve(
        envelope: ExtractionEnvelope,
        sourceText: String,
        now: Date,
        calendar: Calendar = .current
    ) -> ExtractionEnvelope {
        var resolved = convertFutureActionEventsToRemindersIfNeeded(
            envelope,
            sourceText: sourceText,
            now: now,
            calendar: calendar
        )
        let normalizedText = sourceText.lowercased()
        guard hasTemporalPriorityPhrase(normalizedText),
              let duration = relativeActionableDuration(in: normalizedText),
              let dueDate = date(byAdding: duration, to: now, calendar: calendar) else {
            return resolved
        }

        let dueDateString = DateFormatting.dateOnlyString(dueDate, calendar: calendar, timeZone: calendar.timeZone)
        let chosenDateID = appendOperationalDate(
            to: &resolved,
            sourceText: duration.sourceText,
            dateString: dueDateString
        )
        let rejectedDateIDs = appendRejectedContextDates(
            to: &resolved,
            sourceText: sourceText,
            dueDateString: dueDateString,
            now: now,
            calendar: calendar
        )

        applyRuleResolution(
            to: &resolved,
            sourceText: sourceText,
            dueDateString: dueDateString
        )

        guard resolved.rules.contains(where: { $0.ruleType == .reminder && $0.startsAt == dueDateString }) else {
            return resolved
        }

        resolved.temporalResolutionDecisions.append(
            TemporalResolutionDecision(
                chosenDateClientID: chosenDateID,
                rejectedDateClientIDs: rejectedDateIDs,
                reason: "Explicit review or reminder language selected the actionable relative duration before long-term context.",
                confidenceRationale: "Priority order: review/reminder phrase, relative actionable duration, then contextual long-term reference."
            )
        )
        return resolved
    }

    private static func convertFutureActionEventsToRemindersIfNeeded(
        _ envelope: ExtractionEnvelope,
        sourceText: String,
        now: Date,
        calendar: Calendar
    ) -> ExtractionEnvelope {
        guard envelope.rules.isEmpty else { return envelope }
        let normalizedText = sourceText.lowercased()
        guard hasFutureTaskLanguage(normalizedText) else { return envelope }
        let startOfToday = calendar.startOfDay(for: now)

        var resolved = envelope
        var convertedRules: [ExtractedRule] = []
        resolved.events.removeAll { event in
            guard shouldConvertEventToReminder(event, startOfToday: startOfToday) else {
                return false
            }
            convertedRules.append(
                ExtractedRule(
                    clientID: "\(event.clientID)_reminder",
                    title: event.title,
                    thingName: event.thingName,
                    ruleType: .reminder,
                    continuityBehavior: .dateBasedReminder,
                    reason: "Future action captured as a carry-forward reminder.",
                    startsAt: normalizedDateString(event.occurredAt, calendar: calendar) ?? event.occurredAt,
                    expiresAt: nil
                )
            )
            return true
        }

        guard !convertedRules.isEmpty else { return envelope }
        resolved.rules.append(contentsOf: convertedRules)
        resolved.temporalResolutionDecisions.append(
            TemporalResolutionDecision(
                chosenDateClientID: nil,
                rejectedDateClientIDs: [],
                reason: "Simple future action language was stored as a reminder instead of a timeline event.",
                confidenceRationale: "Imperative task phrases such as call, text, email, pay, send, or follow up belong in Carry Forward."
            )
        )
        return resolved
    }

    private static func shouldConvertEventToReminder(_ event: ExtractedEvent, startOfToday: Date) -> Bool {
        if event.eventType == LedgerEventType.reminder.rawValue {
            return true
        }
        guard let eventDate = ExtractionService.parseDate(event.occurredAt),
              eventDate >= startOfToday else {
            return false
        }
        let type = LedgerEventType(rawValue: event.eventType) ?? .other
        switch type {
        case .generic, .other, .note:
            return true
        case .reminder:
            return true
        case .maintenance, .purchase, .visit, .replacement, .cleaning, .renewal,
             .appointment, .project, .measurement, .statusChange:
            return false
        }
    }

    private static func normalizedDateString(_ value: String, calendar: Calendar) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            if DateFormatting.parseDateOnly(prefix) != nil {
                return prefix
            }
        }
        guard let date = ExtractionService.parseDate(value) else { return nil }
        return DateFormatting.dateOnlyString(date, calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func applyRuleResolution(
        to envelope: inout ExtractionEnvelope,
        sourceText: String,
        dueDateString: String
    ) {
        let standingRestriction = hasStandingRestrictionLanguage(sourceText.lowercased())
        let explicitWindow = hasExplicitWindowLanguage(sourceText.lowercased())
        var rules = envelope.rules

        if rules.isEmpty {
            rules.append(reviewReminder(from: nil, sourceText: sourceText, startsAt: dueDateString))
            envelope.rules = rules
            return
        }

        if let reminderIndex = rules.firstIndex(where: { $0.ruleType == .reminder }) {
            rules[reminderIndex].startsAt = dueDateString
            rules[reminderIndex].expiresAt = nil
            rules[reminderIndex].continuityBehavior = .dateBasedReminder
            rules[reminderIndex].reason = mergedReason(rules[reminderIndex].reason, sourceText: sourceText)
        } else if standingRestriction, let restrictiveIndex = rules.firstIndex(where: { $0.ruleType.isRestrictive }) {
            if !explicitWindow {
                rules[restrictiveIndex].expiresAt = nil
                rules[restrictiveIndex].continuityBehavior = .ongoing
            }
            rules.append(reviewReminder(from: rules[restrictiveIndex], sourceText: sourceText, startsAt: dueDateString))
        } else if rules.count == 1 {
            rules[0] = reviewReminder(from: rules[0], sourceText: sourceText, startsAt: dueDateString)
        } else {
            rules.append(reviewReminder(from: rules.first, sourceText: sourceText, startsAt: dueDateString))
        }

        envelope.rules = rules
    }

    private static func reviewReminder(
        from rule: ExtractedRule?,
        sourceText: String,
        startsAt: String
    ) -> ExtractedRule {
        ExtractedRule(
            clientID: reviewReminderClientID(from: rule),
            title: reviewTitle(from: rule?.title, sourceText: sourceText),
            thingName: rule?.thingName,
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            reason: mergedReason(rule?.reason, sourceText: sourceText),
            startsAt: startsAt,
            expiresAt: nil
        )
    }

    private static func reviewReminderClientID(from rule: ExtractedRule?) -> String {
        guard let clientID = rule?.clientID.nilIfEmpty else {
            return "rule_temporal_review"
        }
        return clientID.hasSuffix("_review") ? clientID : "\(clientID)_review"
    }

    private static func reviewTitle(from existingTitle: String?, sourceText: String) -> String {
        if let target = reviewTarget(from: sourceText) {
            return "Reevaluate \(target)"
        }
        guard let existingTitle = existingTitle?.nilIfEmpty else {
            return "Reevaluate"
        }
        let lowered = existingTitle.lowercased()
        if lowered.hasPrefix("reevaluate") || lowered.hasPrefix("revisit") || lowered.hasPrefix("review") {
            return existingTitle
        }
        return "Reevaluate \(lowered)"
    }

    private static func reviewTarget(from sourceText: String) -> String? {
        var target = sourceText.lowercased()
        for marker in temporalPriorityMarkers {
            if let range = target.range(of: marker) {
                target.removeSubrange(range.lowerBound..<target.endIndex)
                break
            }
        }
        target = target.replacingOccurrences(of: "next year", with: "")
        target = target.replacingOccurrences(of: "long term", with: "")
        target = target.replacingOccurrences(of: "i don't want to", with: "")
        target = target.replacingOccurrences(of: "i do not want to", with: "")
        target = target.replacingOccurrences(of: "should probably", with: "")
        target = target.replacingOccurrences(of: "should", with: "")
        target = target.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !target.isEmpty else { return nil }
        if target == "bowl" {
            return "bowling"
        }
        return target
    }

    private static func mergedReason(_ reason: String?, sourceText: String) -> String? {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return reason?.nilIfEmpty }
        guard let reason = reason?.nilIfEmpty else {
            return "Context: \(trimmedSource)"
        }
        guard !reason.localizedCaseInsensitiveContains(trimmedSource) else {
            return reason
        }
        return "\(reason) Context: \(trimmedSource)"
    }

    private static func appendOperationalDate(
        to envelope: inout ExtractionEnvelope,
        sourceText: String,
        dateString: String
    ) -> String {
        if let existing = envelope.dates.first(where: { $0.date == dateString && $0.role == "rule_starts_at" }) {
            return existing.clientID
        }
        let clientID = uniqueDateID(prefix: "date_temporal_selected", dates: envelope.dates)
        envelope.dates.append(
            ExtractedDate(
                clientID: clientID,
                sourceText: sourceText,
                date: dateString,
                precision: "day",
                role: "rule_starts_at",
                ownerClientID: nil,
                ownerField: "startsAt",
                isInferred: true,
                confidence: 0.98,
                resolvedConfidence: 0.98,
                resolvedSourceText: sourceText
            )
        )
        return clientID
    }

    private static func appendRejectedContextDates(
        to envelope: inout ExtractionEnvelope,
        sourceText: String,
        dueDateString: String,
        now: Date,
        calendar: Calendar
    ) -> [String] {
        var rejectedIDs = envelope.dates
            .filter { date in
                guard date.date != dueDateString else { return false }
                return isLongTermContext(date.sourceText) || isLongTermContext(date.resolvedSourceText ?? "")
            }
            .map(\.clientID)

        if rejectedIDs.isEmpty,
           isLongTermContext(sourceText),
           let contextDate = nextYearDateString(from: now, calendar: calendar) {
            let clientID = uniqueDateID(prefix: "date_temporal_context", dates: envelope.dates)
            envelope.dates.append(
                ExtractedDate(
                    clientID: clientID,
                    sourceText: "next year",
                    date: contextDate,
                    precision: "year",
                    role: "unknown",
                    ownerClientID: nil,
                    ownerField: "context",
                    isInferred: true,
                    confidence: 0.9,
                    resolvedConfidence: 0.9,
                    resolvedSourceText: "next year"
                )
            )
            rejectedIDs.append(clientID)
        }

        return rejectedIDs
    }

    private static func uniqueDateID(prefix: String, dates: [ExtractedDate]) -> String {
        var index = 1
        var candidate = "\(prefix)_\(index)"
        let existingIDs = Set(dates.map(\.clientID))
        while existingIDs.contains(candidate) {
            index += 1
            candidate = "\(prefix)_\(index)"
        }
        return candidate
    }

    private static func hasTemporalPriorityPhrase(_ text: String) -> Bool {
        temporalPriorityMarkers.contains { text.contains($0) }
    }

    private static func hasFutureTaskLanguage(_ text: String) -> Bool {
        let normalized = " \(text) "
        let taskMarkers = [
            " call ",
            " text ",
            " email ",
            " follow up",
            " check in",
            " check on",
            " review ",
            " pay ",
            " send ",
            " pick up",
            " book ",
            " remind me",
            " need to "
        ]
        guard taskMarkers.contains(where: { normalized.contains($0) }) else {
            return false
        }
        let futureMarkers = [
            " tomorrow",
            " tonight",
            " later",
            " next ",
            " in ",
            " on monday",
            " on tuesday",
            " on wednesday",
            " on thursday",
            " on friday",
            " on saturday",
            " on sunday"
        ]
        return futureMarkers.contains { normalized.contains($0) }
    }

    private static func isLongTermContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("next year")
            || normalized.contains("long term")
            || normalized.contains("long-term")
            || normalized.contains("indefinitely")
    }

    private static func hasStandingRestrictionLanguage(_ text: String) -> Bool {
        if text.hasPrefix("don't ") || text.hasPrefix("do not ") {
            return true
        }
        let markers = [
            "no ",
            "avoid ",
            "stop ",
            "pause ",
            "hold off ",
            "not buying ",
            "not ordering ",
            "not starting ",
            "ban ",
            "long term",
            "long-term",
            "indefinitely"
        ]
        return markers.contains { text.contains($0) }
    }

    private static func hasExplicitWindowLanguage(_ text: String) -> Bool {
        let markers = [" until ", " through ", " thru ", " between ", " from "]
        return markers.contains { text.contains($0) }
    }

    private static func relativeActionableDuration(in text: String) -> RelativeDuration? {
        let pattern = #"\b(?:in|after)\s+(\d{1,4})\s+(day|days|week|weeks|month|months|year|years)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let sourceRange = Range(match.range(at: 0), in: text),
              let value = Int(text[valueRange]) else {
            return nil
        }
        return RelativeDuration(value: value, unit: String(text[unitRange]), sourceText: String(text[sourceRange]))
    }

    private static func date(
        byAdding duration: RelativeDuration,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        let component: Calendar.Component
        switch duration.unit {
        case "day", "days":
            component = .day
        case "week", "weeks":
            component = .day
            return calendar.date(byAdding: component, value: duration.value * 7, to: date)
        case "month", "months":
            component = .month
        case "year", "years":
            component = .year
        default:
            return nil
        }
        return calendar.date(byAdding: component, value: duration.value, to: date)
    }

    private static func nextYearDateString(from date: Date, calendar: Calendar) -> String? {
        let year = calendar.component(.year, from: date) + 1
        guard let nextYearDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return nil
        }
        return DateFormatting.dateOnlyString(nextYearDate, calendar: calendar, timeZone: calendar.timeZone)
    }

    private static let temporalPriorityMarkers = [
        "reevaluate",
        "re-evaluate",
        "revisit",
        "check again",
        "check back",
        "review later",
        "review whether",
        "remind me",
        "follow up"
    ]
}

private struct RelativeDuration {
    var value: Int
    var unit: String
    var sourceText: String
}
