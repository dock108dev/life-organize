import Foundation

struct LedgerExportEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: String
    let exportedFrom: ExportedFrom
    let locale: ExportLocale
    let records: ExportRecords
}

struct ExportedFrom: Codable, Equatable {
    let appName: String
    let appBuild: String
    let platform: String
}

struct ExportLocale: Codable, Equatable {
    let calendar: String
    let timeZone: String
}

struct ExportRecords: Codable, Equatable {
    let chatMessages: [ChatMessageExport]
    let extractionRuns: [ExtractionRunExport]
    let things: [ThingExport]
    let events: [EventExport]
    let rules: [RuleExport]
    let notes: [NoteExport]
    let ledgerReviewItems: [LedgerReviewItemExport]
    let entityLinks: [EntityLinkExport]
}

struct ExportSource: Codable, Equatable {
    let kind: String
    let chatMessageId: String?
    let extractionRunId: String?
    let sourceClientId: String?

    init(kind: String, chatMessageId: String? = nil, extractionRunId: String? = nil, sourceClientId: String? = nil) {
        self.kind = kind
        self.chatMessageId = chatMessageId
        self.extractionRunId = extractionRunId
        self.sourceClientId = sourceClientId
    }
}

struct ChatMessageExport: Codable, Equatable {
    let id: String
    let role: String
    let text: String
    let createdAt: String
    let linkedEntityIds: [String]
    let extractionRunIds: [String]
    let latestExtractionRunId: String?
    let successfulExtractionRunIds: [String]
    let extractionState: ChatMessageExtractionStateExport?
}

struct ChatMessageExtractionStateExport: Codable, Equatable {
    let status: String
    let errorCode: String?
    let errorMessage: String?
    let extractionVersion: Int
    let attemptCount: Int
    let lastAttemptAt: String?
    let nextRetryAt: String?
    let latestAttemptStatus: String?
    let latestAttemptErrorCode: String?
    let recoveryAction: String?
}

struct ExtractionRunExport: Codable, Equatable {
    let id: String
    let chatMessageId: String?
    let provider: String
    let model: String?
    let purpose: String
    let extractionSchemaVersion: Int
    let promptVersion: String
    let requestedAt: String
    let completedAt: String?
    let status: String
    let input: ExtractionRunInputExport?
    let requestJSON: String?
    let rawResponseText: String?
    let normalizedJSONText: String
    let parsedResponse: JSONValue?
    let createdEntities: ExtractionRunCreatedEntitiesExport
    let createdEntityIds: [String]
    let error: ExtractionRunErrorExport?
}

struct ExtractionRunCreatedEntitiesExport: Codable, Equatable {
    let things: [String]
    let events: [String]
    let rules: [String]
    let notes: [String]
}

struct ExtractionRunInputExport: Codable, Equatable {
    let userText: String
    let referenceNow: String
    let timeZone: String
}

struct ExtractionRunErrorExport: Codable, Equatable {
    let kind: String
    let message: String
}

struct ThingExport: Codable, Equatable {
    let id: String
    let name: String
    let aliases: [String]
    let category: String?
    let createdAt: String
    let updatedAt: String
    let lastEventAt: String?
    let eventCount: Int
    let source: ExportSource
}

struct EventExport: Codable, Equatable {
    let id: String
    let thingId: String?
    let title: String
    let eventType: String
    let rawText: String
    let occurredAt: String
    let createdAt: String
    let updatedAt: String
    let note: String?
    let metadata: [EventMetadataExport]
    let source: ExportSource
}

struct EventMetadataExport: Codable, Equatable {
    let key: String
    let valueKind: String
    let stringValue: String?
    let numberValue: Double?
    let dateValue: String?
    let boolValue: Bool?
    let unit: String?
    let sourceText: String?
}

struct RuleExport: Codable, Equatable {
    let id: String
    let thingId: String?
    let title: String
    let ruleType: String
    let continuityBehavior: String
    let reason: String?
    let startsAt: String
    let expiresAt: String?
    let createdAt: String
    let updatedAt: String
    let isActive: Bool
    let lifecycleState: String
    let manuallyDeactivatedAt: String?
    let rawText: String
    let source: ExportSource
}

struct NoteExport: Codable, Equatable {
    let id: String
    let text: String
    let createdAt: String
    let updatedAt: String
    let linkedThingIds: [String]
    let source: ExportSource
}

struct EntityLinkExport: Codable, Equatable {
    let id: String
    let fromEntityType: String
    let fromEntityId: String
    let toEntityType: String
    let toEntityId: String
    let relationship: String
    let createdAt: String
    let source: ExportSource
}

struct LedgerReviewItemExport: Codable, Equatable {
    let id: String
    let kind: String
    let state: String
    let title: String
    let detail: String
    let actionTitle: String?
    let targetType: String
    let targetId: String?
    let dedupeKey: String
    let confidence: Double
    let createdAt: String
    let updatedAt: String
    let presentedAt: String?
    let resolvedAt: String?
    let snoozedUntil: String?
    let expiresAt: String?
    let failureReason: String?
    let evidence: [LedgerReviewItemEvidenceExport]
}

struct LedgerReviewItemEvidenceExport: Codable, Equatable {
    let sourceType: String
    let sourceId: String
    let summary: String
    let detail: String?
}
