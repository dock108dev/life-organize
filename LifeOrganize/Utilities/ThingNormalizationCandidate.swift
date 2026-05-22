import Foundation

enum ThingNormalizationConfidenceTier: String, Codable, Equatable {
    case high
    case medium
    case low
}

enum ThingNormalizationMatchReason: String, Codable, Equatable {
    case exactName = "exact_name"
    case seedAlias = "seed_alias"
    case learnedAlias = "learned_alias"
    case acronymVariant = "acronym_variant"
    case abbreviationVariant = "abbreviation_variant"
    case tokenOverlap = "token_overlap"
}

struct ThingNormalizationEvidence: Codable, Equatable {
    var sourceText: String
    var sourceKey: String
    var matchedText: String
    var matchedKey: String
    var categoryHint: String?
    var categoryEvidence: ThingNormalizationCategoryEvidence? = nil
    var modelConfidence: Double?
}

struct ThingNormalizationCandidate: Codable, Equatable {
    var targetThingID: UUID?
    var targetName: String
    var targetNormalizedKey: String
    var confidence: Double
    var tier: ThingNormalizationConfidenceTier
    var matchReason: ThingNormalizationMatchReason
    var sourceEvidence: [ThingNormalizationEvidence]
    var ambiguityReason: String?

    var allowsAutomaticMerge: Bool {
        tier == .high && ambiguityReason == nil
    }
}

extension ThingNormalizer {
    static func candidates(
        for name: String,
        aliases: [String] = [],
        categoryHint: String? = nil,
        eventTypeHint: String? = nil,
        contextText: String,
        existingThings: [Thing],
        modelConfidence: Double? = nil
    ) -> [ThingNormalizationCandidate] {
        let sourceValues = ([name] + aliases).compactMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !sourceValues.isEmpty else { return [] }

        let seeds = seedCandidates(
            sourceValues: sourceValues,
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            modelConfidence: modelConfidence
        )
        let thingCandidates = existingThings
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .flatMap { thing in
                candidates(
                    for: thing,
                    sourceValues: sourceValues,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence
                )
            }

        return rankedDedupedCandidates(seeds + thingCandidates)
    }

    private static func seedCandidates(
        sourceValues: [String],
        categoryHint: String?,
        eventTypeHint: String?,
        contextText: String,
        modelConfidence: Double?
    ) -> [ThingNormalizationCandidate] {
        sourceValues.compactMap { value in
            guard let seed = seed(for: value, contextText: contextText) else { return nil }
            let sourceKey = normalizeKey(value)
            let categoryEvidence = ThingNormalizer.categoryEvidence(
                categoryHint: categoryHint,
                eventTypeHint: eventTypeHint,
                contextText: contextText,
                sourceValues: [value],
                targetCategory: seed.category
            )
            let evidence = ThingNormalizationEvidence(
                sourceText: value,
                sourceKey: sourceKey,
                matchedText: seed.canonicalName,
                matchedKey: seed.canonicalKey,
                categoryHint: categoryHint,
                categoryEvidence: categoryEvidence,
                modelConfidence: modelConfidence
            )
            return ThingNormalizationCandidate(
                targetThingID: nil,
                targetName: seed.canonicalName,
                targetNormalizedKey: seed.canonicalKey,
                confidence: adjustedConfidence(base: 0.98, modelConfidence: modelConfidence),
                tier: .high,
                matchReason: .seedAlias,
                sourceEvidence: [evidence],
                ambiguityReason: nil
            )
        }
    }

    private static func candidates(
        for thing: Thing,
        sourceValues: [String],
        categoryHint: String?,
        eventTypeHint: String?,
        contextText: String,
        modelConfidence: Double?
    ) -> [ThingNormalizationCandidate] {
        let targetKeys = identityKeys(for: thing)
        let targetNameKey = thing.normalizedKey.nilIfEmpty ?? normalizeKey(thing.name)
        var candidates: [ThingNormalizationCandidate] = []

        for value in sourceValues {
            let sourceKey = normalizeKey(value)
            guard !sourceKey.isEmpty else { continue }
            if targetKeys.nameKeys.contains(sourceKey) {
                candidates.append(candidate(
                    thing: thing,
                    sourceText: value,
                    sourceKey: sourceKey,
                    matchedText: thing.name,
                    matchedKey: targetNameKey,
                    reason: .exactName,
                    baseConfidence: 1,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence
                ))
                continue
            }
            if let matchedAlias = targetKeys.aliases.first(where: { $0.key == sourceKey }) {
                candidates.append(candidate(
                    thing: thing,
                    sourceText: value,
                    sourceKey: sourceKey,
                    matchedText: matchedAlias.value,
                    matchedKey: matchedAlias.key,
                    reason: .learnedAlias,
                    baseConfidence: 0.96,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence
                ))
                continue
            }
            if let seed = matchingSeed(for: thing),
               seed.matchKeys.contains(sourceKey),
               !isBlocked(seed: seed, valueKey: sourceKey, contextKey: normalizeKey(contextText)) {
                candidates.append(candidate(
                    thing: thing,
                    sourceText: value,
                    sourceKey: sourceKey,
                    matchedText: seed.canonicalName,
                    matchedKey: seed.canonicalKey,
                    reason: .seedAlias,
                    baseConfidence: 0.98,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence
                ))
                continue
            }
            if let candidate = ambiguousFilterCandidate(
                for: thing,
                sourceText: value,
                sourceKey: sourceKey,
                categoryHint: categoryHint,
                eventTypeHint: eventTypeHint,
                contextText: contextText,
                modelConfidence: modelConfidence
            ) {
                candidates.append(candidate)
                continue
            }

            if let acronymScore = acronymMatchScore(sourceKey: sourceKey, targetKeys: targetKeys.allKeys) {
                candidates.append(candidate(
                    thing: thing,
                    sourceText: value,
                    sourceKey: sourceKey,
                    matchedText: thing.name,
                    matchedKey: targetNameKey,
                    reason: .acronymVariant,
                    baseConfidence: acronymScore,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence,
                    ambiguityReason: ambiguityReason(
                        sourceKey: sourceKey,
                        targetKey: targetNameKey,
                        categoryHint: categoryHint,
                        contextText: contextText,
                        reason: .acronymVariant
                    )
                ))
                continue
            }

            if let semanticScore = semanticMatchScore(sourceKey: sourceKey, targetKeys: targetKeys.allKeys) {
                let reason: ThingNormalizationMatchReason = containsAbbreviation(sourceKey) ? .abbreviationVariant : .tokenOverlap
                candidates.append(candidate(
                    thing: thing,
                    sourceText: value,
                    sourceKey: sourceKey,
                    matchedText: thing.name,
                    matchedKey: targetNameKey,
                    reason: reason,
                    baseConfidence: semanticScore,
                    categoryHint: categoryHint,
                    eventTypeHint: eventTypeHint,
                    contextText: contextText,
                    modelConfidence: modelConfidence,
                    ambiguityReason: ambiguityReason(
                        sourceKey: sourceKey,
                        targetKey: targetNameKey,
                        categoryHint: categoryHint,
                        contextText: contextText,
                        reason: reason
                    )
                ))
            }
        }

        return candidates
    }

    private static func ambiguousFilterCandidate(
        for thing: Thing,
        sourceText: String,
        sourceKey: String,
        categoryHint: String?,
        eventTypeHint: String?,
        contextText: String,
        modelConfidence: Double?
    ) -> ThingNormalizationCandidate? {
        guard isAmbiguousFilterAliasKey(sourceKey),
              let seed = matchingSeed(for: thing),
              ["Home Air Filters", "Engine Air Filter", "Cabin Air Filter"].contains(seed.canonicalName),
              !isBlocked(seed: seed, valueKey: sourceKey, contextKey: normalizeKey(contextText)) else {
            return nil
        }
        return candidate(
            thing: thing,
            sourceText: sourceText,
            sourceKey: sourceKey,
            matchedText: seed.canonicalName,
            matchedKey: seed.canonicalKey,
            reason: .tokenOverlap,
            baseConfidence: 0.6,
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            modelConfidence: modelConfidence,
            ambiguityReason: "Filter wording needs review before matching a saved filter Thing."
        )
    }

    private static func candidate(
        thing: Thing,
        sourceText: String,
        sourceKey: String,
        matchedText: String,
        matchedKey: String,
        reason: ThingNormalizationMatchReason,
        baseConfidence: Double,
        categoryHint: String?,
        eventTypeHint: String?,
        contextText: String,
        modelConfidence: Double?,
        ambiguityReason: String? = nil
    ) -> ThingNormalizationCandidate {
        let score = adjustedConfidence(base: baseConfidence, modelConfidence: modelConfidence)
        let categoryEvidence = ThingNormalizer.categoryEvidence(
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            sourceValues: [sourceText],
            targetCategory: thing.category
        )
        return ThingNormalizationCandidate(
            targetThingID: thing.id,
            targetName: thing.name,
            targetNormalizedKey: matchedKey,
            confidence: score,
            tier: tier(for: score),
            matchReason: reason,
            sourceEvidence: [
                ThingNormalizationEvidence(
                    sourceText: sourceText,
                    sourceKey: sourceKey,
                    matchedText: matchedText,
                    matchedKey: matchedKey,
                    categoryHint: categoryHint,
                    categoryEvidence: categoryEvidence,
                    modelConfidence: modelConfidence
                ),
            ],
            ambiguityReason: categoryAmbiguityReason(categoryEvidence) ?? ambiguityReason
        )
    }

    private static func rankedDedupedCandidates(_ candidates: [ThingNormalizationCandidate]) -> [ThingNormalizationCandidate] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            candidate.targetThingID?.uuidString ?? candidate.targetNormalizedKey
        }
        let best = grouped.values.compactMap { group in
            group.sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.targetName.localizedCaseInsensitiveCompare(rhs.targetName) == .orderedAscending
            }.first
        }
        let sorted = best.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.targetName.localizedCaseInsensitiveCompare(rhs.targetName) == .orderedAscending
        }
        guard let first = sorted.first else { return [] }
        return sorted.map { candidate in
            guard candidate.targetThingID != first.targetThingID,
                  first.confidence - candidate.confidence < 0.12,
                  candidate.ambiguityReason == nil else {
                return candidate
            }
            var ambiguous = candidate
            ambiguous.ambiguityReason = "Multiple saved Things are plausible matches."
            return ambiguous
        }
    }

    private static func identityKeys(for thing: Thing) -> (
        nameKeys: Set<String>,
        aliases: [(value: String, key: String)],
        allKeys: Set<String>
    ) {
        let nameKeys = Set([thing.normalizedKey, normalizeKey(thing.name)].filter { !$0.isEmpty })
        let aliases = thing.aliases.map { (value: $0, key: normalizeKey($0)) }.filter { !$0.key.isEmpty }
        return (nameKeys, aliases, nameKeys.union(aliases.map(\.key)))
    }

    private static func matchingSeed(for thing: Thing) -> ThingSeed? {
        seeds.first { seed in
            thing.name == seed.canonicalName || thing.normalizedKey == seed.canonicalKey
        }
    }

    private static func acronymMatchScore(sourceKey: String, targetKeys: Set<String>) -> Double? {
        for targetKey in targetKeys {
            guard targetKey != sourceKey else { continue }
            let targetAcronym = acronym(for: targetKey)
            let sourceAcronym = acronym(for: sourceKey)
            if sourceKey == targetAcronym || targetKey == sourceAcronym {
                return 0.72
            }
        }
        return nil
    }

    private static func acronym(for key: String) -> String {
        key.split(separator: " ").compactMap(\.first).map(String.init).joined()
    }

    private static func semanticMatchScore(sourceKey: String, targetKeys: Set<String>) -> Double? {
        let sourceTokens = expandedTokens(in: sourceKey)
        guard !sourceTokens.isEmpty else { return nil }
        return targetKeys.compactMap { targetKey -> Double? in
            let targetTokens = expandedTokens(in: targetKey)
            let overlap = sourceTokens.intersection(targetTokens)
            guard !overlap.isEmpty else { return nil }
            if sourceTokens == targetTokens {
                return 0.7
            }
            if overlap.contains("security") && (overlap.contains("issue") || overlap.contains("vulnerability")) {
                return 0.68
            }
            if overlap.contains("cloud"), sourceTokens.intersection(targetTokens).count >= 2 {
                return 0.62
            }
            guard !overlap.isDisjoint(with: semanticReviewTokens) else { return nil }
            let smaller = max(1, min(sourceTokens.count, targetTokens.count))
            let ratio = Double(overlap.count) / Double(smaller)
            return ratio >= 0.5 ? 0.55 + min(0.1, ratio * 0.1) : nil
        }.max()
    }

    private static func expandedTokens(in key: String) -> Set<String> {
        key.split(separator: " ").reduce(into: Set<String>()) { result, token in
            let value = String(token)
            result.insert(value)
            semanticExpansions[value, default: []].forEach { result.insert($0) }
        }
    }

    private static func containsAbbreviation(_ key: String) -> Bool {
        key.split(separator: " ").contains { semanticAbbreviations.contains(String($0)) }
    }

    private static func ambiguityReason(
        sourceKey: String,
        targetKey: String,
        categoryHint: String?,
        contextText: String,
        reason: ThingNormalizationMatchReason
    ) -> String? {
        let combined = [sourceKey, targetKey, normalizeKey(categoryHint ?? ""), normalizeKey(contextText)].joined(separator: " ")
        if broadReviewTokens.contains(where: { combined.contains($0) }) {
            return "Broad work, security, cloud, or project language needs review before merging."
        }
        switch reason {
        case .exactName, .seedAlias, .learnedAlias:
            return nil
        case .acronymVariant, .abbreviationVariant, .tokenOverlap:
            return "Match is based on inferred wording rather than an exact saved alias."
        }
    }

    private static func categoryAmbiguityReason(_ evidence: ThingNormalizationCategoryEvidence) -> String? {
        evidence.hasConflict ? "Category evidence conflicts with the saved Thing category." : nil
    }

    private static func adjustedConfidence(base: Double, modelConfidence: Double?) -> Double {
        guard let modelConfidence else { return base }
        return min(base, (base * 0.8) + (max(0, min(modelConfidence, 1)) * 0.2))
    }

    private static func tier(for confidence: Double) -> ThingNormalizationConfidenceTier {
        if confidence >= 0.9 { return .high }
        if confidence >= 0.55 { return .medium }
        return .low
    }

    private static let semanticAbbreviations: Set<String> = ["infra", "vuln"]

    private static let semanticExpansions: [String: Set<String>] = [
        "cloud": ["cloud"],
        "deploy": ["deploy", "project"],
        "deployment": ["deploy", "project"],
        "infra": ["cloud", "infrastructure"],
        "infrastructure": ["cloud", "infrastructure"],
        "issue": ["issue", "security"],
        "project": ["project"],
        "security": ["security"],
        "service": ["cloud", "service"],
        "vuln": ["issue", "security", "vulnerability"],
        "vulnerability": ["issue", "security", "vulnerability"],
        "web": ["cloud", "web"],
    ]

    private static let broadReviewTokens = [
        "cloud",
        "deploy",
        "infra",
        "infrastructure",
        "project",
        "security",
        "service",
        "vuln",
        "vulnerability",
        "work",
    ]

    private static let semanticReviewTokens: Set<String> = Set(broadReviewTokens + ["issue"])
}
