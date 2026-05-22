import Foundation
import SwiftData

@Model
final class Thing {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedKey: String
    var details: String
    var aliases: [String]
    var categoryRawValue: String?
    var createdAt: Date
    var updatedAt: Date
    var sourceMessageIDs: [UUID] = []
    var sourceExtractionAttemptIDs: [UUID] = []
    var eventCount: Int
    var lastEventAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \LedgerEvent.thing)
    var events: [LedgerEvent]

    @Relationship(deleteRule: .nullify, inverse: \LedgerRule.thing)
    var rules: [LedgerRule]

    @Relationship(deleteRule: .nullify, inverse: \LedgerNote.linkedThings)
    var notes: [LedgerNote]

    var category: ThingCategory? {
        get {
            guard let categoryRawValue else { return nil }
            return ThingCategory(rawValue: categoryRawValue)
        }
        set {
            categoryRawValue = newValue?.rawValue
            updatedAt = Date()
        }
    }

    var activeRules: [LedgerRule] {
        rules.filter(\.isCurrentlyActive)
    }

    init(
        id: UUID = UUID(),
        name: String,
        normalizedKey: String? = nil,
        details: String = "",
        aliases: [String] = [],
        category: ThingCategory? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceMessageIDs: [UUID] = [],
        sourceExtractionAttemptIDs: [UUID] = [],
        eventCount: Int = 0,
        lastEventAt: Date? = nil,
        events: [LedgerEvent] = [],
        rules: [LedgerRule] = [],
        notes: [LedgerNote] = []
    ) {
        self.id = id
        self.name = name
        self.normalizedKey = normalizedKey ?? ThingNormalizer.normalizeKey(name)
        self.details = details
        self.aliases = aliases
        self.categoryRawValue = category?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceMessageIDs = sourceMessageIDs
        self.sourceExtractionAttemptIDs = sourceExtractionAttemptIDs
        self.eventCount = eventCount
        self.lastEventAt = lastEventAt
        self.events = events
        self.rules = rules
        self.notes = notes
    }

    func registerAlias(_ alias: String, updatedAt: Date = Date()) {
        registerAliases([alias], updatedAt: updatedAt)
    }

    func registerAliases(_ newAliases: [String], updatedAt: Date = Date()) {
        aliases = ThingAliasPolicy.appendingAliases(newAliases, to: aliases, excludingName: name)
        normalizedKey = ThingNormalizer.normalizeKey(name)
        self.updatedAt = updatedAt
    }
}

enum ThingCategory: String, Codable, CaseIterable {
    case admin
    case finance
    case food
    case health
    case home
    case homeMaintenance = "home_maintenance"
    case maintenance
    case person
    case pet
    case place
    case project
    case purchase
    case ruleTopic = "rule_topic"
    case subscription
    case travel
    case vehicle
    case work
    case other

    var displayName: String {
        rawValue
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// Maps production extraction schema categories into persisted Thing categories.
    static func fromExtractionCategory(_ value: String?) -> ThingCategory? {
        guard let value else { return nil }
        switch normalizedExtractionCategory(value) {
        case "admin":
            return .admin
        case "finance":
            return .finance
        case "food":
            return .food
        case "fitness", "health":
            return .health
        case "home":
            return .home
        case "homemaintenance", "home_maintenance":
            return .homeMaintenance
        case "maintenance":
            return .maintenance
        case "person":
            return .person
        case "pet":
            return .pet
        case "place":
            return .place
        case "project":
            return .project
        case "purchase", "purchaserestriction":
            return .purchase
        case "rule_topic":
            return .ruleTopic
        case "subscription":
            return .subscription
        case "travel":
            return .travel
        case "vehicle":
            return .vehicle
        case "work":
            return .work
        case "other", "unknown":
            return .other
        default:
            return .other
        }
    }

    private static func normalizedExtractionCategory(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
