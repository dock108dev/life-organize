import SwiftData
import XCTest
@testable import LifeOrganize

final class ThingIdentityContinuityTests: XCTestCase {
    private enum IdentityOutcome {
        case automaticMerge
        case newSeededThing
        case newDistinctThing
        case reviewCandidate
    }

    private struct IdentityScenario {
        var inputName: String
        var aliases: [String] = []
        var categoryHint: String?
        var eventTypeHint: String?
        var contextText: String
        var existingThings: [Thing] = []
        var expectedOutcome: IdentityOutcome
        var expectedName: String
        var expectedNormalizedKey: String
        var expectedCategory: ThingCategory?
    }

    func testExtractionCategoryMappingCoversSchemaTaxonomy() {
        let expectedMappings: [(String, ThingCategory)] = [
            ("home_maintenance", .homeMaintenance),
            ("vehicle", .vehicle),
            ("subscription", .subscription),
            ("project", .project),
            ("place", .place),
            ("person", .person),
            ("pet", .pet),
            ("food", .food),
            ("travel", .travel),
            ("rule_topic", .ruleTopic),
            ("other", .other),
            ("unknown", .other)
        ]

        for (rawValue, category) in expectedMappings {
            XCTAssertEqual(ThingCategory.fromExtractionCategory(rawValue), category, rawValue)
        }
        XCTAssertEqual(ThingCategory.fromExtractionCategory(" Home-Maintenance "), .homeMaintenance)
        XCTAssertNil(ThingCategory.fromExtractionCategory(nil))
    }

    @MainActor
    func testSingleMessageRecordsShareThingsAcrossAliasesAndNormalizedNames() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Bowling", category: "other"),
                            canonicalThing("thing_2", name: "Car", category: "vehicle"),
                            canonicalThing("thing_3", name: "HVAC Filter", category: "home_maintenance")
                        ],
                        events: [
                            canonicalEvent("event_1", title: "Bowling night", thingRef: "thing_1", occurredAt: "2027-01-15"),
                            canonicalEvent("event_2", title: "Changed car oil", thingRef: "thing_2", occurredAt: "2027-01-15"),
                            canonicalEvent("event_3", title: "Replaced HVAC filter", thingRef: "thing_3", occurredAt: "2027-01-15")
                        ],
                        rules: [
                            canonicalRule("rule_1", title: "Reevaluate bowling", thingRef: "thing_1", startsAt: "2027-04-15", expiresAt: nil, ruleType: "reminder"),
                            canonicalRule("rule_2", title: "Schedule car inspection", thingRef: "thing_2", startsAt: "2027-02-15", expiresAt: nil, ruleType: "reminder"),
                            canonicalRule("rule_3", title: "Replace home air filters", thingRef: "thing_3", startsAt: "2027-03-15", expiresAt: nil, ruleType: "reminder")
                        ],
                        notes: [
                            canonicalNote("note_1", text: "Bowling shoes are in the hall closet.", linkedThingRefs: ["thing_1"]),
                            canonicalNote("note_2", text: "Car insurance card is in the glove box.", linkedThingRefs: ["thing_2"]),
                            canonicalNote("note_3", text: "Home air filters are 20x20x1.", linkedThingRefs: ["thing_3"])
                        ],
                        aliases: [
                            canonicalAlias("thing_1", alias: "League Bowling"),
                            canonicalAlias("thing_2", alias: "Honda"),
                            canonicalAlias("thing_3", alias: "Home Air Filters")
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Bowling, car, and home air filter updates.")

        let things = try context.fetch(FetchDescriptor<Thing>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())
        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let bowling = try XCTUnwrap(things.first { $0.name == "Bowling" })
        let car = try XCTUnwrap(things.first { $0.name == "Car" })
        let filters = try XCTUnwrap(things.first { $0.name == "Home Air Filters" })

        XCTAssertEqual(things.count, 3)
        XCTAssertEqual(car.category, .vehicle)
        XCTAssertEqual(filters.category, .home)
        XCTAssertEqual(events.first { $0.title == "Bowling night" }?.thing?.id, bowling.id)
        XCTAssertEqual(rules.first { $0.title == "Reevaluate bowling" }?.thing?.id, bowling.id)
        XCTAssertEqual(notes.first { $0.text.contains("Bowling shoes") }?.linkedThings.map(\.id), [bowling.id])
        XCTAssertEqual(events.first { $0.title == "Changed car oil" }?.thing?.id, car.id)
        XCTAssertEqual(rules.first { $0.title == "Schedule car inspection" }?.thing?.id, car.id)
        XCTAssertEqual(notes.first { $0.text.contains("insurance card") }?.linkedThings.map(\.id), [car.id])
        XCTAssertEqual(events.first { $0.title == "Replaced HVAC filter" }?.thing?.id, filters.id)
        XCTAssertEqual(rules.first { $0.title == "Replace home air filters" }?.thing?.id, filters.id)
        XCTAssertEqual(notes.first { $0.text.contains("20x20x1") }?.linkedThings.map(\.id), [filters.id])
        XCTAssertEqual(links.filter { $0.relation == .extractedFrom }.count, 9)
        XCTAssertEqual(links.filter { $0.relation == .primaryThing }.count, 6)
        XCTAssertEqual(links.filter { $0.relation == .aboutThing }.count, 3)
        XCTAssertTrue(links.allSatisfy { $0.sourceMessageID == userMessage.id })
    }

    @MainActor
    func testSeededScenarioIdentityOutcomesAreClassifiedWithoutDuplicateDrift() throws {
        let scenarios = [
            IdentityScenario(
                inputName: "Changed oil",
                contextText: "Changed oil on the car today.",
                existingThings: [seedThing(named: "Oil Change")],
                expectedOutcome: .automaticMerge,
                expectedName: "Oil Change",
                expectedNormalizedKey: "oil change",
                expectedCategory: .maintenance
            ),
            IdentityScenario(
                inputName: "HVAC Filter",
                categoryHint: "home_maintenance",
                contextText: "Replaced HVAC filter in hallway.",
                existingThings: [seedThing(named: "Home Air Filters")],
                expectedOutcome: .automaticMerge,
                expectedName: "Home Air Filters",
                expectedNormalizedKey: "home air filter",
                expectedCategory: .home
            ),
            IdentityScenario(
                inputName: "Car air filter",
                categoryHint: "vehicle",
                contextText: "Changed car air filter.",
                existingThings: [seedThing(named: "Engine Air Filter")],
                expectedOutcome: .automaticMerge,
                expectedName: "Engine Air Filter",
                expectedNormalizedKey: "engine air filter",
                expectedCategory: .maintenance
            ),
            IdentityScenario(
                inputName: "Register domain",
                eventTypeHint: "purchase",
                contextText: "Register domain for new project.",
                expectedOutcome: .newSeededThing,
                expectedName: "Domains",
                expectedNormalizedKey: "domain",
                expectedCategory: .purchase
            ),
            IdentityScenario(
                inputName: "Coffee filter",
                contextText: "Bought coffee filters.",
                existingThings: [seedThing(named: "Home Air Filters")],
                expectedOutcome: .newDistinctThing,
                expectedName: "Coffee Filter",
                expectedNormalizedKey: "coffee filter",
                expectedCategory: .food
            ),
            IdentityScenario(
                inputName: "NWS",
                categoryHint: "work",
                contextText: "NWS infra deploy is blocked.",
                existingThings: [Thing(name: "Nimbus Web Services", category: .work)],
                expectedOutcome: .reviewCandidate,
                expectedName: "NWS",
                expectedNormalizedKey: "nws",
                expectedCategory: .work
            ),
            IdentityScenario(
                inputName: "vulns",
                aliases: ["security issues"],
                categoryHint: "work",
                contextText: "Review vulns and security issues.",
                existingThings: [Thing(name: "Vulnerabilities", category: .work)],
                expectedOutcome: .reviewCandidate,
                expectedName: "Vuln",
                expectedNormalizedKey: "vuln",
                expectedCategory: .work
            ),
            IdentityScenario(
                inputName: "Filter",
                categoryHint: "work",
                contextText: "Filter blockers for a work saved search project.",
                existingThings: [Thing(name: "Filter", category: .homeMaintenance)],
                expectedOutcome: .reviewCandidate,
                expectedName: "Filter",
                expectedNormalizedKey: "filter",
                expectedCategory: .work
            ),
            IdentityScenario(
                inputName: "Air filter",
                contextText: "Ordered air filter.",
                existingThings: [
                    seedThing(named: "Home Air Filters"),
                    seedThing(named: "Engine Air Filter"),
                    seedThing(named: "Cabin Air Filter")
                ],
                expectedOutcome: .reviewCandidate,
                expectedName: "Air Filter",
                expectedNormalizedKey: "air filter",
                expectedCategory: .homeMaintenance
            )
        ]

        for scenario in scenarios {
            let result = try runIdentityScenario(scenario)

            assertIdentityScenario(result, matches: scenario)
            XCTAssertEqual(result.linkedEvent.thing?.id, result.resolvedThing.id, scenario.inputName)
            XCTAssertTrue(result.resolvedThing.sourceMessageIDs.contains(result.message.id), scenario.inputName)
            XCTAssertTrue(result.resolvedThing.sourceExtractionAttemptIDs.contains(result.attempt.id), scenario.inputName)
            XCTAssertTrue(result.attempt.createdEventIDs.contains(result.linkedEvent.id), scenario.inputName)
            if scenario.expectedOutcome != .reviewCandidate {
                XCTAssertFalse(result.reviewItems.contains { $0.kind == .duplicateThing }, scenario.inputName)
            }
        }
    }

    @MainActor
    func testReviewRefreshSurfacesDuplicateAndNormalizationCandidates() throws {
        let context = makeInMemoryModelContext()
        let canonicalFilters = seedThing(named: "Home Air Filters")
        let duplicateFilters = Thing(name: "HVAC Filter", category: .homeMaintenance)
        let needsNormalization = Thing(name: "changed oil", normalizedKey: "changed oil", category: .maintenance)

        [canonicalFilters, duplicateFilters, needsNormalization].forEach(context.insert)
        try context.save()

        let reviewItems = try reviewGenerationService(context).refresh()
        let duplicate = try XCTUnwrap(reviewItems.first { $0.kind == .duplicateThing })
        let normalization = try XCTUnwrap(reviewItems.first {
            $0.kind == .normalizationCandidate && $0.targetID == needsNormalization.id
        })

        XCTAssertEqual(duplicate.title, "Possible duplicate Things")
        XCTAssertTrue(duplicate.detail.contains("Home Air Filters"))
        XCTAssertTrue(duplicate.detail.contains("HVAC Filter"))
        XCTAssertEqual(duplicate.confidence, 0.8)
        XCTAssertEqual(duplicate.targetType, .thing)
        XCTAssertEqual(Set(duplicate.evidence.map(\.sourceID)), Set([canonicalFilters.id, duplicateFilters.id]))
        XCTAssertEqual(normalization.title, "Thing name is ready for review")
        XCTAssertTrue(normalization.detail.contains("Oil Change"))
        XCTAssertEqual(normalization.confidence, 0.75)
        XCTAssertEqual(normalization.targetType, .thing)
        XCTAssertEqual(normalization.evidence.first?.sourceID, needsNormalization.id)
    }

    private struct IdentityScenarioResult {
        var beforeCount: Int
        var afterThings: [Thing]
        var resolvedThing: Thing
        var linkedEvent: LedgerEvent
        var message: ChatMessage
        var attempt: ExtractionAttempt
        var reviewItems: [LedgerReviewItem]
    }

    @MainActor
    private func runIdentityScenario(_ scenario: IdentityScenario) throws -> IdentityScenarioResult {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(role: .user, text: scenario.contextText, createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        scenario.existingThings.forEach(context.insert)
        context.insert(message)
        context.insert(attempt)
        try context.save()

        let beforeCount = try context.fetch(FetchDescriptor<Thing>()).count
        let resolvedThing = try resolver.resolve(
            name: scenario.inputName,
            aliases: scenario.aliases,
            categoryHint: scenario.categoryHint,
            eventTypeHint: scenario.eventTypeHint,
            contextText: scenario.contextText,
            sourceMessage: message,
            attempt: attempt,
            modelConfidence: 0.95
        )
        let event = LedgerEvent(
            title: scenario.contextText,
            occurredAt: now,
            rawText: scenario.contextText,
            sourceExtractionRunID: attempt.id,
            thing: resolvedThing,
            sourceMessage: message
        )
        context.insert(event)
        attempt.createdEventIDs.append(event.id)
        try context.save()

        return IdentityScenarioResult(
            beforeCount: beforeCount,
            afterThings: try context.fetch(FetchDescriptor<Thing>()),
            resolvedThing: resolvedThing,
            linkedEvent: event,
            message: message,
            attempt: attempt,
            reviewItems: try reviewGenerationService(context).refresh()
        )
    }

    @MainActor
    private func assertIdentityScenario(
        _ result: IdentityScenarioResult,
        matches scenario: IdentityScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedCount = scenario.expectedOutcome == .automaticMerge
            ? result.beforeCount
            : result.beforeCount + 1

        XCTAssertEqual(result.afterThings.count, expectedCount, scenario.inputName, file: file, line: line)
        XCTAssertEqual(result.resolvedThing.name, scenario.expectedName, file: file, line: line)
        XCTAssertEqual(result.resolvedThing.normalizedKey, scenario.expectedNormalizedKey, file: file, line: line)
        XCTAssertEqual(result.resolvedThing.category, scenario.expectedCategory, file: file, line: line)
        XCTAssertEqual(
            result.afterThings.filter { $0.id == result.resolvedThing.id }.count,
            1,
            file: file,
            line: line
        )

        switch scenario.expectedOutcome {
        case .automaticMerge:
            XCTAssertTrue(scenario.existingThings.contains { $0.id == result.resolvedThing.id }, file: file, line: line)
            XCTAssertFalse(hasNormalizationCandidate(result.reviewItems), file: file, line: line)
        case .newSeededThing, .newDistinctThing:
            XCTAssertFalse(scenario.existingThings.contains { $0.id == result.resolvedThing.id }, file: file, line: line)
            XCTAssertFalse(hasNormalizationCandidate(result.reviewItems), file: file, line: line)
        case .reviewCandidate:
            XCTAssertFalse(scenario.existingThings.contains { $0.id == result.resolvedThing.id }, file: file, line: line)
            XCTAssertTrue(result.reviewItems.contains { item in
                item.kind == .normalizationCandidate
                    && item.targetID == result.resolvedThing.id
                    && item.detail.contains("may match")
                    && item.targetType == .thing
                    && item.evidence.filter { $0.sourceType == .thing }.count == 2
            }, scenario.inputName, file: file, line: line)
        }

        if scenario.expectedName == "Home Air Filters" || scenario.expectedName == "Engine Air Filter" || scenario.expectedName == "Cabin Air Filter" {
            XCTAssertFalse(result.resolvedThing.aliases.contains {
                ThingNormalizer.isAmbiguousFilterAliasKey(ThingNormalizer.normalizeKey($0))
            }, file: file, line: line)
        }
    }

    private func hasNormalizationCandidate(_ reviewItems: [LedgerReviewItem]) -> Bool {
        reviewItems.contains { $0.kind == .normalizationCandidate }
    }

    private func seedThing(named name: String) -> Thing {
        let seed = ThingNormalizer.seeds.first { $0.canonicalName == name }!
        return Thing(name: seed.canonicalName, normalizedKey: seed.canonicalKey, category: seed.category)
    }

    @MainActor
    private func reviewGenerationService(_ context: ModelContext) -> LedgerReviewItemGenerationService {
        LedgerReviewItemGenerationService(modelContext: context, now: { fixedTestNow })
    }
}
