import Foundation
import SwiftData

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
    var extractionAttempts: [ExtractionAttempt] = []

    var role: ChatRole {
        get { ChatRole(rawValue: roleRawValue) ?? .system }
        set { roleRawValue = newValue.rawValue }
    }

    var extractionStatus: ExtractionStatus {
        get { ExtractionStatus(rawValue: extractionStatusRawValue) ?? .notRequired }
        set { extractionStatusRawValue = newValue.rawValue }
    }

    var extractionErrorCode: ExtractionErrorCode? {
        get {
            guard let extractionErrorCodeRawValue else { return nil }
            return ExtractionErrorCode(rawValue: extractionErrorCodeRawValue)
        }
        set { extractionErrorCodeRawValue = newValue?.rawValue }
    }

    var linkedEntityIDs: [UUID] {
        events.map(\.id) + rules.map(\.id) + notes.map(\.id)
    }

    var requiresPrimaryFeedAttention: Bool {
        guard role == .user else {
            guard role == .assistant else { return false }
            return text.isPrimaryTimelineAssistantResponse
        }

        switch extractionStatus {
        case .pending, .extracting, .pendingKey, .pendingRetry, .partiallySucceeded, .failed, .failedNeedsReview,
             .needsReview:
            return true
        case .notRequired, .succeeded:
            return false
        }
    }

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        rawLLMResponse: String? = nil,
        extractionStatus: ExtractionStatus = .notRequired,
        extractionError: String? = nil,
        extractionErrorCode: ExtractionErrorCode? = nil,
        extractionVersion: Int = 1,
        extractionAttemptCount: Int = 0,
        lastExtractionAttemptAt: Date? = nil,
        nextExtractionRetryAt: Date? = nil,
        events: [LedgerEvent] = [],
        rules: [LedgerRule] = [],
        notes: [LedgerNote] = [],
        extractionAttempts: [ExtractionAttempt] = []
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.rawLLMResponse = rawLLMResponse
        self.extractionStatusRawValue = extractionStatus.rawValue
        self.extractionError = extractionError
        self.extractionErrorCodeRawValue = extractionErrorCode?.rawValue
        self.extractionVersion = extractionVersion
        self.extractionAttemptCount = extractionAttemptCount
        self.lastExtractionAttemptAt = lastExtractionAttemptAt
        self.nextExtractionRetryAt = nextExtractionRetryAt
        self.events = events
        self.rules = rules
        self.notes = notes
        self.extractionAttempts = extractionAttempts
    }
}

private extension String {
    var isPrimaryTimelineAssistantResponse: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let visiblePrefixes = [
            "Coming Up:",
            "Now:",
            "Active restriction:",
            "Active restrictions:",
            "Last logged:",
            "Last expired:",
            "Recent notes:",
            "Local results:",
            "Web results:",
            "Review:",
            "Blocked.",
            "No active ",
        ]
        if visiblePrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }
        return trimmed.contains(" related items found.")
    }
}

enum ChatRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

enum ExtractionStatus: String, Codable, CaseIterable {
    case notRequired = "not_required"
    case pending
    case pendingKey = "pending_key"
    case pendingRetry = "pending_retry"
    case extracting
    case succeeded
    case partiallySucceeded = "partially_succeeded"
    case failed
    case failedNeedsReview = "failed_needs_review"
    case needsReview = "needs_review"
}

enum ExtractionErrorCode: String, Codable, CaseIterable {
    case missingAPIKey = "missing_api_key"
    case invalidAPIKey = "invalid_api_key"
    case networkUnavailable = "network_unavailable"
    case timeout
    case rateLimited = "rate_limited"
    case serverError = "server_error"
    case invalidJSON = "invalid_json"
    case schemaValidationFailed = "schema_validation_failed"
    case partialValidationFailed = "partial_validation_failed"
    case unknown
}
