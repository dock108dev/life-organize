import Foundation

struct LedgerExportComparePolicy: Equatable {
    enum Kind: Equatable {
        case exactExportEquality
        case canonicalLedgerEquality
        case extractionProvenanceEquality
        case uiFacingScenarioEquality
    }

    let kind: Kind
    let ignoresExportedAt: Bool
    let ignoresAppBuild: Bool
    let ignoresPlatform: Bool
    let comparesLocale: Bool

    static let exactExportEquality = LedgerExportComparePolicy(
        kind: .exactExportEquality,
        ignoresExportedAt: false,
        ignoresAppBuild: false,
        ignoresPlatform: false,
        comparesLocale: true
    )

    static let canonicalLedgerEquality = LedgerExportComparePolicy(
        kind: .canonicalLedgerEquality,
        ignoresExportedAt: true,
        ignoresAppBuild: true,
        ignoresPlatform: true,
        comparesLocale: true
    )

    static let extractionProvenanceEquality = LedgerExportComparePolicy(
        kind: .extractionProvenanceEquality,
        ignoresExportedAt: true,
        ignoresAppBuild: true,
        ignoresPlatform: true,
        comparesLocale: true
    )

    static let uiFacingScenarioEquality = LedgerExportComparePolicy(
        kind: .uiFacingScenarioEquality,
        ignoresExportedAt: true,
        ignoresAppBuild: true,
        ignoresPlatform: true,
        comparesLocale: true
    )
}

struct LedgerExportComparisonResult: Equatable {
    let isEqual: Bool
    let differences: [LedgerExportDifference]
}

struct LedgerExportDifference: Equatable {
    let path: String
    let kind: LedgerExportDifferenceKind
    let expected: String?
    let actual: String?
}

enum LedgerExportDifferenceKind: String, Equatable {
    case missingRecord
    case unexpectedRecord
    case valueMismatch
    case schemaMismatch
}

struct LedgerExportCompareService {
    func compare(
        expected: LedgerExportEnvelope,
        actual: LedgerExportEnvelope,
        policy: LedgerExportComparePolicy
    ) -> LedgerExportComparisonResult {
        let canonicalizer = LedgerExportCanonicalizer()
        let expectedValue = canonicalizer.canonicalize(expected, policy: policy).jsonValue
        let actualValue = canonicalizer.canonicalize(actual, policy: policy).jsonValue
        let differences = LedgerExportJSONDiffer().differences(expected: expectedValue, actual: actualValue)
        return LedgerExportComparisonResult(isEqual: differences.isEmpty, differences: differences)
    }
}

struct LedgerExportCanonicalizer {
    func canonicalize(_ envelope: LedgerExportEnvelope, policy: LedgerExportComparePolicy) -> LedgerExportEnvelope {
        if policy.kind == .exactExportEquality {
            return envelope
        }

        var records = canonicalRecords(envelope.records, policy: policy)
        if policy.kind == .extractionProvenanceEquality {
            records = ExportRecords(
                chatMessages: records.chatMessages,
                extractionRuns: records.extractionRuns,
                things: [],
                events: [],
                rules: [],
                notes: [],
                ledgerReviewItems: [],
                entityLinks: []
            )
        } else if policy.kind == .uiFacingScenarioEquality {
            records = ExportRecords(
                chatMessages: records.chatMessages,
                extractionRuns: [],
                things: records.things,
                events: records.events,
                rules: records.rules,
                notes: records.notes,
                ledgerReviewItems: records.ledgerReviewItems,
                entityLinks: records.entityLinks
            )
        }

        return LedgerExportEnvelope(
            schemaVersion: envelope.schemaVersion,
            exportedAt: policy.ignoresExportedAt ? "<ignored>" : envelope.exportedAt,
            exportedFrom: ExportedFrom(
                appName: envelope.exportedFrom.appName,
                appBuild: policy.ignoresAppBuild ? "<ignored>" : envelope.exportedFrom.appBuild,
                platform: policy.ignoresPlatform ? "<ignored>" : envelope.exportedFrom.platform
            ),
            locale: policy.comparesLocale ? envelope.locale : ExportLocale(calendar: "<ignored>", timeZone: "<ignored>"),
            records: records
        )
    }

    private func canonicalRecords(_ records: ExportRecords, policy: LedgerExportComparePolicy) -> ExportRecords {
        let runOrder = Dictionary(uniqueKeysWithValues: records.extractionRuns.map { ($0.id, $0.requestedAt) })
        return ExportRecords(
            chatMessages: records.chatMessages.map { canonicalMessage($0, runOrder: runOrder, policy: policy) }
                .sorted(by: sortMessages),
            extractionRuns: records.extractionRuns.map(canonicalRun)
                .sorted(by: sortRuns),
            things: records.things.map { canonicalThing($0, policy: policy) }
                .sorted(by: sortThings),
            events: records.events.map { canonicalEvent($0, policy: policy) }
                .sorted(by: sortEvents),
            rules: records.rules.map { canonicalRule($0, policy: policy) }
                .sorted(by: sortRules),
            notes: records.notes.map { canonicalNote($0, policy: policy) }
                .sorted(by: sortNotes),
            ledgerReviewItems: records.ledgerReviewItems.map { canonicalReviewItem($0, policy: policy) }
                .sorted(by: sortReviewItems),
            entityLinks: records.entityLinks.map { canonicalEntityLink($0, policy: policy) }
                .sorted(by: sortEntityLinks)
        )
    }

    private func canonicalMessage(
        _ message: ChatMessageExport,
        runOrder: [String: String],
        policy: LedgerExportComparePolicy
    ) -> ChatMessageExport {
        ChatMessageExport(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            linkedEntityIds: sortedIDs(message.linkedEntityIds),
            extractionRunIds: policy.kind == .uiFacingScenarioEquality ? [] : sortRunIDs(message.extractionRunIds, runOrder: runOrder),
            latestExtractionRunId: policy.kind == .uiFacingScenarioEquality ? nil : message.latestExtractionRunId,
            successfulExtractionRunIds: policy.kind == .uiFacingScenarioEquality
                ? []
                : sortRunIDs(message.successfulExtractionRunIds, runOrder: runOrder),
            extractionState: policy.kind == .uiFacingScenarioEquality ? nil : message.extractionState
        )
    }

    private func canonicalRun(_ run: ExtractionRunExport) -> ExtractionRunExport {
        ExtractionRunExport(
            id: run.id,
            chatMessageId: run.chatMessageId,
            provider: run.provider,
            model: run.model,
            purpose: run.purpose,
            extractionSchemaVersion: run.extractionSchemaVersion,
            promptVersion: run.promptVersion,
            requestedAt: run.requestedAt,
            completedAt: run.completedAt,
            status: run.status,
            input: run.input,
            requestJSON: run.requestJSON,
            rawResponseText: run.rawResponseText,
            normalizedJSONText: run.normalizedJSONText,
            parsedResponse: run.parsedResponse,
            createdEntities: ExtractionRunCreatedEntitiesExport(
                things: sortedIDs(run.createdEntities.things),
                events: sortedIDs(run.createdEntities.events),
                rules: sortedIDs(run.createdEntities.rules),
                notes: sortedIDs(run.createdEntities.notes)
            ),
            createdEntityIds: sortedIDs(run.createdEntityIds),
            error: run.error
        )
    }

    private func canonicalThing(_ thing: ThingExport, policy: LedgerExportComparePolicy) -> ThingExport {
        ThingExport(
            id: thing.id,
            name: thing.name,
            aliases: thing.aliases.sorted(),
            category: thing.category,
            createdAt: thing.createdAt,
            updatedAt: thing.updatedAt,
            lastEventAt: thing.lastEventAt,
            eventCount: thing.eventCount,
            source: canonicalSource(thing.source, policy: policy)
        )
    }

    private func canonicalEvent(_ event: EventExport, policy: LedgerExportComparePolicy) -> EventExport {
        EventExport(
            id: event.id,
            thingId: event.thingId,
            title: event.title,
            eventType: event.eventType,
            rawText: event.rawText,
            occurredAt: event.occurredAt,
            createdAt: event.createdAt,
            updatedAt: event.updatedAt,
            note: event.note,
            metadata: event.metadata.sorted(by: sortMetadata),
            source: canonicalSource(event.source, policy: policy)
        )
    }

    private func canonicalRule(_ rule: RuleExport, policy: LedgerExportComparePolicy) -> RuleExport {
        RuleExport(
            id: rule.id,
            thingId: rule.thingId,
            title: rule.title,
            ruleType: rule.ruleType,
            continuityBehavior: rule.continuityBehavior,
            reason: rule.reason,
            startsAt: rule.startsAt,
            expiresAt: rule.expiresAt,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt,
            isActive: rule.isActive,
            lifecycleState: rule.lifecycleState,
            manuallyDeactivatedAt: rule.manuallyDeactivatedAt,
            rawText: rule.rawText,
            source: canonicalSource(rule.source, policy: policy)
        )
    }

    private func canonicalNote(_ note: NoteExport, policy: LedgerExportComparePolicy) -> NoteExport {
        NoteExport(
            id: note.id,
            text: note.text,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            linkedThingIds: sortedIDs(note.linkedThingIds),
            source: canonicalSource(note.source, policy: policy)
        )
    }

    private func canonicalEntityLink(_ link: EntityLinkExport, policy: LedgerExportComparePolicy) -> EntityLinkExport {
        EntityLinkExport(
            id: link.id,
            fromEntityType: link.fromEntityType,
            fromEntityId: link.fromEntityId,
            toEntityType: link.toEntityType,
            toEntityId: link.toEntityId,
            relationship: link.relationship,
            createdAt: link.createdAt,
            source: canonicalSource(link.source, policy: policy)
        )
    }

    private func canonicalReviewItem(
        _ item: LedgerReviewItemExport,
        policy: LedgerExportComparePolicy
    ) -> LedgerReviewItemExport {
        LedgerReviewItemExport(
            id: item.id,
            kind: item.kind,
            state: item.state,
            title: item.title,
            detail: item.detail,
            actionTitle: item.actionTitle,
            targetType: item.targetType,
            targetId: item.targetId,
            dedupeKey: item.dedupeKey,
            confidence: item.confidence,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            presentedAt: item.presentedAt,
            resolvedAt: item.resolvedAt,
            snoozedUntil: item.snoozedUntil,
            expiresAt: item.expiresAt,
            failureReason: item.failureReason,
            evidence: item.evidence.sorted(by: sortEvidence)
        )
    }

    private func canonicalSource(_ source: ExportSource, policy: LedgerExportComparePolicy) -> ExportSource {
        guard policy.kind == .uiFacingScenarioEquality else { return source }
        return ExportSource(kind: source.kind)
    }

    private func sortedIDs(_ values: [String]) -> [String] {
        values.sorted()
    }

    private func sortRunIDs(_ values: [String], runOrder: [String: String]) -> [String] {
        values.sorted {
            let lhsOrder = runOrder[$0] ?? $0
            let rhsOrder = runOrder[$1] ?? $1
            return lhsOrder == rhsOrder ? $0 < $1 : lhsOrder < rhsOrder
        }
    }

    private func sortMessages(_ lhs: ChatMessageExport, _ rhs: ChatMessageExport) -> Bool {
        first(compare(lhs.createdAt, rhs.createdAt), compare(lhs.role, rhs.role)) ?? (lhs.id < rhs.id)
    }

    private func sortRuns(_ lhs: ExtractionRunExport, _ rhs: ExtractionRunExport) -> Bool {
        first(
            compare(lhs.requestedAt, rhs.requestedAt),
            compareOptional(lhs.completedAt, rhs.completedAt, nilsLast: true)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortThings(_ lhs: ThingExport, _ rhs: ThingExport) -> Bool {
        first(
            compare(lhs.name.lowercased(), rhs.name.lowercased()),
            compareOptional(lhs.category, rhs.category, nilsLast: false),
            compare(lhs.createdAt, rhs.createdAt)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortEvents(_ lhs: EventExport, _ rhs: EventExport) -> Bool {
        first(
            compare(rhs.occurredAt, lhs.occurredAt),
            compare(rhs.createdAt, lhs.createdAt),
            compare(lhs.title, rhs.title)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortRules(_ lhs: RuleExport, _ rhs: RuleExport) -> Bool {
        first(
            compareBool(rhs.isActive, lhs.isActive),
            compare(rhs.startsAt, lhs.startsAt),
            compareOptional(lhs.expiresAt, rhs.expiresAt, nilsLast: true),
            compare(lhs.title, rhs.title)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortNotes(_ lhs: NoteExport, _ rhs: NoteExport) -> Bool {
        first(compare(rhs.createdAt, lhs.createdAt), compare(lhs.text, rhs.text)) ?? (lhs.id < rhs.id)
    }

    private func sortReviewItems(_ lhs: LedgerReviewItemExport, _ rhs: LedgerReviewItemExport) -> Bool {
        first(
            compare(lhs.state, rhs.state),
            compare(rhs.createdAt, lhs.createdAt),
            compare(lhs.dedupeKey, rhs.dedupeKey)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortEntityLinks(_ lhs: EntityLinkExport, _ rhs: EntityLinkExport) -> Bool {
        first(
            compare(lhs.createdAt, rhs.createdAt),
            compare(lhs.fromEntityType, rhs.fromEntityType),
            compare(lhs.fromEntityId, rhs.fromEntityId),
            compare(lhs.relationship, rhs.relationship),
            compare(lhs.toEntityType, rhs.toEntityType),
            compare(lhs.toEntityId, rhs.toEntityId)
        ) ?? (lhs.id < rhs.id)
    }

    private func sortMetadata(_ lhs: EventMetadataExport, _ rhs: EventMetadataExport) -> Bool {
        first(
            compare(lhs.key, rhs.key),
            compare(lhs.valueKind, rhs.valueKind),
            compareOptional(lhs.sourceText, rhs.sourceText, nilsLast: true),
            compareOptional(lhs.stringValue, rhs.stringValue, nilsLast: true),
            compareOptional(lhs.numberValue, rhs.numberValue, nilsLast: true),
            compareOptional(lhs.dateValue, rhs.dateValue, nilsLast: true),
            compareOptionalBool(lhs.boolValue, rhs.boolValue, nilsLast: true),
            compareOptional(lhs.unit, rhs.unit, nilsLast: true)
        ) ?? false
    }

    private func sortEvidence(
        _ lhs: LedgerReviewItemEvidenceExport,
        _ rhs: LedgerReviewItemEvidenceExport
    ) -> Bool {
        first(
            compare(lhs.sourceType, rhs.sourceType),
            compare(lhs.sourceId, rhs.sourceId),
            compare(lhs.summary, rhs.summary),
            compareOptional(lhs.detail, rhs.detail, nilsLast: true)
        ) ?? false
    }

    private func first(_ values: Bool?...) -> Bool? {
        values.compactMap { $0 }.first
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool? {
        lhs == rhs ? nil : lhs < rhs
    }

    private func compareBool(_ lhs: Bool, _ rhs: Bool) -> Bool? {
        lhs == rhs ? nil : (!lhs && rhs)
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?, nilsLast: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return compare(lhs, rhs)
        case (nil, nil):
            return nil
        case (nil, _?):
            return !nilsLast
        case (_?, nil):
            return nilsLast
        }
    }

    private func compareOptionalBool(_ lhs: Bool?, _ rhs: Bool?, nilsLast: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return compareBool(lhs, rhs)
        case (nil, nil):
            return nil
        case (nil, _?):
            return !nilsLast
        case (_?, nil):
            return nilsLast
        }
    }
}

extension Encodable {
    var jsonValue: JSONValue {
        let data = encodedData
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }

    var encodedData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }
}
