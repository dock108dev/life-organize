import Foundation

enum LedgerTextMatching {
    static func normalizedAlphanumericText(_ value: String, foldingDiacritics: Bool = false) -> String {
        let normalized = foldingDiacritics
            ? value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            : value.lowercased()
        let characters = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
                ? Character(scalar)
                : " "
        }
        return String(characters)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func expandedTargetKeys(for targetKey: String, rawQuery: String) -> Set<String> {
        var keys = Set([targetKey].filter { !$0.isEmpty })
        if let seed = ThingNormalizer.seed(for: targetKey, contextText: rawQuery) {
            keys.formUnion(seed.matchKeys)
            keys.insert(seed.canonicalKey)
            keys.insert(ThingNormalizer.normalizeKey(seed.canonicalName))
        }
        return keys
    }

    static func thingMatches(_ thing: Thing, targetKeys: Set<String>, targetTokens: Set<String>) -> Bool {
        let candidateKeys = thingKeys(for: thing)
        if !candidateKeys.isDisjoint(with: targetKeys) {
            return true
        }

        return candidateKeys.contains { candidateKey in
            tokenMatch(targetTokens, tokens(in: candidateKey))
        }
    }

    static func thingKeys(for thing: Thing) -> Set<String> {
        var keys = Set(
            ([thing.normalizedKey, ThingNormalizer.normalizeKey(thing.name)] + thing.aliases.map(ThingNormalizer.normalizeKey))
                .filter { !$0.isEmpty }
        )

        for seed in ThingNormalizer.seeds where seed.canonicalName == thing.name || seed.canonicalKey == thing.normalizedKey {
            keys.formUnion(seed.matchKeys)
            keys.insert(seed.canonicalKey)
        }

        return keys
    }

    static func textMatches(_ candidateKey: String, targetKeys: Set<String>, targetTokens: Set<String>) -> Bool {
        guard !candidateKey.isEmpty else { return false }
        if targetKeys.contains(candidateKey) {
            return true
        }
        if targetKeys.contains(where: { key in
            containsWholePhrase(candidateKey, key) || containsWholePhrase(key, candidateKey)
        }) {
            return true
        }
        return tokenMatch(targetTokens, tokens(in: candidateKey))
    }

    static func containsWholePhrase(_ text: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        return text == phrase || text.hasPrefix("\(phrase) ") || text.hasSuffix(" \(phrase)") || text.contains(" \(phrase) ")
    }

    static func tokenMatch(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs.count == 1 {
            return rhs.contains(lhs.first!) && lhs.first!.count > 2
        }
        return lhs.isSubset(of: rhs) || rhs.isSubset(of: lhs) || lhs == rhs
    }

    static func tokens(in key: String) -> Set<String> {
        Set(key.split(separator: " ").map(String.init))
    }
}
