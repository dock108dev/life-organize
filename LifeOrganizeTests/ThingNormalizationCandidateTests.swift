import SwiftData
import XCTest
@testable import LifeOrganize

final class ThingNormalizationCandidateTests: XCTestCase {
    @MainActor
    func testNormalizationCandidatesRankAcronymEvidenceWithoutUnsafeMerge() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let existing = Thing(name: "Nimbus Web Services", aliases: [], category: .work, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "NWS infra deploy is blocked.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(existing)
        context.insert(message)
        context.insert(attempt)

        let candidates = ThingNormalizer.candidates(
            for: "NWS",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [existing],
            modelConfidence: 0.86
        )
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidate.targetThingID, existing.id)
        XCTAssertEqual(candidate.tier, .medium)
        XCTAssertEqual(candidate.matchReason, .acronymVariant)
        XCTAssertEqual(candidate.sourceEvidence.first?.sourceText, "NWS")
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.targetCategory, .work)
        XCTAssertNotNil(candidate.ambiguityReason)
        XCTAssertFalse(candidate.allowsAutomaticMerge)

        let resolved = try resolver.resolve(
            name: "NWS",
            aliases: [],
            categoryHint: "work",
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.86
        )
        try context.save()

        let reviewItems = try context.fetch(FetchDescriptor<LedgerReviewItem>())
        XCTAssertNotEqual(resolved.id, existing.id)
        XCTAssertTrue(reviewItems.contains { item in
            item.kind == .normalizationCandidate
                && item.detail.contains("NWS may match Nimbus Web Services")
                && item.detail.contains("No items have been merged")
        })
    }

    @MainActor
    func testSeededSecurityAbbreviationsMergeIntoCanonicalThing() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let existing = Thing(name: "Vulnerabilities", category: .work, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "Review vulns and security issues.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(existing)
        context.insert(message)
        context.insert(attempt)

        let candidates = ThingNormalizer.candidates(
            for: "vulns",
            aliases: ["security issues"],
            categoryHint: "work",
            contextText: message.text,
            existingThings: [existing],
            modelConfidence: 0.7
        )
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.matchReason, .seedAlias)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.targetCategory, .work)
        XCTAssertNil(candidate.ambiguityReason)
        XCTAssertTrue(candidate.allowsAutomaticMerge)

        let resolved = try resolver.resolve(
            name: "vulns",
            aliases: ["security issues"],
            categoryHint: "work",
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.7
        )
        try context.save()

        XCTAssertEqual(resolved.id, existing.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).filter { $0.kind == .normalizationCandidate }.count, 0)
    }

    @MainActor
    func testExactLearnedAliasesStillMergeAutomatically() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let existing = Thing(name: "Nimbus Web Services", aliases: ["NWS"], category: .work, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "NWS deploy went out.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(existing)
        context.insert(message)
        context.insert(attempt)

        let resolved = try resolver.resolve(
            name: "NWS",
            aliases: [],
            categoryHint: "work",
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.97
        )
        try context.save()

        XCTAssertEqual(resolved.id, existing.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerReviewItem>()).isEmpty)
    }

    @MainActor
    func testFilterBlockersStaleTargetsAndNoMatchReturnNoCandidates() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let filters = Thing(name: "Home Air Filters", normalizedKey: "home air filter", category: .home, createdAt: now, updatedAt: now)

        context.insert(filters)
        try context.save()

        XCTAssertNil(ThingNormalizer.seed(for: "filter blockers", contextText: "Filter blockers for saved searches."))
        XCTAssertTrue(ThingNormalizer.candidates(
            for: "filter blockers",
            categoryHint: "work",
            contextText: "Filter blockers for saved searches.",
            existingThings: [filters]
        ).isEmpty)
        XCTAssertTrue(ThingNormalizer.candidates(
            for: "garden hose",
            contextText: "Bought a garden hose.",
            existingThings: [filters]
        ).isEmpty)

        context.delete(filters)
        try context.save()

        XCTAssertTrue(ThingNormalizer.candidates(
            for: "HVAC filter",
            contextText: "Replaced HVAC filter.",
            existingThings: try context.fetch(FetchDescriptor<Thing>())
        ).allSatisfy { $0.targetThingID != filters.id })
    }

    @MainActor
    func testCategoryConflictCreatesReviewInsteadOfExactNameMerge() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let existing = Thing(name: "Filter", category: .homeMaintenance, createdAt: now, updatedAt: now)
        let message = ChatMessage(role: .user, text: "Filter blockers for a work saved search project.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(existing)
        context.insert(message)
        context.insert(attempt)

        let candidate = try XCTUnwrap(ThingNormalizer.candidates(
            for: "Filter",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [existing]
        ).first)

        XCTAssertEqual(candidate.matchReason, .exactName)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertTrue(candidate.sourceEvidence.first?.categoryEvidence?.hasConflict == true)
        XCTAssertFalse(candidate.allowsAutomaticMerge)

        let resolved = try resolver.resolve(
            name: "Filter",
            aliases: [],
            categoryHint: "work",
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.97
        )
        try context.save()

        XCTAssertNotEqual(resolved.id, existing.id)
        XCTAssertEqual(resolved.category, .work)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).filter { $0.kind == .normalizationCandidate }.count, 1)
    }

    @MainActor
    func testProjectActionAmbiguityStaysReviewOnly() throws {
        let existing = Thing(name: "Forge Deploy", category: .project, createdAt: fixedTestNow, updatedAt: fixedTestNow)
        let candidates = ThingNormalizer.candidates(
            for: "forge deployment",
            categoryHint: "work",
            eventTypeHint: "project",
            contextText: "Work deploy action for the forge project.",
            existingThings: [existing],
            modelConfidence: 0.88
        )
        let candidate = try XCTUnwrap(candidates.first)

        XCTAssertEqual(candidate.targetThingID, existing.id)
        XCTAssertEqual(candidate.matchReason, .tokenOverlap)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.eventTypeCategory, .project)
        XCTAssertEqual(candidate.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertNotNil(candidate.ambiguityReason)
        XCTAssertFalse(candidate.allowsAutomaticMerge)
    }

    func testCategoryEvidenceMapsOperationalExamples() {
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "work",
            contextText: "Review security vulns in NWS infra.",
            sourceValues: ["security issues"]
        ).primaryCategory, .work)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "unknown",
            eventTypeHint: "maintenance",
            contextText: "Serviced the car at 45000 miles.",
            sourceValues: ["Subaru service"]
        ).primaryCategory, .vehicle)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "food",
            eventTypeHint: "purchase",
            contextText: "Bought dog food for Luna.",
            sourceValues: ["dog food"]
        ).primaryCategory, .pet)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "home_maintenance",
            eventTypeHint: "replacement",
            contextText: "Replaced the HVAC air filter.",
            sourceValues: ["air filter"]
        ).primaryCategory, .homeMaintenance)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "unknown",
            eventTypeHint: "renewal",
            contextText: "Monthly subscription renewal posted.",
            sourceValues: ["streaming plan"]
        ).primaryCategory, .subscription)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "purchase",
            eventTypeHint: "purchase",
            contextText: "Paid vendor receipt for office chair.",
            sourceValues: ["office chair"]
        ).primaryCategory, .purchase)
        XCTAssertEqual(ThingNormalizer.categoryEvidence(
            categoryHint: "project",
            eventTypeHint: "project",
            contextText: "Project roadmap milestone moved.",
            sourceValues: ["launch project"]
        ).primaryCategory, .project)
    }
}
