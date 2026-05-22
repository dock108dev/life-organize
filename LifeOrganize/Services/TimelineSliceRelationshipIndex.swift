import Foundation

struct TimelineSliceRelationshipIndex {
    private let thingByID: [UUID: Thing]
    private let linksByNode: [RelationshipNode: [EntityLink]]

    init(things: [Thing], entityLinks: [EntityLink]) {
        self.thingByID = Dictionary(uniqueKeysWithValues: things.map { ($0.id, $0) })
        var linksByNode: [RelationshipNode: [EntityLink]] = [:]
        for link in entityLinks {
            let source = RelationshipNode(type: link.sourceType, id: link.sourceID)
            let target = RelationshipNode(type: link.targetType, id: link.targetID)
            linksByNode[source, default: []].append(link)
            linksByNode[target, default: []].append(link)
        }
        self.linksByNode = linksByNode
    }

    func thingContexts(for node: RelationshipNode, fallback: [Thing] = []) -> [TimelineSliceThingContext] {
        var contextsByID = Dictionary(
            uniqueKeysWithValues: fallback.map {
                ($0.id, TimelineSliceThingContext(id: $0.id, name: $0.name, aliases: $0.aliases, relationshipSourceLabel: nil))
            }
        )

        for link in linksByNode[node] ?? [] where link.representsThingAssociation {
            let linkedThingID: UUID?
            if link.sourceType == .thing {
                linkedThingID = link.sourceID
            } else if link.targetType == .thing {
                linkedThingID = link.targetID
            } else {
                linkedThingID = nil
            }

            guard let linkedThingID, let thing = thingByID[linkedThingID] else { continue }
            contextsByID[linkedThingID] = TimelineSliceThingContext(
                id: thing.id,
                name: thing.name,
                aliases: thing.aliases,
                relationshipSourceLabel: RelationshipTraversalSource.linkedThing.displayName
            )
        }

        return contextsByID.values.sorted {
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func relationshipContext(for node: RelationshipNode) -> TimelineSliceRelationshipContext? {
        (linksByNode[node] ?? [])
            .sorted { lhs, rhs in
                let lhsSource = source(for: lhs, node: node)
                let rhsSource = source(for: rhs, node: node)
                if lhsSource.priority != rhsSource.priority {
                    return lhsSource.priority < rhsSource.priority
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
            .map {
                TimelineSliceRelationshipContext(
                    sourceLabel: source(for: $0, node: node).displayName,
                    sourceMessageID: $0.sourceMessageID,
                    confidence: $0.confidence
                )
            }
    }

    private func source(for link: EntityLink, node: RelationshipNode) -> RelationshipTraversalSource {
        if link.relation == .sameMessage {
            return .sameMessage
        }
        if link.representsThingAssociation {
            return .linkedThing
        }
        if link.relation == .extractedFrom {
            return node.type == .chatMessage ? .extractedRecord : .sourceMessage
        }
        return .directLink
    }
}
