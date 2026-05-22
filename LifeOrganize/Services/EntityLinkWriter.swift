import Foundation
import SwiftData

@MainActor
struct EntityLinkWriter {
    let modelContext: ModelContext
    var now: () -> Date = { Date() }

    func linkMessage(_ message: ChatMessage, mentions thing: Thing) throws {
        try insertUnique(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .mentionsThing,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
    }

    func linkExtracted(message: ChatMessage, event: LedgerEvent) throws {
        try insertUnique(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .event,
            targetID: event.id,
            relation: .extractedFrom,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
    }

    func linkExtracted(message: ChatMessage, rule: LedgerRule) throws {
        try insertUnique(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .rule,
            targetID: rule.id,
            relation: .extractedFrom,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
    }

    func linkExtracted(message: ChatMessage, note: LedgerNote) throws {
        try insertUnique(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .note,
            targetID: note.id,
            relation: .extractedFrom,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
    }

    func linkPrimary(event: LedgerEvent, thing: Thing, sourceMessage: ChatMessage) throws {
        try insertUnique(
            sourceType: .event,
            sourceID: event.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .primaryThing,
            createdBy: .extraction,
            sourceMessageID: sourceMessage.id
        )
    }

    func linkPrimary(rule: LedgerRule, thing: Thing, sourceMessage: ChatMessage) throws {
        try insertUnique(
            sourceType: .rule,
            sourceID: rule.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .primaryThing,
            createdBy: .extraction,
            sourceMessageID: sourceMessage.id
        )
    }

    func linkAbout(note: LedgerNote, thing: Thing, sourceMessage: ChatMessage) throws {
        try insertUnique(
            sourceType: .note,
            sourceID: note.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .aboutThing,
            createdBy: .extraction,
            sourceMessageID: sourceMessage.id
        )
    }

    func linkSiblings(_ entities: [(EntityLinkType, UUID)], sourceMessage: ChatMessage) throws {
        for source in entities {
            for target in entities where source.1 != target.1 {
                try insertUnique(
                    sourceType: source.0,
                    sourceID: source.1,
                    targetType: target.0,
                    targetID: target.1,
                    relation: .sameMessage,
                    createdBy: .system,
                    sourceMessageID: sourceMessage.id
                )
            }
        }
    }

    private func insertUnique(
        sourceType: EntityLinkType,
        sourceID: UUID,
        targetType: EntityLinkType,
        targetID: UUID,
        relation: EntityLinkRelation,
        createdBy: EntityLinkCreator,
        sourceMessageID: UUID?
    ) throws {
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        let exists = links.contains {
            $0.sourceType == sourceType
                && $0.sourceID == sourceID
                && $0.targetType == targetType
                && $0.targetID == targetID
                && $0.relation == relation
        }
        guard !exists else { return }

        modelContext.insert(
            EntityLink(
                sourceType: sourceType,
                sourceID: sourceID,
                targetType: targetType,
                targetID: targetID,
                relation: relation,
                createdAt: now(),
                createdBy: createdBy,
                sourceMessageID: sourceMessageID
            )
        )
    }
}
