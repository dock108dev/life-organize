import Foundation
import SwiftData

@MainActor
struct ThingResolver {
    let modelContext: ModelContext
    var now: () -> Date = { Date() }

    func resolve(
        name: String,
        aliases: [String],
        categoryHint: String? = nil,
        eventTypeHint: String? = nil,
        contextText: String,
        sourceMessage: ChatMessage,
        attempt: ExtractionAttempt,
        modelConfidence: Double? = nil
    ) throws -> Thing {
        let things = try modelContext.fetch(FetchDescriptor<Thing>())
        let candidates = ThingNormalizer.candidates(
            for: name,
            aliases: aliases,
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            existingThings: things,
            modelConfidence: modelConfidence
        )
        let seed = ([name] + aliases).compactMap {
            ThingNormalizer.seed(for: $0, contextText: contextText)
        }.first
        let displayName = seed?.canonicalName ?? ThingNormalizer.displayName(for: name, contextText: contextText)
        let category = seed?.category ?? ThingNormalizer.inferredCategory(
            categoryHint: categoryHint,
            eventTypeHint: eventTypeHint,
            contextText: contextText,
            sourceValues: [name] + aliases
        )
        let aliasValues = aliasCandidates(name: name, aliases: aliases, seed: seed)
        let candidateKeys = matchKeys(name: name, aliases: aliases, seed: seed)

        if let existing = automaticMatch(from: candidates, in: things)
            ?? things.first(where: {
                matches($0, candidateKeys: candidateKeys)
                    && !ThingNormalizer.hasCategoryConflict(
                        categoryHint: categoryHint,
                        eventTypeHint: eventTypeHint,
                        contextText: contextText,
                        sourceValues: [name] + aliases,
                        targetCategory: $0.category
                    )
            }) {
            mergeProvenance(into: existing, sourceMessage: sourceMessage, attempt: attempt)
            mergeCategory(category, into: existing)
            existing.registerAliases(aliasValues, updatedAt: now())
            if existing.normalizedKey.isEmpty {
                existing.normalizedKey = ThingNormalizer.normalizeKey(existing.name)
            }
            return existing
        }

        let thing = Thing(
            name: displayName,
            normalizedKey: seed?.canonicalKey ?? ThingNormalizer.normalizeKey(displayName),
            aliases: ThingAliasPolicy.cleanedAliases(aliasValues, excludingName: displayName),
            category: category,
            createdAt: now(),
            updatedAt: now(),
            sourceMessageIDs: [sourceMessage.id],
            sourceExtractionAttemptIDs: [attempt.id]
        )
        modelContext.insert(thing)
        try createReviewItemIfNeeded(
            for: thing,
            candidates: candidates,
            sourceMessage: sourceMessage,
            attempt: attempt,
            sourceName: name
        )
        return thing
    }

    private func automaticMatch(from candidates: [ThingNormalizationCandidate], in things: [Thing]) -> Thing? {
        guard let candidate = candidates.first(where: { $0.allowsAutomaticMerge }),
              let targetThingID = candidate.targetThingID else {
            return nil
        }
        return things.first { $0.id == targetThingID }
    }

    private func matches(_ thing: Thing, candidateKeys: Set<String>) -> Bool {
        let nameKey = thing.normalizedKey.isEmpty ? ThingNormalizer.normalizeKey(thing.name) : thing.normalizedKey
        if candidateKeys.contains(nameKey) {
            return true
        }

        return thing.aliases.contains { alias in
            candidateKeys.contains(ThingNormalizer.normalizeKey(alias))
        }
    }

    private func matchKeys(name: String, aliases: [String], seed: ThingSeed?) -> Set<String> {
        let rawKeys = ([name] + aliases).map(ThingNormalizer.normalizeKey)
        var keys = Set(rawKeys.filter { key in
            !key.isEmpty && (seed == nil || !ThingNormalizer.isAmbiguousFilterAliasKey(key))
        })
        if let seed {
            keys.formUnion(seed.matchKeys)
        }
        return keys
    }

    private func aliasCandidates(name: String, aliases: [String], seed: ThingSeed?) -> [String] {
        var values = ([name] + aliases).filter { value in
            seed == nil || !ThingNormalizer.isAmbiguousFilterAliasKey(ThingNormalizer.normalizeKey(value))
        }
        if let seed {
            values.append(contentsOf: seed.aliases)
        }
        return values
    }

    private func mergeProvenance(
        into thing: Thing,
        sourceMessage: ChatMessage,
        attempt: ExtractionAttempt
    ) {
        if !thing.sourceMessageIDs.contains(sourceMessage.id) {
            thing.sourceMessageIDs.append(sourceMessage.id)
        }
        if !thing.sourceExtractionAttemptIDs.contains(attempt.id) {
            thing.sourceExtractionAttemptIDs.append(attempt.id)
        }
    }

    private func mergeCategory(_ category: ThingCategory?, into thing: Thing) {
        guard let category, thing.category == nil || (thing.category == .other && category != .other) else {
            return
        }
        thing.category = category
    }

    private func createReviewItemIfNeeded(
        for thing: Thing,
        candidates: [ThingNormalizationCandidate],
        sourceMessage: ChatMessage,
        attempt: ExtractionAttempt,
        sourceName: String
    ) throws {
        guard let candidate = candidates.first(where: { !$0.allowsAutomaticMerge && $0.targetThingID != nil }),
              let targetThingID = candidate.targetThingID else {
            return
        }
        let dedupeKey = [
            LedgerReviewItemKind.normalizationCandidate.rawValue,
            thing.id.uuidString,
            targetThingID.uuidString,
            candidate.matchReason.rawValue,
        ].joined(separator: "|")
        let existingItems = try modelContext.fetch(FetchDescriptor<LedgerReviewItem>())
        guard !existingItems.contains(where: { $0.dedupeKey == dedupeKey }) else { return }

        let evidenceDetails = candidate.sourceEvidence.map { evidence in
            [
                "source: \(evidence.sourceText)",
                "source key: \(evidence.sourceKey)",
                "matched: \(evidence.matchedText)",
                "matched key: \(evidence.matchedKey)",
                evidence.modelConfidence.map { "model confidence: \(LedgerDisplayFormatting.percent($0))" },
            ].compactMap { $0 }.joined(separator: "; ")
        }
        let item = LedgerReviewItem(
            dedupeKey: dedupeKey,
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "\(sourceName) may match \(candidate.targetName). No records have been merged.",
            actionTitle: "Review Thing",
            targetType: .thing,
            targetID: thing.id,
            confidence: candidate.confidence,
            evidence: [
                LedgerReviewItemEvidence(
                    sourceType: .chatMessage,
                    sourceID: sourceMessage.id,
                    summary: sourceMessage.text,
                    detail: candidate.ambiguityReason ?? candidate.matchReason.rawValue
                ),
                LedgerReviewItemEvidence(
                    sourceType: .thing,
                    sourceID: thing.id,
                    summary: thing.name,
                    detail: "New Thing from extraction attempt \(attempt.id.uuidString)"
                ),
                LedgerReviewItemEvidence(
                    sourceType: .thing,
                    sourceID: targetThingID,
                    summary: candidate.targetName,
                    detail: evidenceDetails.joined(separator: " | ").nilIfEmpty
                ),
            ],
            createdAt: now(),
            updatedAt: now()
        )
        modelContext.insert(item)
    }

}
