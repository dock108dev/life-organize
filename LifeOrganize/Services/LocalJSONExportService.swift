import Foundation
import SwiftData

enum LocalJSONExportError: LocalizedError {
    case invalidReference(String)
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .invalidReference(let detail), .invalidIdentifier(let detail):
            detail
        }
    }
}

@MainActor
struct LocalJSONExportService {
    let modelContext: ModelContext
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current
    var bundle: Bundle = .main
    var fileManager: FileManager = .default

    func envelope() throws -> LedgerExportEnvelope {
        let chatMessages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let extractionAttempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        let notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())
        let reviewItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        let entityLinks = try modelContext.fetch(FetchDescriptor<EntityLink>())
        let extractionAttemptIDs = Set(extractionAttempts.map(\.id))

        let records = ExportRecords(
            chatMessages: chatMessages
                .sorted { $0.createdAt < $1.createdAt }
                .map { export($0, things: things, extractionAttemptIDs: extractionAttemptIDs) },
            extractionRuns: extractionAttempts
                .sorted { $0.startedAt < $1.startedAt }
                .map(export),
            things: things
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.createdAt < $1.createdAt) }
                .map(export),
            events: events
                .sorted { lhs, rhs in
                    lhs.occurredAt == rhs.occurredAt ? lhs.createdAt > rhs.createdAt : lhs.occurredAt > rhs.occurredAt
                }
                .map(export),
            rules: rules
                .sorted(by: sortRules)
                .map(export),
            notes: notes
                .sorted { $0.createdAt > $1.createdAt }
                .map(export),
            ledgerReviewItems: reviewItems
                .sorted { $0.createdAt > $1.createdAt }
                .map(export),
            entityLinks: entityLinks
                .sorted { $0.createdAt < $1.createdAt }
                .map(export)
        )

        try validate(records)

        return LedgerExportEnvelope(
            schemaVersion: 3,
            exportedAt: timestamp(now()),
            exportedFrom: ExportedFrom(
                appName: appName,
                appBuild: appBuild,
                platform: platformName
            ),
            locale: ExportLocale(calendar: calendar.identifier.exportValue, timeZone: timeZone.identifier),
            records: records
        )
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope())
    }

    func writeExportFile(directory: URL? = nil) throws -> URL {
        let directory = directory ?? fileManager.temporaryDirectory
        let url = directory.appending(path: exportFilename(for: now()))
        try jsonData().write(to: url, options: [.atomic])
        return url
    }

    func exportFilename(for date: Date) -> String {
        "life-ledger-export-\(filenameTimestamp(date)).json"
    }

    private func export(_ message: ChatMessage, things: [Thing], extractionAttemptIDs: Set<UUID>) -> ChatMessageExport {
        let attempts = message.extractionAttempts
            .filter { extractionAttemptIDs.contains($0.id) }
            .sorted { $0.startedAt < $1.startedAt }
        let latestAttemptID = attempts.last?.id
        let successfulAttemptIDs = attempts
            .filter { $0.status == .succeeded || $0.status == .partiallySucceeded }
            .map(\.id)
        let thingIDs = things
            .filter { $0.sourceMessageIDs.contains(message.id) }
            .map(\.id)
        let linkedIDs = Set(
            message.linkedEntityIDs
                + thingIDs
                + message.extractionAttempts.flatMap { attempt in
                    attempt.createdThingIDs + attempt.createdEventIDs + attempt.createdRuleIDs + attempt.createdNoteIDs
                }
        )
        return ChatMessageExport(
            id: message.id.uuidString,
            role: message.role.rawValue,
            text: safe(message.text),
            createdAt: timestamp(message.createdAt),
            linkedEntityIds: linkedIDs.map(\.uuidString).sorted(),
            extractionRunIds: attempts.map { $0.id.uuidString },
            latestExtractionRunId: latestAttemptID?.uuidString,
            successfulExtractionRunIds: successfulAttemptIDs.map(\.uuidString),
            extractionState: exportExtractionState(message)
        )
    }

    private func export(_ attempt: ExtractionAttempt) -> ExtractionRunExport {
        let normalizedJSONText = safe(attempt.normalizedJSONText)
        let parsedResponse = decodeJSONValue(normalizedJSONText)
        return ExtractionRunExport(
            id: attempt.id.uuidString,
            chatMessageId: attempt.sourceMessageID?.uuidString,
            provider: "openai",
            model: safe(attempt.modelName),
            purpose: "extraction",
            extractionSchemaVersion: attempt.schemaVersion,
            promptVersion: attempt.promptVersion,
            requestedAt: timestamp(attempt.startedAt),
            completedAt: attempt.completedAt.map(timestamp),
            status: exportStatus(attempt.status),
            input: attempt.sourceMessage.map {
                ExtractionRunInputExport(userText: safe($0.text), referenceNow: timestamp($0.createdAt), timeZone: timeZone.identifier)
            },
            requestJSON: safe(attempt.requestJSON),
            rawResponseText: safe(attempt.rawResponseText),
            normalizedJSONText: normalizedJSONText,
            parsedResponse: parsedResponse,
            createdEntities: createdEntities(attempt),
            createdEntityIds: Set(
                attempt.createdThingIDs + attempt.createdEventIDs + attempt.createdRuleIDs + attempt.createdNoteIDs
            )
            .map(\.uuidString)
            .sorted(),
            error: attempt.errorMessage.map {
                ExtractionRunErrorExport(kind: attempt.errorCode?.rawValue ?? "unknown", message: safe($0))
            }
        )
    }

    private func exportExtractionState(_ message: ChatMessage) -> ChatMessageExtractionStateExport? {
        guard message.role == .user else { return nil }
        let latestAttempt = message.extractionAttempts.sorted { $0.startedAt < $1.startedAt }.last
        return ChatMessageExtractionStateExport(
            status: message.extractionStatus.rawValue,
            errorCode: message.extractionErrorCode?.rawValue,
            errorMessage: safe(message.extractionError),
            extractionVersion: message.extractionVersion,
            attemptCount: message.extractionAttemptCount,
            lastAttemptAt: message.lastExtractionAttemptAt.map(timestamp),
            nextRetryAt: message.nextExtractionRetryAt.map(timestamp),
            latestAttemptStatus: latestAttempt?.status.rawValue,
            latestAttemptErrorCode: latestAttempt?.errorCode?.rawValue,
            recoveryAction: recoveryAction(for: message)
        )
    }

    private func recoveryAction(for message: ChatMessage) -> String? {
        switch message.extractionStatus {
        case .pendingToken:
            if message.extractionErrorCode == .invalidServiceToken {
                return "Try this entry again when the service is available."
            }
            return "Try this entry again when the service is available."
        case .pendingRetry:
            return "Try this entry again now, or wait for the next automatic retry."
        case .failed, .failedNeedsReview, .needsReview:
            return "Try this entry again, or review the saved text."
        case .partiallySucceeded:
            return "Review or edit the saved items this entry already created."
        case .pending, .extracting:
            return "Reopen the app to recover this entry if it stays unfinished."
        case .notRequired, .succeeded:
            return nil
        }
    }

    private func export(_ thing: Thing) -> ThingExport {
        ThingExport(
            id: thing.id.uuidString,
            name: safe(thing.name),
            aliases: thing.aliases.map(safe),
            category: safe(thing.categoryRawValue),
            createdAt: timestamp(thing.createdAt),
            updatedAt: timestamp(thing.updatedAt),
            lastEventAt: thing.lastEventAt.map(dateOnly),
            eventCount: thing.eventCount,
            source: source(messageID: thing.sourceMessageIDs.first, extractionRunID: thing.sourceExtractionAttemptIDs.first)
        )
    }

    private func export(_ event: LedgerEvent) -> EventExport {
        EventExport(
            id: event.id.uuidString,
            thingId: event.thingID?.uuidString,
            title: safe(event.title),
            eventType: event.eventType.rawValue,
            rawText: safe(event.rawText),
            occurredAt: dateOnly(event.occurredAt),
            createdAt: timestamp(event.createdAt),
            updatedAt: timestamp(event.updatedAt),
            note: safe(event.note),
            metadata: event.metadataEntries.map(export),
            source: source(
                messageID: event.sourceMessageID,
                extractionRunID: event.sourceExtractionRunID,
                sourceClientID: event.sourceClientID
            )
        )
    }

    private func export(_ metadata: LedgerEventMetadataEntry) -> EventMetadataExport {
        EventMetadataExport(
            key: metadata.keyRawValue,
            valueKind: metadata.valueKindRawValue,
            stringValue: safe(metadata.stringValue),
            numberValue: metadata.numberValue,
            dateValue: metadata.dateValue,
            boolValue: metadata.boolValue,
            unit: safe(metadata.unit),
            sourceText: safe(metadata.sourceText)
        )
    }

    private func export(_ rule: LedgerRule) -> RuleExport {
        RuleExport(
            id: rule.id.uuidString,
            thingId: rule.thingID?.uuidString,
            title: safe(rule.title),
            ruleType: rule.ruleType.rawValue,
            continuityBehavior: rule.continuityBehavior.rawValue,
            reason: safe(rule.reason),
            startsAt: dateOnly(rule.startsAt),
            expiresAt: rule.expiresAt.map(dateOnly),
            createdAt: timestamp(rule.createdAt),
            updatedAt: timestamp(rule.updatedAt),
            isActive: rule.isActive,
            lifecycleState: rule.lifecycleState.rawValue,
            manuallyDeactivatedAt: rule.manuallyDeactivatedAt.map(timestamp),
            rawText: safe(rule.rawText),
            source: source(
                messageID: rule.sourceMessageID,
                extractionRunID: rule.sourceExtractionRunID,
                sourceClientID: rule.sourceClientID
            )
        )
    }

    private func export(_ note: LedgerNote) -> NoteExport {
        NoteExport(
            id: note.id.uuidString,
            text: safe(note.text),
            createdAt: timestamp(note.createdAt),
            updatedAt: timestamp(note.updatedAt),
            linkedThingIds: note.linkedThingIDs.map(\.uuidString).sorted(),
            source: source(
                messageID: note.sourceMessageID,
                extractionRunID: note.sourceExtractionRunID,
                sourceClientID: note.sourceClientID
            )
        )
    }

    private func export(_ link: EntityLink) -> EntityLinkExport {
        EntityLinkExport(
            id: link.id.uuidString,
            fromEntityType: exportType(link.sourceType),
            fromEntityId: link.sourceID.uuidString,
            toEntityType: exportType(link.targetType),
            toEntityId: link.targetID.uuidString,
            relationship: exportRelation(link.relation),
            createdAt: timestamp(link.createdAt),
            source: ExportSource(kind: exportCreator(link.createdBy), chatMessageId: link.sourceMessageID?.uuidString)
        )
    }

    private func export(_ item: LedgerReviewItem) -> LedgerReviewItemExport {
        LedgerReviewItemExport(
            id: item.id.uuidString,
            kind: item.kind.rawValue,
            state: item.state.rawValue,
            title: safe(item.title),
            detail: safe(item.detail),
            actionTitle: safe(item.actionTitle),
            targetType: item.targetType.rawValue,
            targetId: item.targetID?.uuidString,
            dedupeKey: safe(item.dedupeKey),
            confidence: item.confidence,
            createdAt: timestamp(item.createdAt),
            updatedAt: timestamp(item.updatedAt),
            presentedAt: item.presentedAt.map(timestamp),
            resolvedAt: item.resolvedAt.map(timestamp),
            snoozedUntil: item.snoozedUntil.map(timestamp),
            expiresAt: item.expiresAt.map(timestamp),
            failureReason: safe(item.failureReason),
            evidence: item.evidence.map(export)
        )
    }

    private func export(_ evidence: LedgerReviewItemEvidence) -> LedgerReviewItemEvidenceExport {
        LedgerReviewItemEvidenceExport(
            sourceType: evidence.sourceType.rawValue,
            sourceId: evidence.sourceID.uuidString,
            summary: safe(evidence.summary),
            detail: safe(evidence.detail)
        )
    }

    private func source(messageID: UUID?, extractionRunID: UUID?, sourceClientID: String? = nil) -> ExportSource {
        if messageID != nil || extractionRunID != nil || sourceClientID != nil {
            return ExportSource(
                kind: "extracted",
                chatMessageId: messageID?.uuidString,
                extractionRunId: extractionRunID?.uuidString,
                sourceClientId: safe(sourceClientID)
            )
        }
        return ExportSource(kind: "manual")
    }

    private func createdEntities(_ attempt: ExtractionAttempt) -> ExtractionRunCreatedEntitiesExport {
        ExtractionRunCreatedEntitiesExport(
            things: attempt.createdThingIDs.map(\.uuidString).sorted(),
            events: attempt.createdEventIDs.map(\.uuidString).sorted(),
            rules: attempt.createdRuleIDs.map(\.uuidString).sorted(),
            notes: attempt.createdNoteIDs.map(\.uuidString).sorted()
        )
    }

    private func exportStatus(_ status: ExtractionAttemptStatus) -> String {
        status.rawValue
    }

    private func exportType(_ type: EntityLinkType) -> String {
        switch type {
        case .chatMessage:
            "chatMessage"
        case .event:
            "event"
        case .note:
            "note"
        case .rule:
            "rule"
        case .thing:
            "thing"
        }
    }

    private func exportRelation(_ relation: EntityLinkRelation) -> String {
        switch relation {
        case .extractedFrom:
            "created_from"
        case .mentionsThing:
            "mentions"
        case .aboutThing, .primaryThing:
            "linked_to"
        case .sameMessage:
            "related_to"
        }
    }

    private func exportCreator(_ creator: EntityLinkCreator) -> String {
        switch creator {
        case .extraction:
            "extracted"
        case .system:
            "system"
        case .user:
            "manual"
        }
    }

    private func decodeJSONValue(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func safe(_ value: String?) -> String? {
        SecretRedactor.redact(value)
    }

    private func safe(_ value: String) -> String {
        SecretRedactor.redact(value)
    }

    private func sortRules(_ lhs: LedgerRule, _ rhs: LedgerRule) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }
        switch (lhs.expiresAt, rhs.expiresAt) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs < rhs
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func timestamp(_ date: Date) -> String {
        DateFormatting.isoDateTimeString(date, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func dateOnly(_ date: Date) -> String {
        DateFormatting.dateOnlyString(date, calendar: calendar, timeZone: timeZone)
    }

    private func filenameTimestamp(_ date: Date) -> String {
        DateFormatting.filenameTimestamp(date, calendar: calendar, timeZone: timeZone)
    }

    private var appName: String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "LifeOrganize"
    }

    private var appBuild: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var platformName: String {
        #if targetEnvironment(simulator)
        "iOS Simulator"
        #else
        "iOS"
        #endif
    }
}

private extension Calendar.Identifier {
    var exportValue: String {
        switch self {
        case .gregorian:
            "gregorian"
        default:
            String(describing: self)
        }
    }
}
