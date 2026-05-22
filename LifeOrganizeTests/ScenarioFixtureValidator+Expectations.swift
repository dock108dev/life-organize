import Foundation
@testable import LifeOrganize

extension ScenarioFixtureValidator {
    func validateExpectations(_ expectations: ScenarioExpectations, ids: FixtureRecordIDs) throws {
        let surfaces = ["log", "things", "reminders", "reviewQueue", "search", "timelineReplay", "settings"]
        for expectation in expectations.requiredVisibleSurfaces {
            try validateEnum(expectation.surface, allowed: surfaces, field: "expectations.requiredVisibleSurfaces.surface")
            for recordID in expectation.requiredRecordIds {
                try validateAnyRecordReference(recordID, ids: ids, field: "expectations.requiredVisibleSurfaces.requiredRecordIds")
            }
        }

        for relationship in expectations.relationshipChecks {
            try validateEnum(
                relationship.kind,
                allowed: ["thingHasEvent", "thingHasRule", "thingHasNote", "messageLinksEntity", "entityLinkExists"],
                field: "expectations.relationshipChecks.kind"
            )
            try validateExportEntityReference(
                type: relationship.fromType,
                id: relationship.fromId,
                ids: ids,
                field: "expectations.relationshipChecks.from"
            )
            try validateExportEntityReference(
                type: relationship.toType,
                id: relationship.toId,
                ids: ids,
                field: "expectations.relationshipChecks.to"
            )
        }

        for expectation in expectations.searchExpectations {
            try require(!expectation.query.isEmpty, "Search expectation query is required.")
            for target in expectation.expectedTargets {
                try validateExportEntityReference(type: target.type, id: target.id, ids: ids, field: "expectations.search.expectedTargets")
            }
        }

        for expectation in expectations.replayExpectations {
            try validateExportEntityReference(
                type: expectation.sourceType,
                id: expectation.sourceId,
                ids: ids,
                field: "expectations.replay.source"
            )
            for target in expectation.expectedTargets {
                try validateExportEntityReference(type: target.type, id: target.id, ids: ids, field: "expectations.replay.expectedTargets")
            }
        }

        for expectation in expectations.reviewQueueExpectations {
            try validateEnum(expectation.kind, allowed: LedgerReviewItemKind.allCases.map(\.rawValue), field: "expectations.reviewQueue.kind")
            try validateEnum(expectation.state, allowed: LedgerReviewItemState.allCases.map(\.rawValue), field: "expectations.reviewQueue.state")
            try validateEnum(
                expectation.targetType,
                allowed: LedgerReviewItemTargetType.allCases.map(\.rawValue),
                field: "expectations.reviewQueue.targetType"
            )
            try validateReviewReference(
                expectation.targetId,
                type: expectation.targetType,
                ids: ids,
                field: "expectations.reviewQueue.targetId"
            )
            for evidenceID in expectation.requiredEvidenceIds {
                try validateAnyRecordReference(evidenceID, ids: ids, field: "expectations.reviewQueue.requiredEvidenceIds")
            }
        }
    }

    func validateReviewReference(
        _ id: String?,
        type: String,
        ids: FixtureRecordIDs,
        field: String
    ) throws {
        guard let id else { return }
        switch type {
        case LedgerReviewItemTargetType.none.rawValue:
            throw ScenarioFixtureError.invalidFixture("\(field) cannot include an id when target type is none.")
        case LedgerReviewItemTargetType.chatMessage.rawValue:
            try validateReference(id, in: ids.chatMessages, field: field)
        case LedgerReviewItemTargetType.thing.rawValue:
            try validateReference(id, in: ids.things, field: field)
        case LedgerReviewItemTargetType.event.rawValue:
            try validateReference(id, in: ids.events, field: field)
        case LedgerReviewItemTargetType.rule.rawValue:
            try validateReference(id, in: ids.rules, field: field)
        default:
            throw ScenarioFixtureError.invalidFixture("\(field) has unsupported target type \(type).")
        }
    }

    func validateExportEntityReference(
        type: String,
        id: String,
        ids: FixtureRecordIDs,
        field: String
    ) throws {
        switch type {
        case "chatMessage":
            try validateReference(id, in: ids.chatMessages, field: field)
        case "extractionRun":
            try validateReference(id, in: ids.extractionRuns, field: field)
        case "thing":
            try validateReference(id, in: ids.things, field: field)
        case "event":
            try validateReference(id, in: ids.events, field: field)
        case "rule":
            try validateReference(id, in: ids.rules, field: field)
        case "note":
            try validateReference(id, in: ids.notes, field: field)
        case "ledgerReviewItem":
            try validateReference(id, in: ids.ledgerReviewItems, field: field)
        case "entityLink":
            try validateReference(id, in: ids.entityLinks, field: field)
        default:
            throw ScenarioFixtureError.invalidFixture("\(field) has unsupported entity type \(type).")
        }
    }

    func validateAnyRecordReference(_ id: String, ids: FixtureRecordIDs, field: String) throws {
        try validateUUID(id, field: field)
        if !ids.allRecordIDs.contains(id) {
            throw ScenarioFixtureError.invalidFixture("\(field) references missing record \(id).")
        }
    }
}
