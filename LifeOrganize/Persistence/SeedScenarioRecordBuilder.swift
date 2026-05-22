import Foundation
import SwiftData

struct SeedScenarioRecordBuilder {
    let context: ModelContext
    let fixture: SeedScenarioFixture

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: fixture.clock.timeZone) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func insertRecords() throws {
        for message in fixture.records.chatMessages {
            try upsert(message)
        }
        for run in fixture.records.extractionRuns {
            try upsert(run)
        }
        for thing in fixture.records.things {
            try upsert(thing)
        }
        for event in fixture.records.events {
            try upsert(event)
        }
        for rule in fixture.records.rules {
            try upsert(rule)
        }
        for note in fixture.records.notes {
            try upsert(note)
        }
        for link in fixture.records.entityLinks {
            try upsert(link)
        }
        for item in fixture.records.ledgerReviewItems {
            try upsert(item)
        }
    }

    @discardableResult
    private func upsert(_ record: ChatMessageExport) throws -> ChatMessage {
        let id = try uuid(record.id, field: "chatMessages.id")
        let extractionState = record.extractionState
        let message: ChatMessage
        if let existing = try fetchChatMessage(id: id) {
            message = existing
        } else {
            message = ChatMessage(
                id: id,
                role: chatRole(record.role),
                text: record.text,
                createdAt: try timestamp(record.createdAt, field: "chatMessages.createdAt")
            )
            context.insert(message)
        }
        message.role = chatRole(record.role)
        message.text = record.text
        message.createdAt = try timestamp(record.createdAt, field: "chatMessages.createdAt")
        message.extractionStatus = extractionState.map { extractionStatus($0.status) } ?? .notRequired
        message.extractionError = extractionState?.errorMessage
        message.extractionErrorCode = extractionState?.errorCode.map(extractionErrorCode)
        message.extractionVersion = extractionState?.extractionVersion ?? 1
        message.extractionAttemptCount = extractionState?.attemptCount ?? 0
        message.lastExtractionAttemptAt = try extractionState?.lastAttemptAt.map {
            try timestamp($0, field: "chatMessages.extractionState.lastAttemptAt")
        }
        message.nextExtractionRetryAt = try extractionState?.nextRetryAt.map {
            try timestamp($0, field: "chatMessages.extractionState.nextRetryAt")
        }
        return message
    }

    @discardableResult
    private func upsert(_ record: ExtractionRunExport) throws -> ExtractionAttempt {
        let id = try uuid(record.id, field: "extractionRuns.id")
        let attempt: ExtractionAttempt
        if let existing = try fetchExtractionAttempt(id: id) {
            attempt = existing
        } else {
            attempt = ExtractionAttempt(
                id: id,
                status: extractionAttemptStatus(record.status),
                schemaVersion: record.extractionSchemaVersion,
                promptVersion: record.promptVersion,
                startedAt: try timestamp(record.requestedAt, field: "extractionRuns.requestedAt")
            )
            context.insert(attempt)
        }
        attempt.status = extractionAttemptStatus(record.status)
        attempt.schemaVersion = record.extractionSchemaVersion
        attempt.promptVersion = record.promptVersion
        attempt.modelName = record.model
        attempt.requestJSON = record.requestJSON
        attempt.rawResponseText = record.rawResponseText
        attempt.normalizedJSONText = record.normalizedJSONText
        attempt.errorCode = record.error.map { extractionErrorCode($0.kind) }
        attempt.errorMessage = record.error?.message
        attempt.startedAt = try timestamp(record.requestedAt, field: "extractionRuns.requestedAt")
        attempt.completedAt = try record.completedAt.map { try timestamp($0, field: "extractionRuns.completedAt") }
        attempt.createdThingIDs = try record.createdEntities.things.map { try uuid($0, field: "extractionRuns.createdEntities.things") }
        attempt.createdEventIDs = try record.createdEntities.events.map { try uuid($0, field: "extractionRuns.createdEntities.events") }
        attempt.createdRuleIDs = try record.createdEntities.rules.map { try uuid($0, field: "extractionRuns.createdEntities.rules") }
        attempt.createdNoteIDs = try record.createdEntities.notes.map { try uuid($0, field: "extractionRuns.createdEntities.notes") }
        attempt.sourceMessage = try record.chatMessageId.map { try requiredChatMessage(id: $0) }
        return attempt
    }

    @discardableResult
    private func upsert(_ record: ThingExport) throws -> Thing {
        let id = try uuid(record.id, field: "things.id")
        let thing: Thing
        if let existing = try fetchThing(id: id) {
            thing = existing
        } else {
            thing = Thing(id: id, name: record.name)
            context.insert(thing)
        }
        thing.name = record.name
        thing.normalizedKey = ThingNormalizer.normalizeKey(record.name)
        thing.details = ""
        thing.aliases = ThingAliasPolicy.cleanedAliases(record.aliases, excludingName: record.name)
        thing.categoryRawValue = record.category
        thing.createdAt = try timestamp(record.createdAt, field: "things.createdAt")
        thing.updatedAt = try timestamp(record.updatedAt, field: "things.updatedAt")
        thing.sourceMessageIDs = try record.source.chatMessageId.map { [try uuid($0, field: "things.source.chatMessageId")] } ?? []
        thing.sourceExtractionAttemptIDs = try record.source.extractionRunId.map { [try uuid($0, field: "things.source.extractionRunId")] } ?? []
        thing.eventCount = record.eventCount
        thing.lastEventAt = try record.lastEventAt.map { try dateOnly($0, field: "things.lastEventAt") }
        return thing
    }

    @discardableResult
    private func upsert(_ record: EventExport) throws -> LedgerEvent {
        let id = try uuid(record.id, field: "events.id")
        let event: LedgerEvent
        if let existing = try fetchEvent(id: id) {
            event = existing
        } else {
            event = LedgerEvent(
                id: id,
                title: record.title,
                occurredAt: try dateOnly(record.occurredAt, field: "events.occurredAt"),
                rawText: record.rawText
            )
            context.insert(event)
        }
        event.title = record.title
        event.occurredAt = try dateOnly(record.occurredAt, field: "events.occurredAt")
        event.rawText = record.rawText
        event.createdAt = try timestamp(record.createdAt, field: "events.createdAt")
        event.updatedAt = try timestamp(record.updatedAt, field: "events.updatedAt")
        event.note = record.note
        event.sourceClientID = record.source.sourceClientId
        event.sourceExtractionRunID = try record.source.extractionRunId.map { try uuid($0, field: "events.source.extractionRunId") }
        event.eventTypeRawValue = record.eventType
        event.metadataJSONText = LedgerEvent.encodeSeedMetadata(metadataEntries(record.metadata))
        event.metadataKeyRawValues = record.metadata.map(\.key)
        event.thing = try record.thingId.map { try requiredThing(id: $0) }
        event.sourceMessage = try record.source.chatMessageId.map { try requiredChatMessage(id: $0) }
        return event
    }

    @discardableResult
    private func upsert(_ record: RuleExport) throws -> LedgerRule {
        let id = try uuid(record.id, field: "rules.id")
        let rule: LedgerRule
        if let existing = try fetchRule(id: id) {
            rule = existing
        } else {
            rule = LedgerRule(
                id: id,
                title: record.title,
                startsAt: try dateOnly(record.startsAt, field: "rules.startsAt")
            )
            context.insert(rule)
        }
        rule.title = record.title
        rule.reason = record.reason
        rule.rawText = record.rawText
        rule.startsAt = try dateOnly(record.startsAt, field: "rules.startsAt")
        rule.expiresAt = try record.expiresAt.map { try dateOnly($0, field: "rules.expiresAt") }
        rule.createdAt = try timestamp(record.createdAt, field: "rules.createdAt")
        rule.updatedAt = try timestamp(record.updatedAt, field: "rules.updatedAt")
        rule.manuallyDeactivatedAt = try record.manuallyDeactivatedAt.map {
            try timestamp($0, field: "rules.manuallyDeactivatedAt")
        }
        rule.lifecycleStateRawValue = record.lifecycleState
        rule.sourceClientID = record.source.sourceClientId
        rule.sourceExtractionRunID = try record.source.extractionRunId.map { try uuid($0, field: "rules.source.extractionRunId") }
        rule.ruleTypeRawValue = record.ruleType
        rule.continuityBehaviorRawValue = record.continuityBehavior
        rule.thing = try record.thingId.map { try requiredThing(id: $0) }
        rule.sourceMessage = try record.source.chatMessageId.map { try requiredChatMessage(id: $0) }
        rule.isActive = try RuleStatusService().isActive(rule, at: timestamp(fixture.clock.now, field: "clock.now"))
        return rule
    }

    @discardableResult
    private func upsert(_ record: NoteExport) throws -> LedgerNote {
        let id = try uuid(record.id, field: "notes.id")
        let note: LedgerNote
        if let existing = try fetchNote(id: id) {
            note = existing
        } else {
            note = LedgerNote(id: id)
            context.insert(note)
        }
        note.text = record.text
        note.createdAt = try timestamp(record.createdAt, field: "notes.createdAt")
        note.updatedAt = try timestamp(record.updatedAt, field: "notes.updatedAt")
        note.sourceClientID = record.source.sourceClientId
        note.sourceExtractionRunID = try record.source.extractionRunId.map { try uuid($0, field: "notes.source.extractionRunId") }
        note.sourceMessage = try record.source.chatMessageId.map { try requiredChatMessage(id: $0) }
        note.linkedThings = try record.linkedThingIds.map { try requiredThing(id: $0) }
        return note
    }

    @discardableResult
    private func upsert(_ record: EntityLinkExport) throws -> EntityLink {
        let id = try uuid(record.id, field: "entityLinks.id")
        let link: EntityLink
        if let existing = try fetchEntityLink(id: id) {
            link = existing
        } else {
            link = EntityLink(
                id: id,
                sourceType: entityType(record.fromEntityType),
                sourceID: try uuid(record.fromEntityId, field: "entityLinks.fromEntityId"),
                targetType: entityType(record.toEntityType),
                targetID: try uuid(record.toEntityId, field: "entityLinks.toEntityId"),
                relation: entityRelation(record.relationship, from: record.fromEntityType, to: record.toEntityType),
                createdBy: entityCreator(record.source.kind)
            )
            context.insert(link)
        }
        link.sourceType = entityType(record.fromEntityType)
        link.sourceID = try uuid(record.fromEntityId, field: "entityLinks.fromEntityId")
        link.targetType = entityType(record.toEntityType)
        link.targetID = try uuid(record.toEntityId, field: "entityLinks.toEntityId")
        link.relation = entityRelation(record.relationship, from: record.fromEntityType, to: record.toEntityType)
        link.createdAt = try timestamp(record.createdAt, field: "entityLinks.createdAt")
        link.confidence = 1
        link.createdBy = entityCreator(record.source.kind)
        link.sourceMessageID = try record.source.chatMessageId.map { try uuid($0, field: "entityLinks.source.chatMessageId") }
        return link
    }

    @discardableResult
    private func upsert(_ record: LedgerReviewItemExport) throws -> LedgerReviewItem {
        let id = try uuid(record.id, field: "ledgerReviewItems.id")
        let item: LedgerReviewItem
        if let existing = try fetchReviewItem(id: id) {
            item = existing
        } else {
            item = LedgerReviewItem(
                id: id,
                dedupeKey: record.dedupeKey,
                kind: reviewItemKind(record.kind),
                title: record.title,
                detail: record.detail,
                targetType: reviewItemTargetType(record.targetType),
                targetID: try record.targetId.map { try uuid($0, field: "ledgerReviewItems.targetId") },
                evidence: []
            )
            context.insert(item)
        }
        item.dedupeKey = record.dedupeKey
        item.kind = reviewItemKind(record.kind)
        item.state = reviewItemState(record.state)
        item.title = record.title
        item.detail = record.detail
        item.actionTitle = record.actionTitle
        item.targetType = reviewItemTargetType(record.targetType)
        item.targetID = try record.targetId.map { try uuid($0, field: "ledgerReviewItems.targetId") }
        item.confidence = record.confidence
        item.evidenceJSONText = LedgerReviewItem.encodeSeedEvidence(try reviewItemEvidence(record.evidence))
        item.createdAt = try timestamp(record.createdAt, field: "ledgerReviewItems.createdAt")
        item.updatedAt = try timestamp(record.updatedAt, field: "ledgerReviewItems.updatedAt")
        item.presentedAt = try record.presentedAt.map { try timestamp($0, field: "ledgerReviewItems.presentedAt") }
        item.resolvedAt = try record.resolvedAt.map { try timestamp($0, field: "ledgerReviewItems.resolvedAt") }
        item.snoozedUntil = try record.snoozedUntil.map { try timestamp($0, field: "ledgerReviewItems.snoozedUntil") }
        item.expiresAt = try record.expiresAt.map { try timestamp($0, field: "ledgerReviewItems.expiresAt") }
        item.failureReason = record.failureReason
        return item
    }

    private func metadataEntries(_ records: [EventMetadataExport]) -> [LedgerEventMetadataEntry] {
        records.map {
            LedgerEventMetadataEntry(
                keyRawValue: $0.key,
                valueKindRawValue: $0.valueKind,
                stringValue: $0.stringValue,
                numberValue: $0.numberValue,
                dateValue: $0.dateValue,
                boolValue: $0.boolValue,
                unit: $0.unit,
                sourceText: $0.sourceText
            )
        }
    }

    private func reviewItemEvidence(_ records: [LedgerReviewItemEvidenceExport]) throws -> [LedgerReviewItemEvidence] {
        try records.map {
            LedgerReviewItemEvidence(
                sourceType: reviewItemTargetType($0.sourceType),
                sourceID: try uuid($0.sourceId, field: "ledgerReviewItems.evidence.sourceId"),
                summary: $0.summary,
                detail: $0.detail
            )
        }
    }

    private func timestamp(_ text: String, field: String) throws -> Date {
        try SeedScenarioDateParser.timestamp(text, field: field)
    }

    private func dateOnly(_ text: String, field: String) throws -> Date {
        try SeedScenarioDateParser.dateOnly(text, calendar: calendar, field: field)
    }
}
