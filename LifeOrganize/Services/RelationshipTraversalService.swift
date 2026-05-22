import Foundation

enum RelationshipNode: Hashable {
    case chatMessage(UUID)
    case event(UUID)
    case note(UUID)
    case rule(UUID)
    case thing(UUID)

    init(type: EntityLinkType, id: UUID) {
        switch type {
        case .chatMessage:
            self = .chatMessage(id)
        case .event:
            self = .event(id)
        case .note:
            self = .note(id)
        case .rule:
            self = .rule(id)
        case .thing:
            self = .thing(id)
        }
    }

    var type: EntityLinkType {
        switch self {
        case .chatMessage:
            .chatMessage
        case .event:
            .event
        case .note:
            .note
        case .rule:
            .rule
        case .thing:
            .thing
        }
    }

    var id: UUID {
        switch self {
        case .chatMessage(let id), .event(let id), .note(let id), .rule(let id), .thing(let id):
            id
        }
    }

    var navigationTarget: LocalSearchNavigationTarget {
        switch self {
        case .chatMessage(let id):
            .chatMessage(id)
        case .event(let id):
            .eventDetail(id)
        case .note(let id):
            .noteDetail(id)
        case .rule(let id):
            .ruleDetail(id)
        case .thing(let id):
            .thingDetail(id)
        }
    }

    var stableKey: String {
        "\(type.rawValue):\(id.uuidString)"
    }
}

enum RelationshipTraversalSource: String, Codable {
    case directLink
    case extractedRecord
    case linkedThing
    case mentionedThing
    case sameMessage
    case sharedSourceMessage
    case sharedThing
    case sourceMessage
    case textOverlap

    var displayName: String {
        switch self {
        case .directLink:
            "Direct link"
        case .extractedRecord:
            "Extracted record"
        case .linkedThing:
            "Linked thing"
        case .mentionedThing:
            "Mentioned thing"
        case .sameMessage:
            "Same message"
        case .sharedSourceMessage:
            "Shared source"
        case .sharedThing:
            "Linked thing"
        case .sourceMessage:
            "Source message"
        case .textOverlap:
            "Text overlap"
        }
    }

    var priority: Int {
        switch self {
        case .directLink:
            0
        case .extractedRecord:
            1
        case .sourceMessage:
            2
        case .linkedThing:
            3
        case .mentionedThing:
            4
        case .sameMessage:
            5
        case .sharedSourceMessage:
            6
        case .sharedThing:
            7
        case .textOverlap:
            8
        }
    }
}

struct RelationshipTraversalResult: Identifiable {
    let target: RelationshipNode
    let navigationTarget: LocalSearchNavigationTarget
    let source: RelationshipTraversalSource
    let sourceLabel: String
    let sourceMessageID: UUID?
    let dedupeKey: String
    let confidence: Double?
    let createdBy: EntityLinkCreator?

    var id: String {
        dedupeKey
    }
}

struct RelationshipTraversalService {
    func relatedRecords(
        for source: RelationshipNode,
        in records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>? = nil,
        includeTextOverlap: Bool = false
    ) -> [RelationshipTraversalResult] {
        guard records.contains(source) else { return [] }

        var resultsByKey: [String: RelationshipTraversalResult] = [:]
        addLinkedRecords(
            from: source,
            records: records,
            allowedTargetTypes: allowedTargetTypes,
            resultsByKey: &resultsByKey
        )
        addSharedSourceRecords(
            from: source,
            records: records,
            allowedTargetTypes: allowedTargetTypes,
            resultsByKey: &resultsByKey
        )
        addSharedThingRecords(
            from: source,
            records: records,
            allowedTargetTypes: allowedTargetTypes,
            resultsByKey: &resultsByKey
        )
        if includeTextOverlap {
            addTextOverlapRecords(
                from: source,
                records: records,
                allowedTargetTypes: allowedTargetTypes,
                resultsByKey: &resultsByKey
            )
        }

        return resultsByKey.values.sorted { lhs, rhs in
            if lhs.source.priority != rhs.source.priority {
                return lhs.source.priority < rhs.source.priority
            }
            let lhsDate = records.sortDate(for: lhs.target)
            let rhsDate = records.sortDate(for: rhs.target)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.target.type != rhs.target.type {
                return Self.typeSortIndex(lhs.target.type) < Self.typeSortIndex(rhs.target.type)
            }
            let titleComparison = records.title(for: lhs.target).localizedCaseInsensitiveCompare(records.title(for: rhs.target))
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.target.id.uuidString < rhs.target.id.uuidString
        }
    }

    private func addLinkedRecords(
        from source: RelationshipNode,
        records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>?,
        resultsByKey: inout [String: RelationshipTraversalResult]
    ) {
        for link in records.entityLinks {
            let sourceNode = RelationshipNode(type: link.sourceType, id: link.sourceID)
            let targetNode = RelationshipNode(type: link.targetType, id: link.targetID)
            let traversalTarget: RelationshipNode
            let isInverse: Bool

            if sourceNode == source {
                traversalTarget = targetNode
                isInverse = false
            } else if targetNode == source {
                traversalTarget = sourceNode
                isInverse = true
            } else {
                continue
            }

            addResult(
                target: traversalTarget,
                source: sourceLabel(for: link, traversingFrom: source, target: traversalTarget, isInverse: isInverse),
                sourceMessageID: link.sourceMessageID ?? records.sourceMessageID(for: traversalTarget) ?? records.sourceMessageID(for: source),
                confidence: link.confidence,
                createdBy: link.createdBy,
                records: records,
                allowedTargetTypes: allowedTargetTypes,
                resultsByKey: &resultsByKey
            )
        }
    }

    private func addSharedSourceRecords(
        from source: RelationshipNode,
        records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>?,
        resultsByKey: inout [String: RelationshipTraversalResult]
    ) {
        guard source.type != .chatMessage, let sourceMessageID = records.sourceMessageID(for: source) else { return }
        for target in records.allNodes() where target != source && target.type != .chatMessage {
            if records.sourceMessageID(for: target) == sourceMessageID {
                addResult(
                    target: target,
                    source: .sharedSourceMessage,
                    sourceMessageID: sourceMessageID,
                    confidence: nil,
                    createdBy: nil,
                    records: records,
                    allowedTargetTypes: allowedTargetTypes,
                    resultsByKey: &resultsByKey
                )
            }
        }
    }

    private func addSharedThingRecords(
        from source: RelationshipNode,
        records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>?,
        resultsByKey: inout [String: RelationshipTraversalResult]
    ) {
        let sourceThingIDs = records.linkedThingIDs(for: source)
        guard !sourceThingIDs.isEmpty else { return }

        for target in records.allNodes() where target != source {
            guard target.type != .chatMessage, target.type != .thing else { continue }
            if !sourceThingIDs.isDisjoint(with: records.linkedThingIDs(for: target)) {
                addResult(
                    target: target,
                    source: .sharedThing,
                    sourceMessageID: records.sourceMessageID(for: target) ?? records.sourceMessageID(for: source),
                    confidence: nil,
                    createdBy: nil,
                    records: records,
                    allowedTargetTypes: allowedTargetTypes,
                    resultsByKey: &resultsByKey
                )
            }
        }
    }

    private func addTextOverlapRecords(
        from source: RelationshipNode,
        records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>?,
        resultsByKey: inout [String: RelationshipTraversalResult]
    ) {
        let sourceTokens = tokens(in: records.textValues(for: source))
        guard !sourceTokens.isEmpty else { return }

        for target in records.allNodes() where target != source && target.type != .chatMessage && target.type != .thing {
            let targetTokens = tokens(in: records.textValues(for: target))
            guard !sourceTokens.isDisjoint(with: targetTokens) else { continue }
            addResult(
                target: target,
                source: .textOverlap,
                sourceMessageID: records.sourceMessageID(for: target) ?? records.sourceMessageID(for: source),
                confidence: nil,
                createdBy: nil,
                records: records,
                allowedTargetTypes: allowedTargetTypes,
                resultsByKey: &resultsByKey
            )
        }
    }

    private func addResult(
        target: RelationshipNode,
        source: RelationshipTraversalSource,
        sourceMessageID: UUID?,
        confidence: Double?,
        createdBy: EntityLinkCreator?,
        records: RelationshipTraversalRecords,
        allowedTargetTypes: Set<EntityLinkType>?,
        resultsByKey: inout [String: RelationshipTraversalResult]
    ) {
        guard records.contains(target), allowedTargetTypes?.contains(target.type) ?? true else { return }

        let result = RelationshipTraversalResult(
            target: target,
            navigationTarget: target.navigationTarget,
            source: source,
            sourceLabel: source.displayName,
            sourceMessageID: sourceMessageID,
            dedupeKey: target.stableKey,
            confidence: confidence,
            createdBy: createdBy
        )

        if let existing = resultsByKey[result.dedupeKey], existing.source.priority <= result.source.priority {
            return
        }
        resultsByKey[result.dedupeKey] = result
    }

    private func sourceLabel(
        for link: EntityLink,
        traversingFrom source: RelationshipNode,
        target: RelationshipNode,
        isInverse: Bool
    ) -> RelationshipTraversalSource {
        if link.relation == .sameMessage {
            return .sameMessage
        }
        if source.type == .chatMessage, !isInverse, link.relation == .extractedFrom {
            return .extractedRecord
        }
        if target.type == .chatMessage, isInverse, link.relation == .extractedFrom {
            return .sourceMessage
        }
        if source.type == .chatMessage, !isInverse, link.relation == .mentionsThing {
            return .mentionedThing
        }
        if link.representsThingAssociation {
            return .linkedThing
        }
        return .directLink
    }

    private func tokens(in values: [String]) -> Set<String> {
        Set(
            values
                .flatMap { SearchService.normalizeForLocalSearch($0).split(separator: " ") }
                .map(String.init)
                .filter { $0.count >= 4 && !Self.stopWords.contains($0) }
        )
    }

    private static func typeSortIndex(_ type: EntityLinkType) -> Int {
        switch type {
        case .event:
            0
        case .rule:
            1
        case .note:
            2
        case .thing:
            3
        case .chatMessage:
            4
        }
    }

    private static let stopWords: Set<String> = [
        "about",
        "after",
        "again",
        "until",
        "with",
        "this",
        "that",
        "from",
        "have",
        "will",
        "rule"
    ]
}
