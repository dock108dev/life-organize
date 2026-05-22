import Foundation
import SwiftData

@MainActor
struct LedgerReviewItemGenerationService {
    let modelContext: ModelContext
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
    var intervalInference: OperationalIntervalInferenceService = OperationalIntervalInferenceService()
    var ruleStatus: RuleStatusService = RuleStatusService()

    @discardableResult
    func refresh() throws -> [LedgerReviewItem] {
        let date = now()
        let definitions = try currentDefinitions(at: date)
        let currentKeys = Set(definitions.map(\.dedupeKey))
        let existingItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        let existingByKey = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.dedupeKey, $0) })

        for item in existingItems where item.isGeneratorManaged && item.state.isOpen && !currentKeys.contains(item.dedupeKey) {
            item.supersede(at: date)
        }

        for definition in definitions where !isSuppressed(definition, by: existingByKey[definition.dedupeKey]) {
            if let existing = existingByKey[definition.dedupeKey] {
                definition.apply(to: existing, at: date)
            } else {
                modelContext.insert(definition.makeItem(at: date))
            }
        }

        try modelContext.save()
        return try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
            .sorted { lhs, rhs in
                if lhs.state != rhs.state {
                    return lhs.state.sortOrder < rhs.state.sortOrder
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func isSuppressed(_ definition: ReviewItemDefinition, by existing: LedgerReviewItem?) -> Bool {
        guard let existing else { return false }
        return existing.suppressesRepeat
    }

    private func currentDefinitions(at date: Date) throws -> [ReviewItemDefinition] {
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())

        return intervalDefinitions(things: things, now: date)
            + overdueReminderDefinitions(rules: rules, now: date)
            + extractionDefinitions(messages: messages)
            + duplicateThingDefinitions(things: things)
            + conflictingDateDefinitions(events: events)
            + normalizationDefinitions(things: things)
    }

    private func intervalDefinitions(things: [Thing], now: Date) -> [ReviewItemDefinition] {
        things.flatMap { thing in
            intervalInference.inferences(for: thing, now: now).compactMap { inference in
                let intervalText = [
                    inference.calendarIntervalDays.map { "about every \(LedgerDisplayFormatting.count($0, singular: "day", plural: "days"))" },
                    inference.mileageInterval.map { "about every \(Self.integerText($0)) miles" }
                ].compactMap { $0 }.joined(separator: " and ")
                let nextText = [
                    inference.nextExpectedMileage.map { "next mileage \(Self.integerText($0)) mi" },
                    inference.nextExpectedDateRange.map { "next date range \(dateOnly($0.start)) to \(dateOnly($0.end))" }
                ].compactMap { $0 }.joined(separator: "; ")
                let detail = [
                    "Saved records show \(intervalText).",
                    nextText.nilIfEmpty,
                    "No reminder has been created or changed."
                ].compactMap { $0 }.joined(separator: " ")
                return ReviewItemDefinition(
                    dedupeKey: key(.intervalReminder, [thing.id.uuidString, inference.track.rawValue, inference.latestEventID.uuidString]),
                    kind: .intervalReminder,
                    title: "\(inference.track.displayName) cadence is ready for review",
                    detail: detail,
                    actionTitle: "Review reminder setup",
                    targetType: .thing,
                    targetID: thing.id,
                    confidence: inference.confidence.score,
                    evidence: inference.evidence.map {
                        LedgerReviewItemEvidence(
                            sourceType: .event,
                            sourceID: $0.sourceID,
                            summary: $0.summary,
                            detail: $0.detail
                        )
                    }
                )
            }
        }
    }

    private func overdueReminderDefinitions(rules: [LedgerRule], now: Date) -> [ReviewItemDefinition] {
        rules.compactMap { rule in
            guard rule.ruleType.isReminderLike, ruleStatus.status(for: rule, at: now) == .expired else {
                return nil
            }
            return ReviewItemDefinition(
                dedupeKey: key(.overdueReminderReview, [rule.id.uuidString, dateOnly(rule.startsAt)]),
                kind: .overdueReminderReview,
                title: "Reminder is in review",
                detail: "\(rule.title) was due \(dateOnly(rule.startsAt)). Complete, reschedule, pause, or dismiss from the reminder record.",
                actionTitle: "Review reminder",
                targetType: .rule,
                targetID: rule.id,
                confidence: 1,
                evidence: [
                    LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: rule.rawText.nilIfEmpty)
                ]
            )
        }
    }

    private func extractionDefinitions(messages: [ChatMessage]) -> [ReviewItemDefinition] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }
            switch message.extractionStatus {
            case .pendingToken, .pendingRetry:
                return recoveryDefinition(for: message)
            case .partiallySucceeded, .failed, .failedNeedsReview, .needsReview:
                return reviewDefinition(for: message)
            case .notRequired, .pending, .extracting, .succeeded:
                return nil
            }
        }
    }

    private func recoveryDefinition(for message: ChatMessage) -> ReviewItemDefinition {
        let detail: String
        let actionTitle: String
        switch message.extractionStatus {
        case .pendingToken:
            if message.extractionErrorCode == .invalidServiceToken {
                detail = "The original entry is saved locally. Retry this entry to reconnect its details."
            } else {
                detail = "The original entry is saved locally. Retry this entry to connect its details."
            }
            actionTitle = "Retry Now"
        case .pendingRetry:
            detail = pendingRetryDetail(for: message)
            actionTitle = "Retry Now"
        default:
            detail = "The original entry is saved locally and can be reviewed."
            actionTitle = "Review Entry"
        }
        return ReviewItemDefinition(
            dedupeKey: key(.localRecovery, [message.id.uuidString, message.extractionStatus.rawValue]),
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: detail,
            actionTitle: actionTitle,
            targetType: .chatMessage,
            targetID: message.id,
            confidence: 1,
            evidence: [messageEvidence(message)]
        )
    }

    private func pendingRetryDetail(for message: ChatMessage) -> String {
        let action: String
        switch message.extractionErrorCode {
        case .networkUnavailable, .timeout:
            action = "Use Retry Now when your connection is working, or wait for the next automatic retry."
        case .rateLimited:
            action = "Use Retry Now after the limit clears, or wait for the next automatic retry."
        case .serverError:
            action = "Use Retry Now later, or wait for the next automatic retry."
        default:
            action = "Use Retry Now, or wait for the next automatic retry."
        }
        return "The original entry is saved locally. \(action)"
    }

    private func reviewDefinition(for message: ChatMessage) -> ReviewItemDefinition {
        let createdRecordEvidence = createdRecordsEvidence(for: message)
        if let ambiguousReminder = ambiguousReminderDefinition(for: message, createdRecordEvidence: createdRecordEvidence) {
            return ambiguousReminder
        }
        let detail: String
        let actionTitle: String
        switch message.extractionStatus {
        case .partiallySucceeded:
            let count = createdRecordEvidence.count
            let countText = LedgerDisplayFormatting.count(count, singular: "record", plural: "records")
            detail = count > 0
                ? "This entry created \(countText). Open those records to check or edit them."
                : "This entry saved some details but needs review before retrying."
            actionTitle = count > 0 ? "Open Records" : "Review Entry"
        case .failed:
            detail = "The original entry is saved locally. Retry this entry or mark the item reviewed."
            actionTitle = "Retry Now"
        case .failedNeedsReview, .needsReview:
            detail = createdRecordEvidence.isEmpty
                ? "The original entry is saved locally. Retry this entry or review details."
                : "This entry created records and still needs review. Edit the records instead of retrying."
            actionTitle = createdRecordEvidence.isEmpty ? "Retry Now" : "Open Records"
        case .notRequired, .pending, .pendingToken, .pendingRetry, .extracting, .succeeded:
            detail = "The original entry is saved locally and can be reviewed."
            actionTitle = "Review Entry"
        }
        return ReviewItemDefinition(
            dedupeKey: key(.extractionReview, [message.id.uuidString, message.extractionStatus.rawValue]),
            kind: .extractionReview,
            title: "Entry needs review",
            detail: detail,
            actionTitle: actionTitle,
            targetType: .chatMessage,
            targetID: message.id,
            confidence: 1,
            evidence: [messageEvidence(message)] + createdRecordEvidence
        )
    }

    private func duplicateThingDefinitions(things: [Thing]) -> [ReviewItemDefinition] {
        let groups = duplicateThingGroups(things: things)
        return groups.compactMap { group in
            let candidates = group.filter { !$0.name.isEmpty }
            guard candidates.count > 1 else { return nil }
            let sorted = candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return ReviewItemDefinition(
                dedupeKey: key(.duplicateThing, sorted.map { $0.id.uuidString }),
                kind: .duplicateThing,
                title: "Possible duplicate Things",
                detail: "These Things share a normalized name or alias: \(sorted.map(\.name).joined(separator: ", ")). No records have been merged.",
                actionTitle: "Review Things",
                targetType: .thing,
                targetID: sorted.first?.id,
                confidence: 0.8,
                evidence: sorted.map {
                    LedgerReviewItemEvidence(sourceType: .thing, sourceID: $0.id, summary: $0.name, detail: $0.details.nilIfEmpty)
                }
            )
        }
    }

    private func duplicateThingGroups(things: [Thing]) -> [[Thing]] {
        var groupsByKey: [String: [Thing]] = [:]
        for thing in things where !thing.name.isEmpty {
            for key in duplicateKeys(for: thing) {
                groupsByKey[key, default: []].append(thing)
            }
        }

        var seenGroupIDs = Set<String>()
        return groupsByKey.values.compactMap { group in
            let uniqueByID = Dictionary(grouping: group, by: \.id).compactMap(\.value.first)
            guard uniqueByID.count > 1 else { return nil }
            let groupKey = uniqueByID.map { $0.id.uuidString }.sorted().joined(separator: "|")
            guard seenGroupIDs.insert(groupKey).inserted else { return nil }
            return uniqueByID
        }
    }

    private func duplicateKeys(for thing: Thing) -> Set<String> {
        var keys = Set(
            ([thing.normalizedKey, ThingNormalizer.normalizeKey(thing.name)] + thing.aliases.map(ThingNormalizer.normalizeKey))
                .filter { !$0.isEmpty }
        )
        if let seed = ThingNormalizer.seeds.first(where: { seed in
            thing.name == seed.canonicalName || thing.normalizedKey == seed.canonicalKey
        }) {
            keys.formUnion(seed.matchKeys)
            keys.insert(seed.canonicalKey)
        }
        return keys
    }

    private func conflictingDateDefinitions(events: [LedgerEvent]) -> [ReviewItemDefinition] {
        events.compactMap { event in
            guard let conflict = dateConflict(for: event) else { return nil }
            return ReviewItemDefinition(
                dedupeKey: key(.conflictingDate, [event.id.uuidString, conflict.metadataDate]),
                kind: .conflictingDate,
                title: "Event has conflicting dates",
                detail: "\(event.title) is dated \(dateOnly(event.occurredAt)), while saved metadata includes \(conflict.metadataDate). Review the event before changing dates.",
                actionTitle: "Review event",
                targetType: .event,
                targetID: event.id,
                confidence: 0.85,
                evidence: [
                    LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: conflict.sourceText)
                ]
            )
        }
    }

    private func normalizationDefinitions(things: [Thing]) -> [ReviewItemDefinition] {
        things.compactMap { thing in
            let expectedKey = ThingNormalizer.normalizeKey(thing.name)
            let seed = ThingNormalizer.seed(for: thing.name, contextText: [thing.name, thing.details].joined(separator: " "))
            let expectedName = seed?.canonicalName ?? ThingNormalizer.displayName(for: thing.name)
            guard !expectedKey.isEmpty,
                  thing.normalizedKey != expectedKey || thing.name != expectedName else {
                return nil
            }
            return ReviewItemDefinition(
                dedupeKey: key(.normalizationCandidate, [thing.id.uuidString, expectedKey, expectedName]),
                kind: .normalizationCandidate,
                title: "Thing name is ready for review",
                detail: "\(thing.name) can be reviewed against saved naming rules as \(expectedName). No name has been changed.",
                actionTitle: "Review Thing",
                targetType: .thing,
                targetID: thing.id,
                confidence: 0.75,
                evidence: [
                    LedgerReviewItemEvidence(sourceType: .thing, sourceID: thing.id, summary: thing.name, detail: "Normalized key: \(thing.normalizedKey)")
                ]
            )
        }
    }

    private func dateConflict(for event: LedgerEvent) -> (metadataDate: String, sourceText: String?)? {
        let eventDate = dateOnly(event.occurredAt)
        return event.metadataEntries.compactMap { entry -> (String, String?)? in
            guard [.dueDate, .nextDueDate].contains(entry.key), let dateValue = entry.dateValue?.nilIfEmpty else {
                return nil
            }
            return dateValue == eventDate ? nil : (dateValue, entry.sourceText)
        }.first
    }

    private func messageEvidence(_ message: ChatMessage) -> LedgerReviewItemEvidence {
        LedgerReviewItemEvidence(
            sourceType: .chatMessage,
            sourceID: message.id,
            summary: message.text,
            detail: message.extractionErrorCode?.rawValue ?? message.extractionStatus.rawValue
        )
    }

    private func createdRecordsEvidence(for message: ChatMessage) -> [LedgerReviewItemEvidence] {
        let attempts = message.extractionAttempts
        return attempts.flatMap { attempt in
            attempt.createdThingIDs.map {
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: $0, summary: "Created Thing", detail: nil)
            }
                + attempt.createdEventIDs.map {
                    LedgerReviewItemEvidence(sourceType: .event, sourceID: $0, summary: "Created event", detail: nil)
                }
                + attempt.createdRuleIDs.map {
                    LedgerReviewItemEvidence(sourceType: .rule, sourceID: $0, summary: "Created reminder", detail: nil)
                }
                + attempt.createdNoteIDs.map {
                    LedgerReviewItemEvidence(sourceType: .none, sourceID: $0, summary: "Created note", detail: nil)
                }
        }
    }

    private func key(_ kind: LedgerReviewItemKind, _ components: [String]) -> String {
        ([kind.rawValue] + components).joined(separator: "|")
    }

    private func dateOnly(_ date: Date) -> String {
        DateFormatting.dateOnlyString(date, calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func integerText(_ value: Int) -> String {
        LedgerDisplayFormatting.integer(value)
    }
}

struct ReviewItemDefinition {
    let dedupeKey: String
    let kind: LedgerReviewItemKind
    let title: String
    let detail: String
    let actionTitle: String?
    let targetType: LedgerReviewItemTargetType
    let targetID: UUID?
    let confidence: Double
    let evidence: [LedgerReviewItemEvidence]

    func makeItem(at date: Date) -> LedgerReviewItem {
        LedgerReviewItem(
            dedupeKey: dedupeKey,
            kind: kind,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            targetType: targetType,
            targetID: targetID,
            confidence: confidence,
            evidence: evidence,
            createdAt: date,
            updatedAt: date
        )
    }

    func apply(to item: LedgerReviewItem, at date: Date) {
        item.kind = kind
        item.title = title
        item.detail = detail
        item.actionTitle = actionTitle
        item.targetType = targetType
        item.targetID = targetID
        item.confidence = confidence
        item.evidence = evidence
        item.failureReason = nil
        item.resolvedAt = nil
        item.snoozedUntil = nil
        item.updatedAt = date
        item.state = .candidate
    }
}

private extension LedgerReviewItem {
    var isGeneratorManaged: Bool {
        LedgerReviewItemKind.allCases.contains(kind)
    }
}

private extension LedgerReviewItemState {
    var isOpen: Bool {
        switch self {
        case .candidate, .ready, .presented, .failed:
            true
        case .accepted, .dismissed, .snoozed, .superseded, .expired:
            false
        }
    }

    var sortOrder: Int {
        switch self {
        case .ready:
            0
        case .candidate:
            1
        case .presented:
            2
        case .snoozed:
            3
        case .failed:
            4
        case .accepted, .dismissed, .superseded, .expired:
            5
        }
    }
}
