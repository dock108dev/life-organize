import Foundation
import SwiftData

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

    var status: ExtractionAttemptStatus {
        get { ExtractionAttemptStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var errorCode: ExtractionErrorCode? {
        get {
            guard let errorCodeRawValue else { return nil }
            return ExtractionErrorCode(rawValue: errorCodeRawValue)
        }
        set { errorCodeRawValue = newValue?.rawValue }
    }

    var sourceMessageID: UUID? {
        sourceMessage?.id
    }

    init(
        id: UUID = UUID(),
        status: ExtractionAttemptStatus = .pending,
        schemaVersion: Int = ExtractionContract.schemaVersion,
        promptVersion: String = ExtractionContract.promptVersion,
        modelName: String? = nil,
        requestJSON: String? = nil,
        rawResponseText: String? = nil,
        normalizedJSONText: String = ExtractionEnvelope.emptyJSON(),
        errorCode: ExtractionErrorCode? = nil,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        createdEventIDs: [UUID] = [],
        createdRuleIDs: [UUID] = [],
        createdNoteIDs: [UUID] = [],
        createdThingIDs: [UUID] = [],
        sourceMessage: ChatMessage? = nil
    ) {
        self.id = id
        self.statusRawValue = status.rawValue
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.modelName = modelName
        self.requestJSON = requestJSON
        self.rawResponseText = rawResponseText
        self.normalizedJSONText = normalizedJSONText
        self.errorCodeRawValue = errorCode?.rawValue
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.createdEventIDs = createdEventIDs
        self.createdRuleIDs = createdRuleIDs
        self.createdNoteIDs = createdNoteIDs
        self.createdThingIDs = createdThingIDs
        self.sourceMessage = sourceMessage
    }
}

enum ExtractionAttemptStatus: String, Codable, CaseIterable {
    case pending
    case succeeded
    case failed
    case partiallySucceeded = "partially_succeeded"
    case superseded
}
