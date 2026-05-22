import Foundation
import SwiftData

@Model
final class EntityLink {
    @Attribute(.unique) var id: UUID
    var sourceTypeRawValue: String
    var sourceID: UUID
    var targetTypeRawValue: String
    var targetID: UUID
    var relationRawValue: String
    var createdAt: Date
    var confidence: Double
    var createdByRawValue: String
    var sourceMessageID: UUID?

    var sourceType: EntityLinkType {
        get { EntityLinkType(rawValue: sourceTypeRawValue) ?? .chatMessage }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var targetType: EntityLinkType {
        get { EntityLinkType(rawValue: targetTypeRawValue) ?? .chatMessage }
        set { targetTypeRawValue = newValue.rawValue }
    }

    var relation: EntityLinkRelation {
        get { EntityLinkRelation(rawValue: relationRawValue) ?? .mentionsThing }
        set { relationRawValue = newValue.rawValue }
    }

    var createdBy: EntityLinkCreator {
        get { EntityLinkCreator(rawValue: createdByRawValue) ?? .system }
        set { createdByRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sourceType: EntityLinkType,
        sourceID: UUID,
        targetType: EntityLinkType,
        targetID: UUID,
        relation: EntityLinkRelation,
        createdAt: Date = Date(),
        confidence: Double = 1,
        createdBy: EntityLinkCreator,
        sourceMessageID: UUID? = nil
    ) {
        self.id = id
        self.sourceTypeRawValue = sourceType.rawValue
        self.sourceID = sourceID
        self.targetTypeRawValue = targetType.rawValue
        self.targetID = targetID
        self.relationRawValue = relation.rawValue
        self.createdAt = createdAt
        self.confidence = confidence
        self.createdByRawValue = createdBy.rawValue
        self.sourceMessageID = sourceMessageID
    }
}

enum EntityLinkType: String, Codable, CaseIterable {
    case chatMessage = "chat_message"
    case event
    case note
    case rule
    case thing
}

enum EntityLinkRelation: String, Codable, CaseIterable {
    case aboutThing = "about_thing"
    case extractedFrom = "extracted_from"
    case mentionsThing = "mentions_thing"
    case primaryThing = "primary_thing"
    case sameMessage = "same_message"
}

enum EntityLinkCreator: String, Codable, CaseIterable {
    case extraction
    case system
    case user
}
