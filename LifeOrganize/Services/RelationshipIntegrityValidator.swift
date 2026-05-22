import Foundation
import SwiftData

@MainActor
struct RelationshipIntegrityValidator {
    let modelContext: ModelContext

    func validate(now: Date = Date()) throws -> RelationshipIntegrityResult {
        let snapshot = try RelationshipIntegrityStoreSnapshot(modelContext: modelContext)
        var failures: [RelationshipIntegrityFailure] = []
        checkDuplicateIDs(snapshot, failures: &failures)
        checkEntityLinks(snapshot, failures: &failures)
        checkModelReferences(snapshot, now: now, failures: &failures)
        checkExtractionAttempts(snapshot, failures: &failures)
        return RelationshipIntegrityResult(failures: failures)
    }

    private func checkDuplicateIDs(_ snapshot: RelationshipIntegrityStoreSnapshot, failures: inout [RelationshipIntegrityFailure]) {
        checkDuplicateIDs(snapshot.messages.map(\.id), "ChatMessage", failures: &failures)
        checkDuplicateIDs(snapshot.things.map(\.id), "Thing", failures: &failures)
        checkDuplicateIDs(snapshot.events.map(\.id), "LedgerEvent", failures: &failures)
        checkDuplicateIDs(snapshot.rules.map(\.id), "LedgerRule", failures: &failures)
        checkDuplicateIDs(snapshot.notes.map(\.id), "LedgerNote", failures: &failures)
        checkDuplicateIDs(snapshot.extractionAttempts.map(\.id), "ExtractionAttempt", failures: &failures)
        checkDuplicateIDs(snapshot.reviewItems.map(\.id), "LedgerReviewItem", failures: &failures)
        checkDuplicateIDs(snapshot.entityLinks.map(\.id), "EntityLink", failures: &failures)
    }

    private func checkDuplicateIDs(_ ids: [UUID], _ recordType: String, failures: inout [RelationshipIntegrityFailure]) {
        for id in Dictionary(grouping: ids, by: { $0 }).filter({ $0.value.count > 1 }).map(\.key) {
            failures.append(.error("duplicate_id", recordType, id, "id", "\(recordType) has duplicate id."))
        }
    }

    private func checkEntityLinks(_ snapshot: RelationshipIntegrityStoreSnapshot, failures: inout [RelationshipIntegrityFailure]) {
        var semanticKeys = Set<String>()
        for link in snapshot.entityLinks {
            let sourceType = EntityLinkType(rawValue: link.sourceTypeRawValue)
            let targetType = EntityLinkType(rawValue: link.targetTypeRawValue)
            let relation = EntityLinkRelation(rawValue: link.relationRawValue)
            if sourceType == nil {
                failures.append(.error("invalid_raw_type", "EntityLink", link.id, "sourceTypeRawValue", "Invalid source type \(link.sourceTypeRawValue)."))
            }
            if targetType == nil {
                failures.append(.error("invalid_raw_type", "EntityLink", link.id, "targetTypeRawValue", "Invalid target type \(link.targetTypeRawValue)."))
            }
            if relation == nil {
                failures.append(.error("invalid_raw_relation", "EntityLink", link.id, "relationRawValue", "Invalid relation \(link.relationRawValue)."))
            }
            if EntityLinkCreator(rawValue: link.createdByRawValue) == nil {
                failures.append(.error("invalid_raw_creator", "EntityLink", link.id, "createdByRawValue", "Invalid creator \(link.createdByRawValue)."))
            }
            if let sourceMessageID = link.sourceMessageID, snapshot.messagesByID[sourceMessageID] == nil {
                failures.append(.error("entity_link_missing_source_message", "EntityLink", link.id, "sourceMessageID", "Missing source message \(sourceMessageID.uuidString)."))
            }
            if !link.confidence.isFinite || !(0...1).contains(link.confidence) {
                failures.append(.error("entity_link_bad_confidence", "EntityLink", link.id, "confidence", "Confidence is outside 0...1."))
            }
            guard let sourceType, let targetType, let relation else { continue }
            if !snapshot.exists(type: sourceType, id: link.sourceID) {
                failures.append(.error("entity_link_missing_source", "EntityLink", link.id, "sourceID", "Missing \(sourceType.rawValue) source \(link.sourceID.uuidString)."))
            }
            if !snapshot.exists(type: targetType, id: link.targetID) {
                failures.append(.error("entity_link_missing_target", "EntityLink", link.id, "targetID", "Missing \(targetType.rawValue) target \(link.targetID.uuidString)."))
            }
            if !isValidShape(sourceType: sourceType, targetType: targetType, relation: relation, sourceID: link.sourceID, targetID: link.targetID, sourceMessageID: link.sourceMessageID) {
                failures.append(.error("entity_link_invalid_shape", "EntityLink", link.id, "relationRawValue", "Invalid \(sourceType.rawValue) \(relation.rawValue) \(targetType.rawValue) shape."))
            }
            let key = [sourceType.rawValue, link.sourceID.uuidString, targetType.rawValue, link.targetID.uuidString, relation.rawValue].joined(separator: "|")
            if !semanticKeys.insert(key).inserted {
                failures.append(.error("entity_link_duplicate", "EntityLink", link.id, "id", "Duplicate semantic entity link."))
            }
        }
    }

    private func isValidShape(sourceType: EntityLinkType, targetType: EntityLinkType, relation: EntityLinkRelation, sourceID: UUID, targetID: UUID, sourceMessageID: UUID?) -> Bool {
        if sourceType == targetType, sourceID == targetID { return false }
        switch relation {
        case .mentionsThing:
            return sourceType == .chatMessage && targetType == .thing && sourceMessageID == sourceID
        case .extractedFrom:
            return sourceType == .chatMessage && [.event, .rule, .note].contains(targetType) && sourceMessageID == sourceID
        case .primaryThing:
            return [.event, .rule].contains(sourceType) && targetType == .thing
        case .aboutThing:
            return sourceType == .note && targetType == .thing
        case .sameMessage:
            return sourceType != .chatMessage && targetType != .chatMessage && sourceMessageID != nil
        }
    }

    private func checkModelReferences(_ snapshot: RelationshipIntegrityStoreSnapshot, now: Date, failures: inout [RelationshipIntegrityFailure]) {
        let statusService = RuleStatusService()
        for event in snapshot.events {
            checkThing(event.thing, owner: "LedgerEvent", ownerID: event.id, field: "thing", snapshot: snapshot, failures: &failures)
            checkSourceMessage(event.sourceMessage, owner: "LedgerEvent", ownerID: event.id, field: "sourceMessage", snapshot: snapshot, failures: &failures)
        }
        for rule in snapshot.rules {
            checkThing(rule.thing, owner: "LedgerRule", ownerID: rule.id, field: "thing", snapshot: snapshot, failures: &failures)
            checkSourceMessage(rule.sourceMessage, owner: "LedgerRule", ownerID: rule.id, field: "sourceMessage", snapshot: snapshot, failures: &failures)
            if rule.isActive != statusService.isActive(rule, at: now) {
                failures.append(.error("rule_active_state_mismatch", "LedgerRule", rule.id, "isActive", "Rule active state is stale for validation date."))
            }
        }
        for note in snapshot.notes {
            for thing in note.linkedThings {
                checkThing(thing, owner: "LedgerNote", ownerID: note.id, field: "linkedThings", snapshot: snapshot, failures: &failures)
            }
            checkSourceMessage(note.sourceMessage, owner: "LedgerNote", ownerID: note.id, field: "sourceMessage", snapshot: snapshot, failures: &failures)
        }
        for thing in snapshot.things {
            for messageID in thing.sourceMessageIDs where snapshot.messagesByID[messageID] == nil {
                failures.append(.error("model_missing_source_message", "Thing", thing.id, "sourceMessageIDs", "Missing source message \(messageID.uuidString)."))
            }
            let actualEvents = snapshot.eventsByThingID[thing.id] ?? []
            if thing.eventCount != actualEvents.count {
                failures.append(.error("thing_event_count_mismatch", "Thing", thing.id, "eventCount", "Expected \(actualEvents.count), found \(thing.eventCount)."))
            }
            if thing.lastEventAt != actualEvents.map(\.occurredAt).max() {
                failures.append(.error("thing_last_event_mismatch", "Thing", thing.id, "lastEventAt", "Thing lastEventAt does not match linked events."))
            }
        }
    }

    private func checkExtractionAttempts(_ snapshot: RelationshipIntegrityStoreSnapshot, failures: inout [RelationshipIntegrityFailure]) {
        for attempt in snapshot.extractionAttempts {
            checkSourceMessage(attempt.sourceMessage, owner: "ExtractionAttempt", ownerID: attempt.id, field: "sourceMessage", snapshot: snapshot, failures: &failures)
            checkCreatedIDs(attempt.createdThingIDs, in: snapshot.thingsByID, recordType: "ExtractionAttempt", recordID: attempt.id, field: "createdThingIDs", failures: &failures)
            checkCreatedIDs(attempt.createdEventIDs, in: snapshot.eventsByID, recordType: "ExtractionAttempt", recordID: attempt.id, field: "createdEventIDs", failures: &failures)
            checkCreatedIDs(attempt.createdRuleIDs, in: snapshot.rulesByID, recordType: "ExtractionAttempt", recordID: attempt.id, field: "createdRuleIDs", failures: &failures)
            checkCreatedIDs(attempt.createdNoteIDs, in: snapshot.notesByID, recordType: "ExtractionAttempt", recordID: attempt.id, field: "createdNoteIDs", failures: &failures)
        }
    }

    private func checkThing(_ thing: Thing?, owner: String, ownerID: UUID, field: String, snapshot: RelationshipIntegrityStoreSnapshot, failures: inout [RelationshipIntegrityFailure]) {
        guard let thing, snapshot.thingsByID[thing.id] == nil else { return }
        failures.append(.error("model_missing_thing", owner, ownerID, field, "Missing related thing \(thing.id.uuidString)."))
    }

    private func checkSourceMessage(_ message: ChatMessage?, owner: String, ownerID: UUID, field: String, snapshot: RelationshipIntegrityStoreSnapshot, failures: inout [RelationshipIntegrityFailure]) {
        guard let message, snapshot.messagesByID[message.id] == nil else { return }
        failures.append(.error("model_missing_source_message", owner, ownerID, field, "Missing source message \(message.id.uuidString)."))
    }

    private func checkCreatedIDs<T>(_ ids: [UUID], in records: [UUID: T], recordType: String, recordID: UUID, field: String, failures: inout [RelationshipIntegrityFailure]) {
        for id in ids where records[id] == nil {
            failures.append(.error("extraction_attempt_missing_created_record", recordType, recordID, field, "Missing created record \(id.uuidString)."))
        }
    }
}

struct RelationshipIntegrityResult: Equatable {
    let failures: [RelationshipIntegrityFailure]

    var hasErrors: Bool {
        failures.contains { $0.severity == .error }
    }
}

struct RelationshipIntegrityFailure: CustomStringConvertible, Equatable {
    enum Severity: String {
        case error
        case warning
    }

    let severity: Severity
    let code: String
    let recordType: String
    let recordID: UUID?
    let field: String
    let message: String

    var description: String {
        let idText = recordID.map { " \($0.uuidString)" } ?? ""
        return "[\(severity.rawValue)] \(code) \(recordType)\(idText) \(field): \(message)"
    }

    static func error(_ code: String, _ recordType: String, _ recordID: UUID?, _ field: String, _ message: String) -> RelationshipIntegrityFailure {
        RelationshipIntegrityFailure(severity: .error, code: code, recordType: recordType, recordID: recordID, field: field, message: message)
    }
}

@MainActor
struct RelationshipIntegrityStoreSnapshot {
    let messages: [ChatMessage]
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let extractionAttempts: [ExtractionAttempt]
    let reviewItems: [LedgerReviewItem]
    let entityLinks: [EntityLink]
    let messagesByID: [UUID: ChatMessage]
    let thingsByID: [UUID: Thing]
    let eventsByID: [UUID: LedgerEvent]
    let rulesByID: [UUID: LedgerRule]
    let notesByID: [UUID: LedgerNote]
    let eventsByThingID: [UUID: [LedgerEvent]]

    init(modelContext: ModelContext) throws {
        messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        things = try modelContext.fetch(FetchDescriptor<Thing>())
        events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())
        extractionAttempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        reviewItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        entityLinks = try modelContext.fetch(FetchDescriptor<EntityLink>())
        messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        thingsByID = Dictionary(things.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rulesByID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        notesByID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        eventsByThingID = Dictionary(grouping: events.compactMap { event in event.thing.map { ($0.id, event) } }, by: \.0)
            .mapValues { $0.map(\.1) }
    }

    func exists(type: EntityLinkType, id: UUID) -> Bool {
        switch type {
        case .chatMessage: messagesByID[id] != nil
        case .event: eventsByID[id] != nil
        case .note: notesByID[id] != nil
        case .rule: rulesByID[id] != nil
        case .thing: thingsByID[id] != nil
        }
    }
}
