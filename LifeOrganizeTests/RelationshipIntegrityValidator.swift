import Foundation
import SwiftData
@testable import LifeOrganize

@MainActor
struct ScenarioRelationshipIntegrityValidator {
    let modelContext: ModelContext

    func validateScenario(name: String, now: Date, calendar: Calendar = .current) throws {
        let result = try validate(now: now, calendar: calendar)
        if result.hasErrors {
            throw RelationshipIntegrityValidationError(scenarioName: name, result: result)
        }
    }

    func validate(now: Date, calendar: Calendar = .current) throws -> RelationshipIntegrityResult {
        var failures = try RelationshipIntegrityValidator(modelContext: modelContext).validate(now: now).failures
        let snapshot = try RelationshipStoreSnapshot(modelContext: modelContext)
        // Scenario checks intentionally stay test-only; runtime QA owns the shared integrity rules.
        checkRelationshipTraversal(snapshot, failures: &failures)
        checkScenarioModelReferences(snapshot, failures: &failures)
        checkReviewItems(snapshot, failures: &failures)
        checkTimelineContinuity(snapshot, now: now, calendar: calendar, failures: &failures)
        return RelationshipIntegrityResult(failures: failures)
    }

    private func checkRelationshipTraversal(
        _ snapshot: RelationshipStoreSnapshot,
        failures: inout [RelationshipIntegrityFailure]
    ) {
        var expectedTraversalTargetsBySource: [RelationshipNode: Set<RelationshipNode>] = [:]
        let traversalRecords = snapshot.traversalRecords
        let traversalService = RelationshipTraversalService()

        for link in snapshot.entityLinks {
            guard let sourceType = EntityLinkType(rawValue: link.sourceTypeRawValue),
                  let targetType = EntityLinkType(rawValue: link.targetTypeRawValue),
                  EntityLinkRelation(rawValue: link.relationRawValue) != nil,
                  snapshot.exists(type: sourceType, id: link.sourceID),
                  snapshot.exists(type: targetType, id: link.targetID) else {
                continue
            }
            let sourceNode = RelationshipNode(type: sourceType, id: link.sourceID)
            let targetNode = RelationshipNode(type: targetType, id: link.targetID)
            expectedTraversalTargetsBySource[sourceNode, default: []].insert(targetNode)
        }

        for (sourceNode, expectedTargets) in expectedTraversalTargetsBySource {
            let traversedTargets = Set(traversalService.relatedRecords(for: sourceNode, in: traversalRecords).map(\.target))
            for targetNode in expectedTargets where !traversedTargets.contains(targetNode) {
                failures.append(.error(
                    "relationship_traversal_drop",
                    sourceNode.type.rawValue,
                    sourceNode.id,
                    "targetID",
                    "Traversal from \(sourceNode.stableKey) did not include \(targetNode.stableKey)."
                ))
            }
        }
    }

    private func checkScenarioModelReferences(
        _ snapshot: RelationshipStoreSnapshot,
        failures: inout [RelationshipIntegrityFailure]
    ) {
        for event in snapshot.events {
            checkThingLink(
                sourceType: .event,
                sourceID: event.id,
                thingID: event.thing?.id,
                relation: .primaryThing,
                code: "event_primary_link_mismatch",
                snapshot: snapshot,
                failures: &failures
            )
        }
        for rule in snapshot.rules {
            checkThingLink(
                sourceType: .rule,
                sourceID: rule.id,
                thingID: rule.thing?.id,
                relation: .primaryThing,
                code: "rule_primary_link_mismatch",
                snapshot: snapshot,
                failures: &failures
            )
        }
        for note in snapshot.notes {
            let graphIDs = Set(snapshot.entityLinks.filter {
                $0.sourceType == .note && $0.sourceID == note.id && $0.targetType == .thing && $0.relation == .aboutThing
            }.map(\.targetID))
            let modelIDs = Set(note.linkedThings.map(\.id))
            if !graphIDs.isSubset(of: modelIDs) {
                failures.append(.error(
                    "note_about_link_mismatch",
                    "LedgerNote",
                    note.id,
                    "linkedThings",
                    "Note aboutThing links include things not linked on the note."
                ))
            }
        }
        for thing in snapshot.things {
            if thing.normalizedKey != ThingNormalizer.normalizeKey(thing.name) {
                failures.append(.error(
                    "thing_normalized_key_mismatch",
                    "Thing",
                    thing.id,
                    "normalizedKey",
                    "Thing normalized key does not match name."
                ))
            }
            if thing.aliases != DerivedFieldMaintenanceService.normalizedAliases(thing.aliases, excludingName: thing.name) {
                failures.append(.error(
                    "thing_aliases_not_normalized",
                    "Thing",
                    thing.id,
                    "aliases",
                    "Thing aliases are not normalized."
                ))
            }
        }
    }

    private func checkThingLink(
        sourceType: EntityLinkType,
        sourceID: UUID,
        thingID: UUID?,
        relation: EntityLinkRelation,
        code: String,
        snapshot: RelationshipStoreSnapshot,
        failures: inout [RelationshipIntegrityFailure]
    ) {
        let links = snapshot.entityLinks.filter {
            $0.sourceType == sourceType && $0.sourceID == sourceID && $0.targetType == .thing && $0.relation == relation
        }
        guard !links.isEmpty else { return }
        let linkIDs = Set(links.map(\.targetID))
        if thingID.map({ linkIDs != [$0] }) ?? true {
            failures.append(.error(
                code,
                sourceType.rawValue,
                sourceID,
                "thing",
                "Model thing does not match \(relation.rawValue) links."
            ))
        }
    }

    private func checkReviewItems(
        _ snapshot: RelationshipStoreSnapshot,
        failures: inout [RelationshipIntegrityFailure]
    ) {
        for item in snapshot.reviewItems {
            if LedgerReviewItemKind(rawValue: item.kindRawValue) == nil {
                failures.append(.error(
                    "invalid_review_kind",
                    "LedgerReviewItem",
                    item.id,
                    "kindRawValue",
                    "Invalid review kind \(item.kindRawValue)."
                ))
            }
            if LedgerReviewItemState(rawValue: item.stateRawValue) == nil {
                failures.append(.error(
                    "invalid_review_state",
                    "LedgerReviewItem",
                    item.id,
                    "stateRawValue",
                    "Invalid review state \(item.stateRawValue)."
                ))
            }
            guard let targetType = LedgerReviewItemTargetType(rawValue: item.targetTypeRawValue) else {
                failures.append(.error(
                    "invalid_review_target_type",
                    "LedgerReviewItem",
                    item.id,
                    "targetTypeRawValue",
                    "Invalid review target type \(item.targetTypeRawValue)."
                ))
                continue
            }
            if let targetID = item.targetID, !snapshot.exists(reviewTargetType: targetType, id: targetID) {
                failures.append(.error(
                    "review_missing_reference",
                    "LedgerReviewItem",
                    item.id,
                    "targetID",
                    "Missing review target \(targetID.uuidString)."
                ))
            }
            for evidence in item.evidence where !snapshot.exists(reviewTargetType: evidence.sourceType, id: evidence.sourceID) {
                failures.append(.error(
                    "review_missing_reference",
                    "LedgerReviewItem",
                    item.id,
                    "evidence",
                    "Missing review evidence \(evidence.sourceID.uuidString)."
                ))
            }
            if !item.confidence.isFinite || !(0...1).contains(item.confidence) {
                failures.append(.error(
                    "review_bad_confidence",
                    "LedgerReviewItem",
                    item.id,
                    "confidence",
                    "Review confidence is outside 0...1."
                ))
            }
        }
    }

    private func checkTimelineContinuity(
        _ snapshot: RelationshipStoreSnapshot,
        now: Date,
        calendar: Calendar,
        failures: inout [RelationshipIntegrityFailure]
    ) {
        let searchRecords = SearchService().records(
            things: snapshot.things,
            events: snapshot.events,
            rules: snapshot.rules,
            notes: snapshot.notes,
            messages: snapshot.messages
        )
        for record in searchRecords where !snapshot.hasAvailableRecord(for: record.navigationTarget) {
            failures.append(.error(
                "search_missing_navigation_target",
                "LocalSearchRecord",
                record.id,
                "navigationTarget",
                "Search record points to a missing target."
            ))
        }
        let rows = TimelineSliceProjection(calendar: calendar, now: now).rows(
            messages: snapshot.messages,
            things: snapshot.things,
            events: snapshot.events,
            reminders: snapshot.rules,
            notes: snapshot.notes,
            entityLinks: snapshot.entityLinks
        )
        for row in rows where !snapshot.hasAvailableRecord(for: row.navigationTarget) {
            failures.append(.error(
                "timeline_missing_navigation_target",
                row.sourceKind.rawValue,
                row.sourceID,
                "navigationTarget",
                "Timeline row points to a missing target."
            ))
        }
        for thing in snapshot.things {
            let descriptor = TimelineSliceReplayDescriptor.linkedThing(thing)
            guard case .id(let thingID)? = descriptor.query.linkedThingFilter, snapshot.thingsByID[thingID] != nil else {
                failures.append(.error(
                    "timeline_missing_descriptor_target",
                    "Thing",
                    thing.id,
                    "linkedThingFilter",
                    "Timeline descriptor points to a missing thing."
                ))
                continue
            }
        }
    }
}

struct RelationshipIntegrityValidationError: LocalizedError, CustomStringConvertible {
    let scenarioName: String
    let result: RelationshipIntegrityResult

    var errorDescription: String? { description }

    var description: String {
        let rendered = result.failures.map(\.description).joined(separator: "\n")
        return "Relationship integrity failed for \(scenarioName):\n\(rendered)"
    }
}

@MainActor
private struct RelationshipStoreSnapshot {
    let messages: [ChatMessage]
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let reviewItems: [LedgerReviewItem]
    let entityLinks: [EntityLink]

    let messagesByID: [UUID: ChatMessage]
    let thingsByID: [UUID: Thing]
    let eventsByID: [UUID: LedgerEvent]
    let rulesByID: [UUID: LedgerRule]
    let notesByID: [UUID: LedgerNote]

    init(modelContext: ModelContext) throws {
        messages = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        things = try modelContext.fetch(FetchDescriptor<Thing>())
        events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
        rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
        notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())
        reviewItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        entityLinks = try modelContext.fetch(FetchDescriptor<EntityLink>())
        messagesByID = Self.firstByID(messages)
        thingsByID = Self.firstByID(things)
        eventsByID = Self.firstByID(events)
        rulesByID = Self.firstByID(rules)
        notesByID = Self.firstByID(notes)
    }

    var traversalRecords: RelationshipTraversalRecords {
        RelationshipTraversalRecords(
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            entityLinks: entityLinks
        )
    }

    func exists(type: EntityLinkType, id: UUID) -> Bool {
        switch type {
        case .chatMessage:
            return messagesByID[id] != nil
        case .event:
            return eventsByID[id] != nil
        case .note:
            return notesByID[id] != nil
        case .rule:
            return rulesByID[id] != nil
        case .thing:
            return thingsByID[id] != nil
        }
    }

    func exists(reviewTargetType: LedgerReviewItemTargetType, id: UUID) -> Bool {
        switch reviewTargetType {
        case .none:
            return notesByID[id] != nil
        case .chatMessage:
            return messagesByID[id] != nil
        case .thing:
            return thingsByID[id] != nil
        case .event:
            return eventsByID[id] != nil
        case .rule:
            return rulesByID[id] != nil
        }
    }

    func hasAvailableRecord(for target: LocalSearchNavigationTarget) -> Bool {
        switch target {
        case .thingDetail(let id):
            return thingsByID[id] != nil
        case .eventDetail(let id):
            return eventsByID[id] != nil
        case .ruleDetail(let id):
            return rulesByID[id] != nil
        case .noteDetail(let id):
            return notesByID[id] != nil
        case .chatMessage(let id):
            return messagesByID[id] != nil
        case .timelineSlice(let descriptor):
            if case .id(let id)? = descriptor.query.linkedThingFilter {
                return thingsByID[id] != nil
            }
            return true
        }
    }

    private static func firstByID<T>(_ records: [T]) -> [UUID: T] {
        Dictionary(records.map { (recordID($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func recordID<T>(_ record: T) -> UUID {
        switch record {
        case let record as ChatMessage:
            return record.id
        case let record as Thing:
            return record.id
        case let record as LedgerEvent:
            return record.id
        case let record as LedgerRule:
            return record.id
        case let record as LedgerNote:
            return record.id
        default:
            return UUID()
        }
    }
}
