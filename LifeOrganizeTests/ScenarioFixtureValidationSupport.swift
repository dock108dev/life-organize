import Foundation
@testable import LifeOrganize

extension ScenarioFixtureValidator {
    func validateSource(_ source: ExportSource, ids: FixtureRecordIDs, field: String) throws {
        try validateEnum(source.kind, allowed: ["manual", "extracted", "system"], field: "\(field).kind")
        try validateOptionalReference(source.chatMessageId, in: ids.chatMessages, field: "\(field).chatMessageId")
        try validateOptionalReference(source.extractionRunId, in: ids.extractionRuns, field: "\(field).extractionRunId")
        if source.kind == "manual" {
            try require(
                source.chatMessageId == nil && source.extractionRunId == nil,
                "\(field) manual source must not include chat or extraction references."
            )
        }
        if source.kind == "extracted" {
            try require(
                source.chatMessageId != nil || source.extractionRunId != nil || source.sourceClientId != nil,
                "\(field) extracted source must include provenance."
            )
        }
        if let extractionRunId = source.extractionRunId,
           let chatMessageId = source.chatMessageId,
           let runMessageId = ids.extractionRunChatMessageIDs[extractionRunId] {
            try require(
                runMessageId == chatMessageId,
                "\(field) extractionRunId must belong to the same chatMessageId."
            )
        }
    }

    func validateSourceBacklinks(for message: ChatMessageExport, records: ExportRecords) throws {
        let sourceLinkedRecordIDs =
            records.things.filter { $0.source.chatMessageId == message.id }.map(\.id)
            + records.events.filter { $0.source.chatMessageId == message.id }.map(\.id)
            + records.rules.filter { $0.source.chatMessageId == message.id }.map(\.id)
            + records.notes.filter { $0.source.chatMessageId == message.id }.map(\.id)
        for recordID in sourceLinkedRecordIDs {
            try require(
                message.linkedEntityIds.contains(recordID),
                "Chat message \(message.id) linkedEntityIds must include source-linked record \(recordID)."
            )
        }
    }

    func validateOptionalReference(_ id: String?, in ids: Set<String>, field: String) throws {
        guard let id else { return }
        try validateReference(id, in: ids, field: field)
    }

    func validateReference(_ id: String, in ids: Set<String>, field: String) throws {
        try validateUUID(id, field: field)
        if !ids.contains(id) {
            throw ScenarioFixtureError.invalidFixture("\(field) references missing record \(id).")
        }
    }

    func validateUUID(_ text: String, field: String) throws {
        if UUID(uuidString: text) == nil {
            throw ScenarioFixtureError.invalidFixture("\(field) must be a UUID string: \(text).")
        }
    }

    func validateEnum(_ value: String, allowed: [String], field: String) throws {
        if !allowed.contains(value) {
            throw ScenarioFixtureError.invalidFixture("\(field) has invalid value \(value).")
        }
    }

    func parseTimestamp(_ text: String, field: String) throws -> Date {
        if let date = Self.isoTimestampFormatter.date(from: text) {
            return date
        }
        if let date = Self.fractionalIsoTimestampFormatter.date(from: text) {
            return date
        }
        throw ScenarioFixtureError.invalidFixture("\(field) has invalid timestamp \(text).")
    }

    func parseDateOnly(_ text: String, field: String) throws -> Date {
        if let date = Self.dateOnlyFormatter.date(from: text), Self.dateOnlyFormatter.string(from: date) == text {
            return date
        }
        throw ScenarioFixtureError.invalidFixture("\(field) has invalid date \(text).")
    }

    func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw ScenarioFixtureError.invalidFixture(message)
        }
    }

    private static let isoTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalIsoTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}

struct FixtureRecordIDs {
    let chatMessages: Set<String>
    let extractionRuns: Set<String>
    let things: Set<String>
    let events: Set<String>
    let rules: Set<String>
    let notes: Set<String>
    let ledgerReviewItems: Set<String>
    let entityLinks: Set<String>
    let extractionRunChatMessageIDs: [String: String]
    let duplicateErrors: [String]

    var allRecordIDs: Set<String> {
        chatMessages
            .union(extractionRuns)
            .union(things)
            .union(events)
            .union(rules)
            .union(notes)
            .union(ledgerReviewItems)
            .union(entityLinks)
    }

    init(records: ExportRecords) {
        let chatMessageIDs = records.chatMessages.map(\.id)
        let extractionRunIDs = records.extractionRuns.map(\.id)
        let thingIDs = records.things.map(\.id)
        let eventIDs = records.events.map(\.id)
        let ruleIDs = records.rules.map(\.id)
        let noteIDs = records.notes.map(\.id)
        let reviewItemIDs = records.ledgerReviewItems.map(\.id)
        let entityLinkIDs = records.entityLinks.map(\.id)

        self.chatMessages = Set(chatMessageIDs)
        self.extractionRuns = Set(extractionRunIDs)
        self.things = Set(thingIDs)
        self.events = Set(eventIDs)
        self.rules = Set(ruleIDs)
        self.notes = Set(noteIDs)
        self.ledgerReviewItems = Set(reviewItemIDs)
        self.entityLinks = Set(entityLinkIDs)
        self.extractionRunChatMessageIDs = Dictionary(
            uniqueKeysWithValues: records.extractionRuns.compactMap { run in
                guard let chatMessageId = run.chatMessageId else { return nil }
                return (run.id, chatMessageId)
            }
        )
        self.duplicateErrors = [
            Self.duplicateError(chatMessageIDs, label: "chatMessages"),
            Self.duplicateError(extractionRunIDs, label: "extractionRuns"),
            Self.duplicateError(thingIDs, label: "things"),
            Self.duplicateError(eventIDs, label: "events"),
            Self.duplicateError(ruleIDs, label: "rules"),
            Self.duplicateError(noteIDs, label: "notes"),
            Self.duplicateError(reviewItemIDs, label: "ledgerReviewItems"),
            Self.duplicateError(entityLinkIDs, label: "entityLinks"),
        ].compactMap { $0 }
    }

    func validateDuplicates() throws {
        if let duplicateError = duplicateErrors.first {
            throw ScenarioFixtureError.invalidFixture(duplicateError)
        }
    }

    private static func duplicateError(_ ids: [String], label: String) -> String? {
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map(\.key)
            .sorted()
        guard let duplicate = duplicates.first else { return nil }
        return "\(label) contains duplicate id \(duplicate)."
    }
}

extension DecodingError {
    var readableDescription: String {
        switch self {
        case .keyNotFound(let key, let context):
            "Missing required field \(key.stringValue) at \(context.codingPath.readablePath)."
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            "\(context.debugDescription) at \(context.codingPath.readablePath)."
        @unknown default:
            localizedDescription
        }
    }
}

private extension [CodingKey] {
    var readablePath: String {
        guard !isEmpty else { return "<root>" }
        return map(\.stringValue).joined(separator: ".")
    }
}
