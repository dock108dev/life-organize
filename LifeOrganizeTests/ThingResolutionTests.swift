import SwiftData
import XCTest
@testable import LifeOrganize

final class ThingResolutionTests: XCTestCase {
    @MainActor
    func testNormalizerBuildsStableMatchKeys() {
        XCTAssertEqual(ThingNormalizer.normalizeKey("Changed oil!"), "change oil")
        XCTAssertEqual(ThingNormalizer.normalizeKey("changing the oil"), "change oil")
        XCTAssertEqual(ThingNormalizer.normalizeKey("air filters"), "air filter")
        XCTAssertEqual(ThingNormalizer.normalizeKey("HVAC filter"), "hvac filter")
        XCTAssertEqual(ThingNormalizer.normalizeKey("car air filters"), "car air filter")
        XCTAssertEqual(ThingNormalizer.normalizeKey("cabin filters"), "cabin filter")
        XCTAssertEqual(ThingNormalizer.normalizeKey("engine air filters"), "engine air filter")
        XCTAssertEqual(ThingNormalizer.normalizeKey("another domain"), "domain")
        XCTAssertEqual(ThingNormalizer.normalizeKey("buying domains"), "buy domain")
        XCTAssertEqual(ThingNormalizer.normalizeKey("Rutgers Football"), "rutgers football")
    }

    @MainActor
    func testDisplayNameUsesExplicitAcronymPolicy() {
        XCTAssertEqual(ThingNormalizer.displayName(for: "NWS"), "NWS")
        XCTAssertEqual(ThingNormalizer.displayName(for: "nws infra"), "NWS Infra")
        XCTAssertEqual(ThingNormalizer.displayName(for: "Nimbus Web Services"), "Nimbus Web Services")
        XCTAssertEqual(ThingNormalizer.displayName(for: "HVAC filter"), "Home Air Filters")
    }

    @MainActor
    func testFilterSeedsUseContextWithoutMergingUnrelatedFilters() {
        XCTAssertEqual(
            ThingNormalizer.seed(for: "HVAC filter", contextText: "Replaced HVAC filter")?.canonicalName,
            "Home Air Filters"
        )
        XCTAssertEqual(
            ThingNormalizer.seed(for: "air filter", contextText: "Replaced HVAC filter")?.canonicalName,
            "Home Air Filters"
        )
        XCTAssertEqual(
            ThingNormalizer.seed(for: "car air filter", contextText: "Changed car air filter")?.canonicalName,
            "Engine Air Filter"
        )
        XCTAssertEqual(
            ThingNormalizer.seed(for: "air filter", contextText: "Changed car air filter")?.canonicalName,
            "Engine Air Filter"
        )
        XCTAssertEqual(
            ThingNormalizer.seed(for: "cabin filter", contextText: "Changed cabin filter")?.canonicalName,
            "Cabin Air Filter"
        )
        XCTAssertEqual(
            ThingNormalizer.seed(for: "filter", contextText: "Changed cabin filter")?.canonicalName,
            "Cabin Air Filter"
        )
        XCTAssertNil(ThingNormalizer.seed(for: "coffee filter", contextText: "Bought coffee filters"))
    }

    @MainActor
    func testResolverMatchesNamesAliasesAndSeedSynonyms() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(role: .user, text: "Changed oil and replaced HVAC filter.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(message)
        context.insert(attempt)

        let changedOil = try resolver.resolve(
            name: "changed oil",
            aliases: [],
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt
        )
        let oilChange = try resolver.resolve(
            name: "Oil Change",
            aliases: [],
            contextText: "Oil change was done.",
            sourceMessage: message,
            attempt: attempt
        )
        let domains = try resolver.resolve(
            name: "domains",
            aliases: [],
            contextText: "No buying domains for 30 days.",
            sourceMessage: message,
            attempt: attempt
        )
        let anotherDomain = try resolver.resolve(
            name: "another domain",
            aliases: [],
            contextText: "Can I buy another domain?",
            sourceMessage: message,
            attempt: attempt
        )
        let airFilter = try resolver.resolve(
            name: "air filter",
            aliases: [],
            contextText: "Replaced the HVAC filter today.",
            sourceMessage: message,
            attempt: attempt
        )
        let hvacFilter = try resolver.resolve(
            name: "HVAC filter",
            aliases: [],
            contextText: "Replaced the HVAC filter today.",
            sourceMessage: message,
            attempt: attempt
        )
        let carAirFilter = try resolver.resolve(
            name: "car air filter",
            aliases: [],
            contextText: "Changed the car air filter.",
            sourceMessage: message,
            attempt: attempt
        )

        try context.save()

        XCTAssertEqual(changedOil.id, oilChange.id)
        XCTAssertEqual(changedOil.name, "Oil Change")
        XCTAssertEqual(changedOil.normalizedKey, "oil change")
        XCTAssertEqual(domains.id, anotherDomain.id)
        XCTAssertEqual(domains.name, "Domains")
        XCTAssertEqual(airFilter.id, hvacFilter.id)
        XCTAssertEqual(airFilter.name, "Home Air Filters")
        XCTAssertNotEqual(airFilter.id, carAirFilter.id)
        XCTAssertEqual(carAirFilter.name, "Engine Air Filter")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 4)
    }

    @MainActor
    func testResolverSeparatesVehicleHomeCoffeeAndOilFilterConcepts() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(
            role: .user,
            text: "Changed cabin filter, changed car air filter, replaced HVAC filter, bought coffee filters, and changed oil.",
            createdAt: now
        )
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })

        context.insert(message)
        context.insert(attempt)

        let cabinFilter = try resolver.resolve(
            name: "cabin filter",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed cabin filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let cabinAirFilter = try resolver.resolve(
            name: "cabin air filter",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed cabin air filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let broadCabinFilter = try resolver.resolve(
            name: "filter",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed cabin filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let carAirFilter = try resolver.resolve(
            name: "air filter",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed car air filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let engineAirFilter = try resolver.resolve(
            name: "engine air filter",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed engine air filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let hvacFilter = try resolver.resolve(
            name: "air filter",
            aliases: [],
            categoryHint: "home",
            contextText: "Replaced HVAC filter.",
            sourceMessage: message,
            attempt: attempt
        )
        let coffeeFilter = try resolver.resolve(
            name: "coffee filter",
            aliases: [],
            contextText: "Bought coffee filters.",
            sourceMessage: message,
            attempt: attempt
        )
        let oilChange = try resolver.resolve(
            name: "car oil change",
            aliases: [],
            categoryHint: "vehicle",
            contextText: "Changed car oil.",
            sourceMessage: message,
            attempt: attempt
        )

        try context.save()

        XCTAssertEqual(cabinFilter.id, cabinAirFilter.id)
        XCTAssertEqual(cabinFilter.id, broadCabinFilter.id)
        XCTAssertEqual(cabinFilter.name, "Cabin Air Filter")
        XCTAssertEqual(cabinFilter.normalizedKey, "cabin air filter")
        XCTAssertEqual(cabinFilter.category, .maintenance)
        XCTAssertFalse(cabinFilter.aliases.contains { ThingNormalizer.normalizeKey($0) == "air filter" })

        XCTAssertEqual(carAirFilter.id, engineAirFilter.id)
        XCTAssertEqual(carAirFilter.name, "Engine Air Filter")
        XCTAssertEqual(carAirFilter.category, .maintenance)

        XCTAssertEqual(hvacFilter.name, "Home Air Filters")
        XCTAssertEqual(hvacFilter.category, .home)
        XCTAssertFalse(hvacFilter.aliases.contains { ThingNormalizer.normalizeKey($0) == "air filter" })

        XCTAssertEqual(coffeeFilter.name, "Coffee Filter")
        XCTAssertNotEqual(coffeeFilter.id, hvacFilter.id)
        XCTAssertNotEqual(coffeeFilter.id, carAirFilter.id)
        XCTAssertNotEqual(coffeeFilter.id, cabinFilter.id)

        XCTAssertEqual(oilChange.name, "Oil Change")
        XCTAssertNotEqual(oilChange.id, cabinFilter.id)
        XCTAssertNotEqual(oilChange.id, carAirFilter.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 5)
    }

    @MainActor
    func testResolverCleansAliasesWithSamePolicyAsManualReplacementAndAppend() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(role: .user, text: "Changed oil.", createdAt: now)
        let attempt = ExtractionAttempt(startedAt: now, sourceMessage: message)
        let resolver = ThingResolver(modelContext: context, now: { now })
        let aliases = [" oil change ", "Changed oil!", "changing oil", "engine oil change", ""]

        context.insert(message)
        context.insert(attempt)

        let seedAliases = try XCTUnwrap(ThingNormalizer.seed(for: "Oil Change", contextText: message.text)).aliases
        let allCandidateAliases = ["Oil Change"] + aliases + seedAliases
        let extractedThing = try resolver.resolve(
            name: "Oil Change",
            aliases: aliases,
            contextText: message.text,
            sourceMessage: message,
            attempt: attempt
        )
        let manuallyReplacedThing = Thing(name: "Oil Change", createdAt: now, updatedAt: now)
        DerivedFieldMaintenanceService.updateThingFields(
            manuallyReplacedThing,
            aliases: allCandidateAliases,
            updatedAt: now
        )
        let appendedThing = Thing(name: "Oil Change", aliases: [" oil change "], createdAt: now, updatedAt: now)
        appendedThing.registerAliases(allCandidateAliases, updatedAt: now)

        XCTAssertEqual(extractedThing.aliases, manuallyReplacedThing.aliases)
        XCTAssertEqual(appendedThing.aliases, manuallyReplacedThing.aliases)
        XCTAssertEqual(manuallyReplacedThing.aliases, ["Changed oil!", "engine oil change", "oil changed", "engine oil", "car oil change"])
    }

    @MainActor
    func testExtractionCreatesSourceSemanticLinksAndSearchableAliases() async throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Oil Change", category: "vehicle"),
                            canonicalThing("thing_2", name: "Domains", category: "purchase"),
                            canonicalThing("thing_3", name: "Garage Filter", category: "home_maintenance"),
                            canonicalThing("thing_4", name: "Kitchen Filter", category: "home_maintenance")
                        ],
                        events: [
                            canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15")
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "No buying domains",
                                thingRef: "thing_2",
                                startsAt: "2027-01-15",
                                expiresAt: "2027-02-14"
                            )
                        ],
                        notes: [
                            canonicalNote(
                                "note_1",
                                text: "Garage filter and kitchen filter use the same size.",
                                linkedThingRefs: ["thing_3", "thing_4"]
                            )
                        ],
                        aliases: [
                            canonicalAlias("thing_1", alias: "changed oil"),
                            canonicalAlias("thing_2", alias: "another domain")
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: now)
        )

        _ = try await service.send("Changed oil today. No buying domains for 30 days. Garage filter and kitchen filter use the same size.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())
        let oilChange = try XCTUnwrap(things.first { $0.name == "Oil Change" })
        let domains = try XCTUnwrap(things.first { $0.name == "Domains" })

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(events.first?.sourceMessage?.id, userMessage.id)
        XCTAssertEqual(rules.first?.sourceMessage?.id, userMessage.id)
        XCTAssertEqual(notes.first?.sourceMessage?.id, userMessage.id)
        XCTAssertEqual(events.first?.thing?.id, oilChange.id)
        XCTAssertEqual(rules.first?.thing?.id, domains.id)
        XCTAssertEqual(notes.first?.linkedThings.count, 2)
        XCTAssertTrue(SearchService().contains("changed oil", in: oilChange))
        XCTAssertTrue(SearchService().contains("another domain", in: domains))
        XCTAssertEqual(
            RecallService().answer(query: "changed oil", things: things, events: events).answer,
            """
            Last logged:
            Changed oil for Oil Change on January 15, 2027.
            """
        )
        XCTAssertEqual(links.filter { $0.relation == .extractedFrom }.count, 3)
        XCTAssertEqual(links.filter { $0.relation == .primaryThing }.count, 2)
        XCTAssertEqual(links.filter { $0.relation == .aboutThing }.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.sourceMessageID == userMessage.id })
    }

    @MainActor
    func testManualAliasesPersistAndParticipateInSearchAndRecall() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let thing = Thing(name: "Oil Change", createdAt: now, updatedAt: now)
        let event = LedgerEvent(title: "Changed oil", occurredAt: now, rawText: "Changed oil.", thing: thing)

        thing.registerAlias("engine oil change", updatedAt: now)
        context.insert(thing)
        context.insert(event)
        try context.save()

        let storedThing = try XCTUnwrap(try context.fetch(FetchDescriptor<Thing>()).first)
        let storedEvents = try context.fetch(FetchDescriptor<LedgerEvent>())

        XCTAssertTrue(storedThing.aliases.contains("engine oil change"))
        XCTAssertTrue(SearchService().contains("engine oil change", in: storedThing))
        XCTAssertEqual(
            RecallService().answer(query: "engine oil change", things: [storedThing], events: storedEvents).answer,
            """
            Last logged:
            Changed oil for Oil Change on January 15, 2027.
            """
        )
    }

    @MainActor
    func testLastTimeRecallUsesLatestMatchingEventThroughThingAlias() throws {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = fixedTestNow
        let oilChange = Thing(name: "Oil Change", aliases: ["engine oil change"])
        let oldEvent = LedgerEvent(title: "Changed oil", occurredAt: older, rawText: "Changed oil.", thing: oilChange)
        let newEvent = LedgerEvent(title: "Oil changed", occurredAt: newer, rawText: "Oil changed at the shop.", thing: oilChange)

        XCTAssertEqual(
            RecallService().answer(
                query: "Last engine oil change?",
                things: [oilChange],
                events: [oldEvent, newEvent]
            ).answer,
            """
            Last logged:
            Oil changed for Oil Change on January 15, 2027.
            """
        )
    }

    @MainActor
    func testLastTimeRecallFallsBackToConfidentEventTextMatch() {
        let cleanKitchen = LedgerEvent(
            title: "Cleaned kitchen",
            occurredAt: fixedTestNow,
            rawText: "Cleaned the kitchen after dinner."
        )

        XCTAssertEqual(
            RecallService().answer(
                query: "Did I already clean the kitchen?",
                things: [],
                events: [cleanKitchen]
            ).answer,
            """
            Last logged:
            Cleaned kitchen on January 15, 2027.
            """
        )
    }

    @MainActor
    func testLastTimeRecallReturnsFactualNoResult() {
        XCTAssertEqual(
            RecallService().answer(
                query: "When did I last replace the air filters?",
                things: [],
                events: []
            ).answer,
            "No matching logged event found."
        )
    }
}
