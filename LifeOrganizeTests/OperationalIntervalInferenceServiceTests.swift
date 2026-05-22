import XCTest
@testable import LifeOrganize

final class OperationalIntervalInferenceServiceTests: XCTestCase {
    func testInfersAirFilterCalendarCadenceFromThreeLinkedEvents() throws {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        thing.events = [
            event("Replaced HVAC air filter", day: 1, type: .replacement, thing: thing),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: thing),
            event("Replaced HVAC air filter", day: 181, type: .replacement, thing: thing),
        ]

        let inference = try XCTUnwrap(service.inferences(for: thing, now: date(day: 182)).first)

        XCTAssertEqual(inference.track, .airFilter)
        XCTAssertEqual(inference.calendarIntervalDays, 90)
        XCTAssertEqual(inference.confidence.level, .medium)
        XCTAssertEqual(inference.operationalReason, "This is based on saved replacement records for a maintained household item.")
        XCTAssertEqual(inference.evidence.filter { $0.source == .event }.count, 3)
        XCTAssertEqual(inference.nextExpectedDateRange?.start, date(day: 262))
        XCTAssertEqual(inference.nextExpectedDateRange?.end, date(day: 280))
        XCTAssertNotNil(inference.reviewItem())
    }

    func testTwoEventCalendarEvidenceProducesWeakConfidence() throws {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        thing.events = [
            event("Replaced HVAC air filter", day: 1, type: .replacement, thing: thing),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: thing),
        ]

        let inference = try XCTUnwrap(service.inferences(for: thing, now: date(day: 92)).first)

        XCTAssertEqual(inference.calendarIntervalDays, 90)
        XCTAssertEqual(inference.confidence.level, .weak)
    }

    func testInfersDogFoodPurchaseCadence() throws {
        let thing = Thing(name: "Dog food", aliases: ["kibble"], category: .food)
        thing.events = [
            event("Bought dog food", day: 1, type: .purchase, thing: thing, quantity: 30, unit: "lb"),
            event("Bought dog food", day: 25, type: .purchase, thing: thing, quantity: 30, unit: "lb"),
            event("Bought dog food", day: 51, type: .purchase, thing: thing, quantity: 30, unit: "lb"),
            event("Bought dog food", day: 75, type: .purchase, thing: thing, quantity: 30, unit: "lb"),
            event("Bought dog food", day: 100, type: .purchase, thing: thing, quantity: 30, unit: "lb"),
        ]

        let inference = try XCTUnwrap(service.inferences(for: thing, now: date(day: 101)).first)

        XCTAssertEqual(inference.track, .dogFood)
        XCTAssertEqual(inference.calendarIntervalDays, 25)
        XCTAssertEqual(inference.confidence.level, .strong)
        XCTAssertEqual(inference.operationalReason, "This is based on saved purchase records for a recurring household supply.")
        XCTAssertEqual(inference.reviewItem()?.thingName, "Dog food")
    }

    func testInfersOilChangeMileageCadenceSeparatelyFromCalendarCadence() throws {
        let thing = Thing(name: "Blue sedan", category: .vehicle)
        thing.events = [
            event("Oil change", day: 1, type: .maintenance, thing: thing, mileage: 30_000, subtype: "oil_change"),
            event("Oil change", day: 181, type: .maintenance, thing: thing, mileage: 35_000, subtype: "oil_change"),
            event("Oil change", day: 361, type: .maintenance, thing: thing, mileage: 40_000, subtype: "oil_change"),
        ]

        let inference = try XCTUnwrap(service.inferences(for: thing, now: date(day: 362)).first)

        XCTAssertEqual(inference.track, .oilChange)
        XCTAssertEqual(inference.calendarIntervalDays, 180)
        XCTAssertEqual(inference.mileageInterval, 5_000)
        XCTAssertEqual(inference.nextExpectedMileage, 45_000)
        XCTAssertEqual(inference.confidence.level, .strong)
        XCTAssertEqual(inference.operationalReason, "This is based on saved vehicle service records and mileage evidence.")
        XCTAssertTrue(inference.evidence.contains { $0.source == .derivedMileageInterval })
    }

    func testUsesExplicitIntervalMetadataFromSavedEventText() throws {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        thing.events = [
            event(
                "Replaced HVAC air filter",
                day: 1,
                type: .replacement,
                thing: thing,
                metadata: [
                    LedgerEventMetadataEntry(
                        key: .calendarInterval,
                        valueKind: .number,
                        numberValue: 90,
                        unit: "days",
                        sourceText: "every 90 days"
                    ),
                    LedgerEventMetadataEntry(key: .serviceReset, valueKind: .boolean, boolValue: true),
                ]
            ),
        ]

        let inference = try XCTUnwrap(service.inferences(for: thing, now: date(day: 2)).first)

        XCTAssertEqual(inference.calendarIntervalDays, 90)
        XCTAssertEqual(inference.confidence.level, .strong)
        XCTAssertEqual(inference.evidence.last?.detail, "every 90 days")
    }

    func testRecurringTextReminderRemainsSavedWordingAndDoesNotCreateInferenceAlone() {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        let rule = LedgerRule(
            title: "Replace HVAC air filter every 90 days",
            ruleType: .reminder,
            rawText: "Replace HVAC air filter every 90 days",
            startsAt: date(day: 1),
            thing: thing
        )
        thing.rules = [rule]

        XCTAssertEqual(rule.continuityBehavior, .recurringText)
        XCTAssertTrue(service.inferences(for: thing, now: date(day: 2)).isEmpty)
    }

    func testSuppressesInferenceWhenActiveReminderCoversSameCadence() throws {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        thing.events = [
            event("Replaced HVAC air filter", day: 1, type: .replacement, thing: thing),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: thing),
            event("Replaced HVAC air filter", day: 181, type: .replacement, thing: thing),
        ]
        thing.rules = [
            LedgerRule(
                title: "Replace HVAC air filter",
                ruleType: .reminder,
                continuityBehavior: .dateBasedReminder,
                startsAt: date(day: 170),
                thing: thing
            ),
        ]

        XCTAssertTrue(service.inferences(for: thing, now: date(day: 182)).isEmpty)
        let suppressed = try XCTUnwrap(service.inferences(for: thing, now: date(day: 182), includeSuppressed: true).first)
        XCTAssertTrue(suppressed.isSuppressed)
        XCTAssertNil(suppressed.reviewItem())
        XCTAssertTrue(suppressed.suppressionReason?.contains("Existing active reminder") == true)
    }

    func testInsufficientEvidenceDoesNotInferPattern() {
        let thing = Thing(name: "Dog food", category: .food)
        thing.events = [
            event("Bought dog food", day: 1, type: .purchase, thing: thing),
        ]

        XCTAssertTrue(service.inferences(for: thing, now: date(day: 2)).isEmpty)
    }

    func testMixedEventTypesDoNotBecomeComparableEvidence() {
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance)
        thing.events = [
            event("Bought HVAC air filter", day: 1, type: .purchase, thing: thing),
            event("Replaced HVAC air filter", day: 91, type: .replacement, thing: thing),
            event("Cleaned HVAC air filter", day: 181, type: .cleaning, thing: thing),
        ]

        XCTAssertTrue(service.inferences(for: thing, now: date(day: 182)).isEmpty)
    }

    func testAmbiguousFilterThingDoesNotMergeDifferentFilterTracks() {
        let thing = Thing(name: "Filters", category: .homeMaintenance)
        thing.events = [
            event("Replaced kitchen water filter", day: 1, type: .replacement, thing: thing),
            event("Replaced furnace filter", day: 91, type: .replacement, thing: thing),
            event("Replaced vacuum filter", day: 181, type: .replacement, thing: thing),
        ]

        XCTAssertTrue(service.inferences(for: thing, now: date(day: 182)).isEmpty)
    }

    private var service: OperationalIntervalInferenceService {
        OperationalIntervalInferenceService(calendar: calendar)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func event(
        _ title: String,
        day: Int,
        type: LedgerEventType,
        thing: Thing,
        mileage: Double? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        subtype: String? = nil,
        metadata: [LedgerEventMetadataEntry]? = nil
    ) -> LedgerEvent {
        LedgerEvent(
            title: title,
            occurredAt: date(day: day),
            rawText: title,
            createdAt: date(day: day),
            updatedAt: date(day: day),
            eventType: type,
            metadataEntries: metadata ?? metadataEntries(mileage: mileage, quantity: quantity, unit: unit, subtype: subtype),
            thing: thing
        )
    }

    private func metadataEntries(
        mileage: Double?,
        quantity: Double?,
        unit: String?,
        subtype: String?
    ) -> [LedgerEventMetadataEntry] {
        [
            mileage.map {
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: $0, unit: "mi")
            },
            quantity.map {
                LedgerEventMetadataEntry(key: .quantity, valueKind: .number, numberValue: $0, unit: unit)
            },
            subtype.map {
                LedgerEventMetadataEntry(key: .subtype, valueKind: .string, stringValue: $0)
            },
        ].compactMap { $0 }
    }

    private func date(day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
    }
}
