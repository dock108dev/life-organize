import Foundation
import SwiftData

enum LifeOrganizeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LifeOrganizeSchemaV2.ChatMessage.self,
            LifeOrganizeSchemaV2.ExtractionAttempt.self,
            LifeOrganizeSchemaV2.EntityLink.self,
            LifeOrganizeSchemaV2.Thing.self,
            LifeOrganizeSchemaV2.LedgerEvent.self,
            LifeOrganizeSchemaV2.LedgerRule.self,
            LifeOrganizeSchemaV2.LedgerNote.self
        ]
    }

    @Model
    final class ChatMessage {
        @Attribute(.unique) var id: UUID
        var roleRawValue: String
        var text: String
        var createdAt: Date
        var rawLLMResponse: String?
        var extractionStatusRawValue: String
        var extractionError: String?
        var extractionErrorCodeRawValue: String?
        var extractionVersion: Int
        var extractionAttemptCount: Int = 0
        var lastExtractionAttemptAt: Date?
        var nextExtractionRetryAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LedgerEvent.sourceMessage)
        var events: [LedgerEvent]

        @Relationship(deleteRule: .nullify, inverse: \LedgerRule.sourceMessage)
        var rules: [LedgerRule]

        @Relationship(deleteRule: .nullify, inverse: \LedgerNote.sourceMessage)
        var notes: [LedgerNote]

        @Relationship(deleteRule: .cascade, inverse: \ExtractionAttempt.sourceMessage)
        var extractionAttempts: [ExtractionAttempt]

        init(
            id: UUID,
            roleRawValue: String,
            text: String,
            createdAt: Date,
            rawLLMResponse: String?,
            extractionStatusRawValue: String,
            extractionVersion: Int
        ) {
            self.id = id
            self.roleRawValue = roleRawValue
            self.text = text
            self.createdAt = createdAt
            self.rawLLMResponse = rawLLMResponse
            self.extractionStatusRawValue = extractionStatusRawValue
            self.extractionError = nil
            self.extractionErrorCodeRawValue = nil
            self.extractionVersion = extractionVersion
            self.events = []
            self.rules = []
            self.notes = []
            self.extractionAttempts = []
        }
    }

    @Model
    final class ExtractionAttempt {
        @Attribute(.unique) var id: UUID
        var statusRawValue: String
        var schemaVersion: Int
        var promptVersion: String
        var modelName: String?
        var requestJSON: String?
        var rawResponseText: String?
        var normalizedJSONText: String
        var errorCodeRawValue: String?
        var errorMessage: String?
        var startedAt: Date
        var completedAt: Date?
        var createdEventIDs: [UUID]
        var createdRuleIDs: [UUID]
        var createdNoteIDs: [UUID]
        var createdThingIDs: [UUID]
        var sourceMessage: ChatMessage?

        init(
            id: UUID,
            statusRawValue: String,
            schemaVersion: Int,
            promptVersion: String,
            normalizedJSONText: String,
            startedAt: Date,
            completedAt: Date?,
            createdEventIDs: [UUID],
            createdRuleIDs: [UUID],
            createdNoteIDs: [UUID],
            createdThingIDs: [UUID],
            sourceMessage: ChatMessage?
        ) {
            self.id = id
            self.statusRawValue = statusRawValue
            self.schemaVersion = schemaVersion
            self.promptVersion = promptVersion
            self.modelName = nil
            self.requestJSON = nil
            self.rawResponseText = nil
            self.normalizedJSONText = normalizedJSONText
            self.errorCodeRawValue = nil
            self.errorMessage = nil
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.createdEventIDs = createdEventIDs
            self.createdRuleIDs = createdRuleIDs
            self.createdNoteIDs = createdNoteIDs
            self.createdThingIDs = createdThingIDs
            self.sourceMessage = sourceMessage
        }
    }

    @Model
    final class EntityLink {
        @Attribute(.unique) var id: UUID
        var sourceTypeRawValue: String
        var sourceID: UUID
        var targetTypeRawValue: String
        var targetID: UUID
        var relationRawValue: String
        var createdAt: Date
        var confidence: Double
        var createdByRawValue: String
        var sourceMessageID: UUID?

        init(
            id: UUID,
            sourceTypeRawValue: String,
            sourceID: UUID,
            targetTypeRawValue: String,
            targetID: UUID,
            relationRawValue: String,
            createdAt: Date,
            confidence: Double,
            createdByRawValue: String,
            sourceMessageID: UUID?
        ) {
            self.id = id
            self.sourceTypeRawValue = sourceTypeRawValue
            self.sourceID = sourceID
            self.targetTypeRawValue = targetTypeRawValue
            self.targetID = targetID
            self.relationRawValue = relationRawValue
            self.createdAt = createdAt
            self.confidence = confidence
            self.createdByRawValue = createdByRawValue
            self.sourceMessageID = sourceMessageID
        }
    }

    @Model
    final class Thing {
        @Attribute(.unique) var id: UUID
        var name: String
        var normalizedKey: String
        var details: String
        var aliases: [String]
        var categoryRawValue: String?
        var createdAt: Date
        var updatedAt: Date
        var sourceMessageIDs: [UUID] = []
        var sourceExtractionAttemptIDs: [UUID] = []
        var eventCount: Int
        var lastEventAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LedgerEvent.thing)
        var events: [LedgerEvent]

        @Relationship(deleteRule: .nullify, inverse: \LedgerRule.thing)
        var rules: [LedgerRule]

        @Relationship(deleteRule: .nullify, inverse: \LedgerNote.linkedThings)
        var notes: [LedgerNote]

        init(
            id: UUID,
            name: String,
            normalizedKey: String,
            details: String,
            createdAt: Date,
            updatedAt: Date,
            sourceMessageIDs: [UUID],
            sourceExtractionAttemptIDs: [UUID],
            eventCount: Int,
            lastEventAt: Date?
        ) {
            self.id = id
            self.name = name
            self.normalizedKey = normalizedKey
            self.details = details
            self.aliases = []
            self.categoryRawValue = nil
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.sourceMessageIDs = sourceMessageIDs
            self.sourceExtractionAttemptIDs = sourceExtractionAttemptIDs
            self.eventCount = eventCount
            self.lastEventAt = lastEventAt
            self.events = []
            self.rules = []
            self.notes = []
        }
    }

    @Model
    final class LedgerEvent {
        @Attribute(.unique) var id: UUID
        var title: String
        var occurredAt: Date
        var rawText: String
        var createdAt: Date
        var updatedAt: Date
        var note: String?
        var sourceClientID: String?
        var sourceExtractionRunID: UUID?
        var eventTypeRawValue: String?
        var metadataJSONText: String = "[]"
        var metadataKeyRawValues: [String] = []
        var thing: Thing?
        var sourceMessage: ChatMessage?

        init(
            id: UUID,
            title: String,
            occurredAt: Date,
            rawText: String,
            createdAt: Date,
            updatedAt: Date,
            sourceClientID: String?,
            sourceExtractionRunID: UUID?,
            thing: Thing?,
            sourceMessage: ChatMessage?
        ) {
            self.id = id
            self.title = title
            self.occurredAt = occurredAt
            self.rawText = rawText
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.note = nil
            self.sourceClientID = sourceClientID
            self.sourceExtractionRunID = sourceExtractionRunID
            self.eventTypeRawValue = nil
            self.thing = thing
            self.sourceMessage = sourceMessage
        }
    }

    @Model
    final class LedgerRule {
        @Attribute(.unique) var id: UUID
        var title: String
        var reason: String?
        var rawText: String
        var startsAt: Date
        var expiresAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var isActive: Bool
        var manuallyDeactivatedAt: Date?
        var sourceClientID: String?
        var sourceExtractionRunID: UUID?
        var ruleTypeRawValue: String?
        var continuityBehaviorRawValue: String?
        var thing: Thing?
        var sourceMessage: ChatMessage?

        init(
            id: UUID,
            title: String,
            reason: String?,
            rawText: String,
            startsAt: Date,
            createdAt: Date,
            updatedAt: Date,
            sourceClientID: String?,
            sourceExtractionRunID: UUID?,
            thing: Thing?,
            sourceMessage: ChatMessage?
        ) {
            self.id = id
            self.title = title
            self.reason = reason
            self.rawText = rawText
            self.startsAt = startsAt
            self.expiresAt = nil
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isActive = true
            self.manuallyDeactivatedAt = nil
            self.sourceClientID = sourceClientID
            self.sourceExtractionRunID = sourceExtractionRunID
            self.ruleTypeRawValue = nil
            self.continuityBehaviorRawValue = nil
            self.thing = thing
            self.sourceMessage = sourceMessage
        }
    }

    @Model
    final class LedgerNote {
        @Attribute(.unique) var id: UUID
        var text: String
        var createdAt: Date
        var updatedAt: Date
        var sourceClientID: String?
        var sourceExtractionRunID: UUID?
        var sourceMessage: ChatMessage?

        @Relationship(deleteRule: .nullify)
        var linkedThings: [Thing]

        init(
            id: UUID,
            text: String,
            createdAt: Date,
            updatedAt: Date,
            sourceClientID: String?,
            sourceExtractionRunID: UUID?,
            sourceMessage: ChatMessage?,
            linkedThings: [Thing]
        ) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.sourceClientID = sourceClientID
            self.sourceExtractionRunID = sourceExtractionRunID
            self.sourceMessage = sourceMessage
            self.linkedThings = linkedThings
        }
    }
}
