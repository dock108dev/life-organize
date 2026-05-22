import Foundation
@testable import LifeOrganize

extension ScenarioFixtureValidator {
    func validateRules(_ rules: [RuleExport], ids: FixtureRecordIDs) throws {
        for rule in rules {
            try validateUUID(rule.id, field: "rules.id")
            try validateOptionalReference(rule.thingId, in: ids.things, field: "rules.thingId")
            try validateEnum(rule.ruleType, allowed: LedgerRuleType.allCases.map(\.rawValue), field: "rules.ruleType")
            try validateEnum(
                rule.continuityBehavior,
                allowed: LedgerContinuityBehavior.allCases.map(\.rawValue),
                field: "rules.continuityBehavior"
            )
            try validateEnum(rule.lifecycleState, allowed: LedgerRuleLifecycleState.allCases.map(\.rawValue), field: "rules.lifecycleState")
            _ = try parseDateOnly(rule.startsAt, field: "rules.startsAt")
            if let expiresAt = rule.expiresAt {
                _ = try parseDateOnly(expiresAt, field: "rules.expiresAt")
            }
            let createdAt = try parseTimestamp(rule.createdAt, field: "rules.createdAt")
            let updatedAt = try parseTimestamp(rule.updatedAt, field: "rules.updatedAt")
            try require(updatedAt >= createdAt, "Rule \(rule.id) updatedAt must be on or after createdAt.")
            if let deactivatedAtText = rule.manuallyDeactivatedAt {
                let deactivatedAt = try parseTimestamp(deactivatedAtText, field: "rules.manuallyDeactivatedAt")
                try require(deactivatedAt >= createdAt, "Rule \(rule.id) manuallyDeactivatedAt must be on or after createdAt.")
            }
            try validateSource(rule.source, ids: ids, field: "rules.source")
        }
    }

    func validateNotes(_ notes: [NoteExport], ids: FixtureRecordIDs) throws {
        for note in notes {
            try validateUUID(note.id, field: "notes.id")
            let createdAt = try parseTimestamp(note.createdAt, field: "notes.createdAt")
            let updatedAt = try parseTimestamp(note.updatedAt, field: "notes.updatedAt")
            try require(updatedAt >= createdAt, "Note \(note.id) updatedAt must be on or after createdAt.")
            for thingID in note.linkedThingIds {
                try validateReference(thingID, in: ids.things, field: "notes.linkedThingIds")
            }
            try validateSource(note.source, ids: ids, field: "notes.source")
        }
    }

    func validateReviewItems(_ items: [LedgerReviewItemExport], ids: FixtureRecordIDs) throws {
        for item in items {
            try validateUUID(item.id, field: "ledgerReviewItems.id")
            try validateEnum(item.kind, allowed: LedgerReviewItemKind.allCases.map(\.rawValue), field: "ledgerReviewItems.kind")
            try validateEnum(item.state, allowed: LedgerReviewItemState.allCases.map(\.rawValue), field: "ledgerReviewItems.state")
            try validateEnum(
                item.targetType,
                allowed: LedgerReviewItemTargetType.allCases.map(\.rawValue),
                field: "ledgerReviewItems.targetType"
            )
            try validateReviewReference(item.targetId, type: item.targetType, ids: ids, field: "ledgerReviewItems.targetId")
            let createdAt = try parseTimestamp(item.createdAt, field: "ledgerReviewItems.createdAt")
            let updatedAt = try parseTimestamp(item.updatedAt, field: "ledgerReviewItems.updatedAt")
            try require(updatedAt >= createdAt, "Review item \(item.id) updatedAt must be on or after createdAt.")
            try require((0...1).contains(item.confidence), "Review item \(item.id) confidence must be between 0 and 1.")
            if let presentedAt = item.presentedAt {
                try require(
                    try parseTimestamp(presentedAt, field: "ledgerReviewItems.presentedAt") >= createdAt,
                    "Review item \(item.id) presentedAt must be on or after createdAt."
                )
            }
            if let resolvedAt = item.resolvedAt {
                try require(
                    try parseTimestamp(resolvedAt, field: "ledgerReviewItems.resolvedAt") >= createdAt,
                    "Review item \(item.id) resolvedAt must be on or after createdAt."
                )
            }
            if let snoozedUntil = item.snoozedUntil {
                try require(
                    try parseTimestamp(snoozedUntil, field: "ledgerReviewItems.snoozedUntil") >= createdAt,
                    "Review item \(item.id) snoozedUntil must be on or after createdAt."
                )
            }
            if let expiresAt = item.expiresAt {
                _ = try parseTimestamp(expiresAt, field: "ledgerReviewItems.expiresAt")
            }
            for evidence in item.evidence {
                try validateEnum(
                    evidence.sourceType,
                    allowed: LedgerReviewItemTargetType.allCases.map(\.rawValue),
                    field: "ledgerReviewItems.evidence.sourceType"
                )
                try validateReviewReference(
                    evidence.sourceId,
                    type: evidence.sourceType,
                    ids: ids,
                    field: "ledgerReviewItems.evidence.sourceId"
                )
            }
        }
    }

    func validateEntityLinks(_ links: [EntityLinkExport], ids: FixtureRecordIDs) throws {
        for link in links {
            try validateUUID(link.id, field: "entityLinks.id")
            try validateExportEntityReference(type: link.fromEntityType, id: link.fromEntityId, ids: ids, field: "entityLinks.from")
            try validateExportEntityReference(type: link.toEntityType, id: link.toEntityId, ids: ids, field: "entityLinks.to")
            try validateEnum(
                link.relationship,
                allowed: ["created_from", "mentions", "linked_to", "related_to"],
                field: "entityLinks.relationship"
            )
            _ = try parseTimestamp(link.createdAt, field: "entityLinks.createdAt")
            try validateSource(link.source, ids: ids, field: "entityLinks.source")
        }
    }

    func validateMetadata(_ metadata: EventMetadataExport, eventID: String) throws {
        try validateEnum(metadata.key, allowed: LedgerEventMetadataKey.allCases.map(\.rawValue), field: "events.metadata.key")
        try validateEnum(
            metadata.valueKind,
            allowed: LedgerEventMetadataValueKind.allCases.map(\.rawValue),
            field: "events.metadata.valueKind"
        )
        if let dateValue = metadata.dateValue {
            _ = try parseDateOnly(dateValue, field: "events.metadata.dateValue")
        }
        let populatedValues = [
            metadata.stringValue != nil,
            metadata.numberValue != nil,
            metadata.dateValue != nil,
            metadata.boolValue != nil,
        ].filter { $0 }.count
        try require(populatedValues == 1, "Event \(eventID) metadata \(metadata.key) must set exactly one value field.")
        switch metadata.valueKind {
        case LedgerEventMetadataValueKind.string.rawValue:
            try require(metadata.stringValue != nil, "Event \(eventID) string metadata \(metadata.key) needs stringValue.")
        case LedgerEventMetadataValueKind.number.rawValue:
            try require(metadata.numberValue != nil, "Event \(eventID) number metadata \(metadata.key) needs numberValue.")
        case LedgerEventMetadataValueKind.date.rawValue:
            try require(metadata.dateValue != nil, "Event \(eventID) date metadata \(metadata.key) needs dateValue.")
        case LedgerEventMetadataValueKind.boolean.rawValue:
            try require(metadata.boolValue != nil, "Event \(eventID) boolean metadata \(metadata.key) needs boolValue.")
        default:
            break
        }
    }
}
