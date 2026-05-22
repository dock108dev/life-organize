import Foundation

struct RelationshipTraversalRecords {
    var messages: [ChatMessage]
    var things: [Thing]
    var events: [LedgerEvent]
    var rules: [LedgerRule]
    var notes: [LedgerNote]
    var entityLinks: [EntityLink]

    private let messageByID: [UUID: ChatMessage]
    private let thingByID: [UUID: Thing]
    private let eventByID: [UUID: LedgerEvent]
    private let ruleByID: [UUID: LedgerRule]
    private let noteByID: [UUID: LedgerNote]
    private let nodes: [RelationshipNode]

    init(
        messages: [ChatMessage] = [],
        things: [Thing] = [],
        events: [LedgerEvent] = [],
        rules: [LedgerRule] = [],
        notes: [LedgerNote] = [],
        entityLinks: [EntityLink] = []
    ) {
        self.messages = messages
        self.things = things
        self.events = events
        self.rules = rules
        self.notes = notes
        self.entityLinks = entityLinks
        messageByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        thingByID = Dictionary(uniqueKeysWithValues: things.map { ($0.id, $0) })
        eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        ruleByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        noteByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        var nodes: [RelationshipNode] = []
        nodes.append(contentsOf: messages.map { RelationshipNode.chatMessage($0.id) })
        nodes.append(contentsOf: events.map { RelationshipNode.event($0.id) })
        nodes.append(contentsOf: rules.map { RelationshipNode.rule($0.id) })
        nodes.append(contentsOf: notes.map { RelationshipNode.note($0.id) })
        nodes.append(contentsOf: things.map { RelationshipNode.thing($0.id) })
        self.nodes = nodes
    }

    func contains(_ node: RelationshipNode) -> Bool {
        switch node {
        case .chatMessage(let id):
            messageByID[id] != nil
        case .event(let id):
            eventByID[id] != nil
        case .note(let id):
            noteByID[id] != nil
        case .rule(let id):
            ruleByID[id] != nil
        case .thing(let id):
            thingByID[id] != nil
        }
    }

    func allNodes() -> [RelationshipNode] {
        nodes
    }

    func sourceMessageID(for node: RelationshipNode) -> UUID? {
        switch node {
        case .chatMessage(let id):
            id
        case .event(let id):
            eventByID[id]?.sourceMessage?.id
        case .note(let id):
            noteByID[id]?.sourceMessage?.id
        case .rule(let id):
            ruleByID[id]?.sourceMessage?.id
        case .thing(let id):
            thingByID[id]?.sourceMessageIDs.first
        }
    }

    func linkedThingIDs(for node: RelationshipNode) -> Set<UUID> {
        var ids = modelLinkedThingIDs(for: node)
        for link in entityLinks {
            let sourceNode = RelationshipNode(type: link.sourceType, id: link.sourceID)
            let targetNode = RelationshipNode(type: link.targetType, id: link.targetID)
            guard link.representsThingAssociation else { continue }

            if sourceNode == node, targetNode.type == .thing, contains(targetNode) {
                ids.insert(targetNode.id)
            }
            if targetNode == node, sourceNode.type == .thing, contains(sourceNode) {
                ids.insert(sourceNode.id)
            }
        }
        return ids
    }

    func title(for node: RelationshipNode) -> String {
        switch node {
        case .chatMessage(let id):
            messageByID[id]?.text ?? ""
        case .event(let id):
            eventByID[id]?.title ?? ""
        case .note(let id):
            noteByID[id]?.text ?? ""
        case .rule(let id):
            ruleByID[id]?.title ?? ""
        case .thing(let id):
            thingByID[id]?.name ?? ""
        }
    }

    func sortDate(for node: RelationshipNode) -> Date {
        switch node {
        case .chatMessage(let id):
            messageByID[id]?.createdAt ?? .distantPast
        case .event(let id):
            eventByID[id]?.occurredAt ?? .distantPast
        case .note(let id):
            noteByID[id]?.updatedAt ?? .distantPast
        case .rule(let id):
            ruleByID[id]?.startsAt ?? .distantPast
        case .thing(let id):
            thingByID[id]?.lastEventAt ?? thingByID[id]?.updatedAt ?? .distantPast
        }
    }

    func textValues(for node: RelationshipNode) -> [String] {
        switch node {
        case .chatMessage(let id):
            return [messageByID[id]?.text ?? ""]
        case .event(let id):
            guard let event = eventByID[id] else { return [] }
            return [event.title, event.rawText, event.note ?? "", event.thing?.name ?? ""]
        case .note(let id):
            guard let note = noteByID[id] else { return [] }
            return [note.text] + note.linkedThings.flatMap { [$0.name] + $0.aliases }
        case .rule(let id):
            guard let rule = ruleByID[id] else { return [] }
            return [rule.title, rule.reason ?? "", rule.rawText, rule.thing?.name ?? ""] + (rule.thing?.aliases ?? [])
        case .thing(let id):
            guard let thing = thingByID[id] else { return [] }
            return [thing.name, thing.details] + thing.aliases
        }
    }

    private func modelLinkedThingIDs(for node: RelationshipNode) -> Set<UUID> {
        switch node {
        case .chatMessage:
            []
        case .event(let id):
            Set([eventByID[id]?.thing?.id].compactMap { $0 })
        case .note(let id):
            Set(noteByID[id]?.linkedThings.map(\.id) ?? [])
        case .rule(let id):
            Set([ruleByID[id]?.thing?.id].compactMap { $0 })
        case .thing(let id):
            [id]
        }
    }
}

extension EntityLink {
    var representsThingAssociation: Bool {
        switch relation {
        case .aboutThing, .mentionsThing, .primaryThing:
            sourceType == .thing || targetType == .thing
        case .extractedFrom, .sameMessage:
            false
        }
    }
}
