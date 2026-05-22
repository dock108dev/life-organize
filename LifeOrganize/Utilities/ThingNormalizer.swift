import Foundation

struct ThingSeed: Equatable {
    var canonicalName: String
    var canonicalKey: String
    var category: ThingCategory
    var aliases: [String]

    var matchKeys: Set<String> {
        Set(([canonicalKey] + aliases).map(ThingNormalizer.normalizeKey).filter { !$0.isEmpty })
    }
}

enum ThingNormalizer {
    static func normalizeKey(_ value: String) -> String {
        let words = LedgerTextMatching.normalizedAlphanumericText(value)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .compactMap(normalizedWord)

        return words.joined(separator: " ")
    }

    static func displayName(for value: String) -> String {
        displayName(for: value, contextText: value)
    }

    static func displayName(for value: String, contextText: String) -> String {
        if let seed = seed(for: value, contextText: contextText) {
            return seed.canonicalName
        }

        let surfaceWords = displaySurfaceWords(for: value)
        return normalizeKey(value)
            .split(separator: " ")
            .map { displayWord($0, surfaceWords: surfaceWords) }
            .joined(separator: " ")
    }

    static func seed(for value: String, contextText: String) -> ThingSeed? {
        let valueKey = normalizeKey(value)
        let contextKey = normalizeKey(contextText)
        guard !valueKey.isEmpty else { return nil }

        for seed in seeds where seed.matchKeys.contains(valueKey) {
            if isBlocked(seed: seed, valueKey: valueKey, contextKey: contextKey) {
                return nil
            }
            return seed
        }

        if let seed = contextualFilterSeed(valueKey: valueKey, contextKey: contextKey) {
            return seed
        }

        return nil
    }

    static func isAmbiguousFilterAliasKey(_ key: String) -> Bool {
        key == "air filter" || key == "filter"
    }

    private static func normalizedWord(_ word: String) -> String? {
        let lemmatized = verbForms[word] ?? singularWord(word)
        guard !fillerWords.contains(lemmatized), !lemmatized.isEmpty else {
            return nil
        }
        return lemmatized
    }

    private static func singularWord(_ word: String) -> String {
        if protectedProperNames.contains(word) {
            return word
        }
        if word.hasSuffix("ies"), word.count > 4 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("s"),
           !word.hasSuffix("ss"),
           !word.hasSuffix("us"),
           !word.hasSuffix("is"),
           word.count > 3 {
            return String(word.dropLast())
        }
        return word
    }

    private static func displayWord(_ word: Substring, surfaceWords: [String: String]) -> String {
        let key = String(word)
        if let acronym = acronymDisplayWords[key] {
            return acronym
        }
        if let surfaceWord = surfaceWords[key] {
            return surfaceWord
        }
        return key.capitalized
    }

    private static func displaySurfaceWords(for value: String) -> [String: String] {
        LedgerTextMatching.normalizedAlphanumericText(value)
            .split(whereSeparator: \.isWhitespace)
            .reduce(into: [:]) { result, rawWord in
                let rawValue = String(rawWord)
                guard let normalized = normalizedWord(rawValue), acronymDisplayWords[normalized] == nil else {
                    return
                }
                guard displaySurfacePassthroughWords.contains(normalized) else {
                    return
                }
                result[normalized] = rawValue.capitalized
            }
    }

    static func isBlocked(seed: ThingSeed, valueKey: String, contextKey: String) -> Bool {
        let combined = "\(valueKey) \(contextKey)"

        switch seed.canonicalName {
        case "Oil Change":
            return blockedOilPhrases.contains { combined.contains($0) }
        case "Home Air Filters":
            guard isAmbiguousFilterAliasKey(valueKey) else { return false }
            return blockedFilterPhrases.contains { combined.contains($0) }
        case "Domains":
            return blockedDomainPhrases.contains { combined.contains($0) }
        default:
            return false
        }
    }

    private static func contextualFilterSeed(valueKey: String, contextKey: String) -> ThingSeed? {
        guard isAmbiguousFilterAliasKey(valueKey) else { return nil }

        if containsAny(contextKey, [
            "cabin filter",
            "cabin air filter",
            "car cabin filter",
            "vehicle cabin filter",
            "auto cabin filter"
        ]) {
            return seed(named: "Cabin Air Filter")
        }

        if containsAny(contextKey, [
            "car air filter",
            "engine air filter",
            "vehicle air filter",
            "auto air filter",
            "automotive air filter"
        ]) {
            return seed(named: "Engine Air Filter")
        }

        if containsAny(contextKey, [
            "hvac filter",
            "furnace filter",
            "home air filter",
            "house filter",
            "return air filter",
            "vent filter"
        ]) {
            return seed(named: "Home Air Filters")
        }

        return nil
    }

    private static func containsAny(_ key: String, _ phrases: [String]) -> Bool {
        phrases.contains { key.contains($0) }
    }

    private static func seed(named name: String) -> ThingSeed? {
        seeds.first { $0.canonicalName == name }
    }

    private static let fillerWords: Set<String> = [
        "a",
        "again",
        "an",
        "another",
        "last",
        "new",
        "next",
        "old",
        "the",
        "today"
    ]

    private static let verbForms = [
        "bought": "buy",
        "buying": "buy",
        "changed": "change",
        "changing": "change",
        "called": "call",
        "calling": "call",
        "cleaned": "clean",
        "cleaning": "clean",
        "ordered": "order",
        "ordering": "order",
        "paid": "pay",
        "paying": "pay",
        "registered": "register",
        "registering": "register",
        "renewed": "renew",
        "renewing": "renew",
        "replaced": "replace",
        "replacing": "replace",
        "scheduled": "schedule",
        "scheduling": "schedule",
        "visited": "visit",
        "visiting": "visit",
        "went": "go",
        "going": "go"
    ]

    private static let acronymDisplayWords = [
        "api": "API",
        "hvac": "HVAC",
        "id": "ID",
        "nws": "NWS"
    ]

    private static let displaySurfacePassthroughWords: Set<String> = ["service"]

    private static let protectedProperNames: Set<String> = [
        "rutgers"
    ]

    private static let blockedOilPhrases = [
        "heating oil",
        "oil leak",
        "oil paint",
        "olive oil"
    ]

    private static let blockedFilterPhrases = [
        "cabin air filter",
        "cabin filter",
        "car air filter",
        "engine air filter",
        "vehicle air filter",
        "coffee filter",
        "pool filter",
        "water filter"
    ]

    private static let blockedDomainPhrases = [
        "claim domain",
        "claims domain",
        "domain model",
        "math domain",
        "work domain"
    ]

    static let seeds = [
        ThingSeed(
            canonicalName: "Oil Change",
            canonicalKey: "oil change",
            category: .maintenance,
            aliases: [
                "oil change",
                "change oil",
                "changed oil",
                "changing oil",
                "oil changed",
                "engine oil",
                "engine oil change",
                "car oil change",
                "car oil changed"
            ]
        ),
        ThingSeed(
            canonicalName: "Home Air Filters",
            canonicalKey: "home air filter",
            category: .home,
            aliases: [
                "home air filter",
                "home air filters",
                "hvac filter",
                "hvac filters",
                "furnace filter",
                "furnace filters",
                "house filter",
                "house filters",
                "return air filter",
                "return air filters",
                "vent filter",
                "vent filters"
            ]
        ),
        ThingSeed(
            canonicalName: "Engine Air Filter",
            canonicalKey: "engine air filter",
            category: .maintenance,
            aliases: [
                "engine air filter",
                "engine air filters",
                "car air filter",
                "car air filters",
                "vehicle air filter",
                "vehicle air filters",
                "auto air filter",
                "auto air filters",
                "automotive air filter",
                "automotive air filters"
            ]
        ),
        ThingSeed(
            canonicalName: "Cabin Air Filter",
            canonicalKey: "cabin air filter",
            category: .maintenance,
            aliases: [
                "cabin air filter",
                "cabin air filters",
                "cabin filter",
                "cabin filters",
                "car cabin filter",
                "car cabin filters",
                "vehicle cabin filter",
                "vehicle cabin filters",
                "auto cabin filter",
                "auto cabin filters"
            ]
        ),
        ThingSeed(
            canonicalName: "Domains",
            canonicalKey: "domain",
            category: .purchase,
            aliases: [
                "domain",
                "domains",
                "another domain",
                "buy domain",
                "buying domain",
                "buying domains",
                "domain purchase",
                "domain purchases",
                "register domain",
                "registering domains",
                "renew domain",
                "domain renewal"
            ]
        )
    ]
}

enum ThingAliasPolicy {
    static func cleanedAliases(_ aliases: [String], excludingName name: String) -> [String] {
        var seenKeys: Set<String> = []
        return cleanedAliases(aliases, excludingName: name, seenKeys: &seenKeys)
    }

    static func appendingAliases(_ aliases: [String], to existingAliases: [String], excludingName name: String) -> [String] {
        var seenKeys: Set<String> = []
        var cleanedExisting = cleanedAliases(existingAliases, excludingName: name, seenKeys: &seenKeys)
        cleanedExisting.append(contentsOf: cleanedAliases(aliases, excludingName: name, seenKeys: &seenKeys))
        return cleanedExisting
    }

    private static func cleanedAliases(_ aliases: [String], excludingName name: String, seenKeys: inout Set<String>) -> [String] {
        var cleanedAliases: [String] = []

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ThingNormalizer.normalizeKey(trimmed)
            guard !trimmed.isEmpty,
                  !key.isEmpty,
                  !isSurfaceEquivalent(trimmed, to: name),
                  !seenKeys.contains(key) else {
                continue
            }
            cleanedAliases.append(trimmed)
            seenKeys.insert(key)
        }

        return cleanedAliases
    }

    private static func isSurfaceEquivalent(_ alias: String, to name: String) -> Bool {
        surfaceKey(alias) == surfaceKey(name)
    }

    private static func surfaceKey(_ value: String) -> String {
        LedgerTextMatching.normalizedAlphanumericText(value)
    }
}
