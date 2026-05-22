import Foundation

struct ThingNormalizationCategoryEvidence: Codable, Equatable {
    var extractionCategory: ThingCategory?
    var eventTypeCategory: ThingCategory?
    var sourceCategories: [ThingCategory]
    var contextCategories: [ThingCategory]
    var targetCategory: ThingCategory?
    var primaryCategory: ThingCategory?
    var hasConflict: Bool
}

extension ThingNormalizer {
    static func categoryEvidence(
        categoryHint: String?,
        eventTypeHint: String? = nil,
        contextText: String,
        sourceValues: [String],
        targetCategory: ThingCategory? = nil
    ) -> ThingNormalizationCategoryEvidence {
        let extractionCategory = ThingCategory.fromExtractionCategory(categoryHint)
        let eventTypeCategory = category(forEventType: eventTypeHint)
        let sourceCategories = categories(in: sourceValues.joined(separator: " "))
        let contextCategories = categories(in: contextText)
        let primaryCategory = primaryCategory(
            extractionCategory: extractionCategory,
            eventTypeCategory: eventTypeCategory,
            sourceCategories: sourceCategories,
            contextCategories: contextCategories
        )

        return ThingNormalizationCategoryEvidence(
            extractionCategory: extractionCategory,
            eventTypeCategory: eventTypeCategory,
            sourceCategories: sourceCategories,
            contextCategories: contextCategories,
            targetCategory: targetCategory,
            primaryCategory: primaryCategory,
            hasConflict: hasCategoryConflict(sourceCategory: primaryCategory, targetCategory: targetCategory)
        )
    }

    static func inferredCategory(
        categoryHint: String?,
        eventTypeHint: String? = nil,
        contextText: String,
        sourceValues: [String]
    ) -> ThingCategory? {
        categoryEvidence(
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            sourceValues: sourceValues
        ).primaryCategory
    }

    static func hasCategoryConflict(
        categoryHint: String?,
        eventTypeHint: String? = nil,
        contextText: String,
        sourceValues: [String],
        targetCategory: ThingCategory?
    ) -> Bool {
        categoryEvidence(
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            sourceValues: sourceValues,
            targetCategory: targetCategory
        ).hasConflict
    }

    private static func primaryCategory(
        extractionCategory: ThingCategory?,
        eventTypeCategory: ThingCategory?,
        sourceCategories: [ThingCategory],
        contextCategories: [ThingCategory]
    ) -> ThingCategory? {
        if sourceCategories.contains(.pet), sourceCategories.contains(.food) {
            return .pet
        }
        if sourceCategories.contains(.vehicle) || contextCategories.contains(.vehicle) {
            return .vehicle
        }
        if sourceCategories.contains(.subscription) || contextCategories.contains(.subscription) {
            return .subscription
        }
        if sourceCategories.contains(.homeMaintenance) {
            return .homeMaintenance
        }
        if sourceCategories.contains(.maintenance) {
            return .maintenance
        }
        if sourceCategories.contains(.work) {
            return .work
        }
        if let extractionCategory, extractionCategory != .other {
            return extractionCategory
        }
        if let eventTypeCategory {
            return eventTypeCategory
        }
        if contextCategories.contains(.homeMaintenance) {
            return .homeMaintenance
        }
        if contextCategories.contains(.maintenance) {
            return .maintenance
        }
        if contextCategories.contains(.work) {
            return .work
        }
        return contextCategories.first
    }

    private static func category(forEventType value: String?) -> ThingCategory? {
        guard let rawValue = value?.nilIfEmpty else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case LedgerEventType.maintenance.rawValue,
             LedgerEventType.replacement.rawValue,
             LedgerEventType.cleaning.rawValue:
            return .maintenance
        case LedgerEventType.purchase.rawValue:
            return .purchase
        case LedgerEventType.renewal.rawValue:
            return .subscription
        case LedgerEventType.appointment.rawValue,
             LedgerEventType.measurement.rawValue:
            return .health
        case LedgerEventType.project.rawValue,
             LedgerEventType.statusChange.rawValue:
            return .project
        default:
            return nil
        }
    }

    private static func categories(in text: String) -> [ThingCategory] {
        let key = normalizeKey(text)
        return categorySignals.compactMap { signal in
            signal.tokens.contains { key.contains($0) } ? signal.category : nil
        }.removingDuplicates()
    }

    private static func hasCategoryConflict(sourceCategory: ThingCategory?, targetCategory: ThingCategory?) -> Bool {
        guard let sourceCategory, let targetCategory else { return false }
        if sourceCategory == .other || targetCategory == .other || sourceCategory == targetCategory {
            return false
        }
        return !compatibleCategoryGroups.contains { group in
            group.contains(sourceCategory) && group.contains(targetCategory)
        }
    }

    private static let categorySignals: [(category: ThingCategory, tokens: Set<String>)] = [
        (.work, ["cloud", "deploy", "infra", "infrastructure", "nimbus", "nws", "security", "server", "service", "vuln", "vulnerability", "work"]),
        (.vehicle, ["auto", "car", "mileage", "odometer", "tire", "vehicle"]),
        (.pet, ["cat", "dog", "kibble", "litter", "pet", "vet"]),
        (.food, ["coffee", "dinner", "food", "grocer", "grocery", "lunch", "meal"]),
        (.homeMaintenance, ["air filter", "appliance", "furnace", "garage", "home", "house", "hvac", "plumbing", "roof"]),
        (.maintenance, ["change oil", "oil change", "replace", "service"]),
        (.subscription, ["membership", "monthly", "plan", "renewal", "subscription"]),
        (.purchase, ["amount", "bought", "buy", "order", "paid", "purchase", "receipt", "vendor"]),
        (.project, ["milestone", "project", "roadmap", "task"]),
    ]

    private static let compatibleCategoryGroups: [Set<ThingCategory>] = [
        [.home, .homeMaintenance, .maintenance],
        [.vehicle, .maintenance],
        [.pet, .food],
        [.work, .project],
        [.purchase, .subscription],
    ]
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
