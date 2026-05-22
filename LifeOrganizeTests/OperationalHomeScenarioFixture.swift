import SwiftData
import XCTest
@testable import LifeOrganize

struct OperationalHomeScenarioFixture {
    let filters: Thing
    let filterEvents: [LedgerEvent]
    let dogFood: Thing
    let dogFoodEvents: [LedgerEvent]
    let car: Thing
    let oilEvents: [LedgerEvent]
    let garage: Thing
    let garageEvents: [LedgerEvent]
    let householdSupplies: Thing
    let householdSupplyEvents: [LedgerEvent]
    let dryerVent: Thing
    let dryerVentEvents: [LedgerEvent]
    let smokeDetectorBatteries: Thing
    let smokeDetectorEvents: [LedgerEvent]

    var allThings: [Thing] {
        [filters, dogFood, car, garage, householdSupplies, dryerVent, smokeDetectorBatteries]
    }

    var allEvents: [LedgerEvent] {
        filterEvents + dogFoodEvents + oilEvents + garageEvents + householdSupplyEvents + dryerVentEvents + smokeDetectorEvents
    }
}

struct OperationalHomeScenarioFactory {
    let calendar: Calendar

    func scenario(now: Date, context: ModelContext) throws -> OperationalHomeScenarioFixture {
        let filters = Thing(
            name: "Home Air Filters",
            aliases: ["HVAC filters", "furnace filters", "return vent filters"],
            category: .homeMaintenance,
            createdAt: date(2026, 1, 1),
            updatedAt: now
        )
        let filterEvents = [
            event("Replaced Home Air Filters", on: date(2026, 1, 5), type: .replacement, thing: filters, rawText: "Replaced furnace air filters."),
            event("Replaced Home Air Filters", on: date(2026, 4, 5), type: .replacement, thing: filters, rawText: "Replaced HVAC return vent filters."),
            event("Replaced Home Air Filters", on: date(2026, 7, 4), type: .replacement, thing: filters, rawText: "Replaced Home Air Filters before the holiday weekend.")
        ]

        let dogFood = Thing(
            name: "Dog food",
            aliases: ["kibble", "pet food"],
            category: .food,
            createdAt: date(2026, 2, 1),
            updatedAt: now
        )
        let dogFoodEvents = [date(2026, 2, 1), date(2026, 2, 26), date(2026, 3, 23), date(2026, 4, 17), date(2026, 5, 12)].map { purchaseDate in
            event(
                "Bought dog food",
                on: purchaseDate,
                type: .purchase,
                thing: dogFood,
                rawText: "Bought a 30 lb bag of dog food at Corner Pet Supply.",
                metadata: [
                    LedgerEventMetadataEntry(key: .quantity, valueKind: .number, numberValue: 30, unit: "lb", sourceText: "30 lb bag"),
                    LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Corner Pet Supply", sourceText: "Corner Pet Supply")
                ]
            )
        }

        let car = Thing(
            name: "Blue sedan",
            aliases: ["daily driver"],
            category: .vehicle,
            createdAt: date(2026, 1, 10),
            updatedAt: now
        )
        let oilEvents = [
            event("Oil change", on: date(2026, 1, 10), type: .maintenance, thing: car, mileage: 30_000, subtype: "oil_change", rawText: "Changed oil on the blue sedan at 30000 miles."),
            event("Oil change", on: date(2026, 4, 10), type: .maintenance, thing: car, mileage: 35_000, subtype: "oil_change", rawText: "Changed oil on the blue sedan at 35000 miles."),
            event("Oil change", on: date(2026, 7, 1), type: .maintenance, thing: car, mileage: 40_000, subtype: "oil_change", rawText: "Changed oil on the blue sedan at 40000 miles.")
        ]

        let garage = Thing(
            name: "Garage",
            aliases: ["attached garage", "storage bay"],
            category: .homeMaintenance,
            createdAt: date(2026, 3, 1),
            updatedAt: now
        )
        let garageEvents = [
            event("Cleaned garage", on: date(2026, 3, 2), type: .cleaning, thing: garage, rawText: "Swept floor, broke down boxes, moved winter bins to the back shelf."),
            event("Cleaned garage", on: date(2026, 6, 15), type: .cleaning, thing: garage, rawText: "Cleared donation pile and checked storage shelves.")
        ]

        let householdSupplies = Thing(
            name: "Household supplies",
            aliases: ["bulk supplies", "pantry restock", "Harbor Warehouse run"],
            category: .purchase,
            createdAt: date(2026, 4, 1),
            updatedAt: now
        )
        let householdSupplyEvents = [
            householdSupplyEvent(on: date(2026, 4, 3), amount: 148.72, quantity: 8, rawText: "Bought paper towels, trash bags, detergent, batteries, dish tabs, freezer bags, coffee, and napkins.", thing: householdSupplies),
            householdSupplyEvent(on: date(2026, 5, 3), amount: 163.40, quantity: 9, rawText: "Restocked paper towels, laundry soap, dishwasher tabs, granola bars, foil, freezer bags, light bulbs, hand soap, and napkins.", thing: householdSupplies),
            householdSupplyEvent(on: date(2026, 6, 2), amount: 137.18, quantity: 7, rawText: "Restocked trash bags, paper towels, dish tabs, coffee, batteries, hand soap, and freezer bags.", thing: householdSupplies)
        ]

        let dryerVent = Thing(name: "Dryer vent", aliases: ["laundry vent"], category: .homeMaintenance, createdAt: date(2026, 1, 1), updatedAt: now)
        let dryerVentEvents = [
            event("Cleaned dryer vent", on: date(2026, 1, 18), type: .cleaning, thing: dryerVent, rawText: "Vacuumed lint line and checked exterior flap."),
            event("Cleaned dryer vent", on: date(2026, 6, 20), type: .cleaning, thing: dryerVent, rawText: "Cleared lint from hose and wall outlet.")
        ]

        let smokeDetectorBatteries = Thing(
            name: "Smoke detector batteries",
            aliases: ["smoke alarm batteries"],
            category: .homeMaintenance,
            createdAt: date(2026, 1, 1),
            updatedAt: now
        )
        let smokeDetectorEvents = [
            event("Replaced smoke detector battery", on: date(2026, 3, 9), type: .replacement, thing: smokeDetectorBatteries, rawText: "Replaced hallway smoke detector battery."),
            event("Replaced smoke detector battery", on: date(2026, 6, 9), type: .replacement, thing: smokeDetectorBatteries, rawText: "Replaced basement smoke detector battery after chirping.")
        ]

        let fixture = OperationalHomeScenarioFixture(
            filters: filters,
            filterEvents: filterEvents,
            dogFood: dogFood,
            dogFoodEvents: dogFoodEvents,
            car: car,
            oilEvents: oilEvents,
            garage: garage,
            garageEvents: garageEvents,
            householdSupplies: householdSupplies,
            householdSupplyEvents: householdSupplyEvents,
            dryerVent: dryerVent,
            dryerVentEvents: dryerVentEvents,
            smokeDetectorBatteries: smokeDetectorBatteries,
            smokeDetectorEvents: smokeDetectorEvents
        )
        try insert(fixture, into: context)
        return fixture
    }

    private func insert(_ fixture: OperationalHomeScenarioFixture, into context: ModelContext) throws {
        for thing in fixture.allThings {
            context.insert(thing)
        }
        for event in fixture.allEvents {
            context.insert(event)
        }
        fixture.filters.events = fixture.filterEvents
        fixture.dogFood.events = fixture.dogFoodEvents
        fixture.car.events = fixture.oilEvents
        fixture.garage.events = fixture.garageEvents
        fixture.householdSupplies.events = fixture.householdSupplyEvents
        fixture.dryerVent.events = fixture.dryerVentEvents
        fixture.smokeDetectorBatteries.events = fixture.smokeDetectorEvents
        try context.save()
    }

    private func householdSupplyEvent(on date: Date, amount: Double, quantity: Double, rawText: String, thing: Thing) -> LedgerEvent {
        let amountText = LedgerDisplayFormatting.decimal(amount, minimumFractionDigits: 2, maximumFractionDigits: 2)
        return event(
            "Bought household supplies",
            on: date,
            type: .purchase,
            thing: thing,
            rawText: rawText + " Harbor Warehouse total $\(amountText).",
            metadata: [
                LedgerEventMetadataEntry(key: .vendor, valueKind: .string, stringValue: "Harbor Warehouse", sourceText: "Harbor Warehouse"),
                LedgerEventMetadataEntry(key: .amount, valueKind: .number, numberValue: amount, unit: "USD", sourceText: "$\(amountText)"),
                LedgerEventMetadataEntry(key: .quantity, valueKind: .number, numberValue: quantity, unit: "items", sourceText: "\(Int(quantity)) items")
            ]
        )
    }

    private func event(
        _ title: String,
        on date: Date,
        type: LedgerEventType,
        thing: Thing,
        mileage: Double? = nil,
        subtype: String? = nil,
        rawText: String? = nil,
        metadata: [LedgerEventMetadataEntry]? = nil
    ) -> LedgerEvent {
        LedgerEvent(
            title: title,
            occurredAt: date,
            rawText: rawText ?? title,
            createdAt: date,
            updatedAt: date,
            eventType: type,
            metadataEntries: metadata ?? [
                mileage.map { LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: $0, unit: "mi") },
                subtype.map { LedgerEventMetadataEntry(key: .subtype, valueKind: .string, stringValue: $0) }
            ].compactMap { $0 },
            thing: thing
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

extension ContinuityScenarioRegressionTests {
    func assertSearch(
        _ search: SearchService,
        _ query: String,
        in records: [LocalSearchRecord],
        includes expectedTargets: [LocalSearchNavigationTarget],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let targets = Set(search.search(query, in: records).map(\.navigationTarget))
        for target in expectedTargets {
            XCTAssertTrue(targets.contains(target), "Missing \(target) for query \(query)", file: file, line: line)
        }
    }

    func isOpenReviewState(_ state: LedgerReviewItemState) -> Bool {
        switch state {
        case .candidate, .ready, .presented, .failed:
            return true
        case .accepted, .dismissed, .snoozed, .superseded, .expired:
            return false
        }
    }

    func surfaceText(from results: [LocalSearchResult]) -> [String] {
        results.flatMap { [$0.title, $0.subtitle, $0.body, $0.productContextText].compactMap { $0 } }
    }

    func replaySurfaceText(_ replay: TimelineSliceReplayModel) -> [String] {
        replay.sections.flatMap { section in
            [section.title, section.subtitle].compactMap { $0 } + section.rows.flatMap { [$0.displayLabel, $0.summaryText] }
        }
    }

    func assertNoLeakedPrimarySurfaceTerms(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        assertNoTerms(values, disallowed: [
            "dashboard", "chart", "ai-powered", "advice", "coaching", "internal extraction", "confidence", "assistant transcript", "assistant:"
        ], file: file, line: line)
    }

    func assertNoOperationalLanguageLeaks(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        assertNoTerms(values, disallowed: [
            "emotion", "emotional", "mood", "productive", "productivity", "habit", "coach", "coaching", "advice", "primary", "secondary", "surface"
        ], file: file, line: line)
    }

    func assertNoTerms(
        _ values: [String],
        disallowed: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let combined = values.joined(separator: "\n").lowercased()
        for term in disallowed {
            XCTAssertFalse(combined.contains(term), "Leaked term: \(term)\n\(combined)", file: file, line: line)
        }
    }

    func assertStoreIsEmpty(_ context: ModelContext) throws {
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityLink>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 0)
    }
}

@MainActor
final class ControlledScenarioExtractionClient: MessageExtractionClient {
    var onStart: (() -> Void)?
    private var continuation: CheckedContinuation<ExtractionResponsePayload, Error>?

    func extractRawResponse(for _: String, now _: Date) async throws -> ExtractionResponsePayload {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
    }

    func succeed(_ payload: ExtractionResponsePayload) {
        continuation?.resume(returning: payload)
        continuation = nil
    }
}
