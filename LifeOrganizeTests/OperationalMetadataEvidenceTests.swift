import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class OperationalMetadataEvidenceTests: XCTestCase {
    func testDeterministicFixturesExtractOperationalIntervalEvidence() async throws {
        let airFilter = try await parsedEnvelope(for: "Replaced air filter today, every 90 days.")
            .events
            .first
        let airMetadata = try XCTUnwrap(airFilter?.metadata)
        XCTAssertEqual(airMetadata.map(\.key), ["calendar_interval", "service_reset"])
        XCTAssertEqual(airMetadata.first?.numberValue, 90)
        XCTAssertEqual(airMetadata.first?.unit, "days")

        let oilInterval = try await parsedEnvelope(for: "Changed oil today, every 5,000 miles.")
            .events
            .first
        let oilMetadata = try XCTUnwrap(oilInterval?.metadata)
        XCTAssertEqual(oilMetadata.map(\.key), ["mileage_interval", "service_reset"])
        XCTAssertEqual(oilMetadata.first?.numberValue, 5_000)
        XCTAssertEqual(oilMetadata.first?.unit, "mi")

        let nextMileage = try await parsedEnvelope(for: "Changed oil at 50,000 miles, next at 55,000 miles.")
            .events
            .first
        XCTAssertEqual(nextMileage?.metadata.map(\.key), ["mileage", "next_due_mileage"])
        XCTAssertEqual(nextMileage?.metadata.last?.numberValue, 55_000)

        let dogFood = try await parsedEnvelope(for: "Bought dog food, 30 lb bag.")
            .events
            .first
        XCTAssertEqual(dogFood?.metadata.first?.key, "package_quantity")
        XCTAssertEqual(dogFood?.metadata.first?.numberValue, 30)
        XCTAssertEqual(dogFood?.metadata.first?.unit, "lb")

        let unsupported = try await parsedEnvelope(for: "Changed air filter when the indicator turns red.")
        XCTAssertEqual(unsupported.rules, [])
        XCTAssertEqual(unsupported.events.first?.metadata.first?.key, "recurrence_evidence")
        XCTAssertEqual(unsupported.events.first?.metadata.first?.stringValue, "when the indicator turns red")
    }

    func testParserDropsInvalidOperationalMetadataWithoutCorruptingLegacyOtherMetadata() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Car", category: "vehicle"),
                ],
                events: [
                    canonicalEvent(
                        "event_1",
                        title: "Logged service details",
                        thingRef: "thing_1",
                        occurredAt: "2027-01-15",
                        eventType: "maintenance",
                        metadata: [
                            canonicalEventMetadata(
                                key: "calendar_interval",
                                valueKind: "number",
                                numberValue: 90,
                                unit: "days",
                                sourceText: "every 90 days"
                            ),
                            canonicalEventMetadata(
                                key: "next_due_mileage",
                                valueKind: "date",
                                dateValue: "2027-03-15",
                                sourceText: "next at 55,000 miles"
                            ),
                            canonicalEventMetadata(
                                key: "interval_hours",
                                valueKind: "number",
                                numberValue: 300,
                                unit: "hours",
                                sourceText: "every 300 hours"
                            ),
                            canonicalEventMetadata(
                                key: "warranty_code",
                                valueKind: "string",
                                stringValue: "ABC123",
                                sourceText: "ABC123"
                            ),
                        ]
                    ),
                ]
            )
        ).envelope

        let metadata = try XCTUnwrap(envelope.events.first?.metadata)
        XCTAssertEqual(metadata.map(\.key), ["calendar_interval", "other"])
        XCTAssertEqual(metadata.first?.numberValue, 90)
        XCTAssertEqual(metadata.last?.stringValue, "ABC123")
    }

    func testChatSendPersistsTypedIntervalEvidenceFromExtraction() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Air Filter", category: "home_maintenance"),
                        ],
                        events: [
                            canonicalEvent(
                                "event_1",
                                title: "Replaced air filter",
                                thingRef: "thing_1",
                                occurredAt: "2027-01-15",
                                eventType: "replacement",
                                metadata: [
                                    canonicalEventMetadata(
                                        key: "calendar_interval",
                                        valueKind: "number",
                                        numberValue: 90,
                                        unit: "days",
                                        sourceText: "every 90 days"
                                    ),
                                    canonicalEventMetadata(
                                        key: "service_reset",
                                        valueKind: "boolean",
                                        boolValue: true,
                                        sourceText: "replaced"
                                    ),
                                ]
                            ),
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Replaced air filter today, every 90 days.")

        let event = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerEvent>()).first)
        XCTAssertEqual(event.metadataKeyRawValues, ["calendar_interval", "service_reset"])
        XCTAssertEqual(event.intervalEvidence.map(\.kind), [.calendarInterval, .serviceReset])
        XCTAssertEqual(event.intervalEvidence.first?.numberValue, 90)
        XCTAssertEqual(event.intervalEvidence.first?.unit, "days")
        XCTAssertEqual(event.intervalEvidence.last?.boolValue, true)
    }

    func testOperationalEvidenceExportsSearchesAndDisplays() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let car = Thing(name: "Car", category: .vehicle, createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: "Changed oil at 50,000 miles, next at 55,000 miles.",
            createdAt: now,
            updatedAt: now,
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(key: .mileage, valueKind: .number, numberValue: 50_000, unit: "mi"),
                LedgerEventMetadataEntry(key: .nextDueMileage, valueKind: .number, numberValue: 55_000, unit: "mi"),
                LedgerEventMetadataEntry(key: .mileageInterval, valueKind: .number, numberValue: 5_000, unit: "mi"),
                LedgerEventMetadataEntry(key: .nextDueDate, valueKind: .date, dateValue: "2027-03-15"),
            ],
            thing: car
        )
        context.insert(car)
        context.insert(event)
        try context.save()

        let summary = try XCTUnwrap(
            EventMetadataDisplayFormatter.summary(for: event.metadataEntries, eventType: .maintenance, limit: 4)
        )
        XCTAssertEqual(
            summary,
            "Mileage: 50,000 mi · Next Due Mileage: 55,000 mi · Next Due Date: Mar 15, 2027 · Mileage Interval: 5,000 mi"
        )

        let search = SearchService()
        let records = search.records(things: [car], events: [event])
        XCTAssertTrue(search.search("next due mileage", in: records).contains { $0.title == "Changed oil" })
        XCTAssertTrue(search.search("55k", in: records).contains { $0.title == "Changed oil" })
        XCTAssertTrue(search.search("mileage interval", in: records).contains { $0.title == "Changed oil" })

        let exported = try exportService(context: context).envelope().records.events.first
        XCTAssertEqual(exported?.metadata.map(\.key), ["mileage", "next_due_mileage", "mileage_interval", "next_due_date"])
        XCTAssertEqual(exported?.metadata.first { $0.key == "next_due_mileage" }?.numberValue, 55_000)
        XCTAssertEqual(exported?.metadata.first { $0.key == "next_due_date" }?.dateValue, "2027-03-15")
    }

    func testRecurringTextRemainsSavedWordingOnly() {
        let rule = LedgerRule(
            title: "Replace air filters every 90 days",
            ruleType: .reminder,
            rawText: "Replace air filters every 90 days",
            startsAt: fixedTestNow.addingTimeInterval(-86_400)
        )
        let status = RuleStatusService().status(for: rule, at: fixedTestNow)

        XCTAssertEqual(rule.continuityBehavior, .recurringText)
        XCTAssertNil(ReminderDetailActionPolicy.dateAction(for: rule, status: status))
        XCTAssertEqual(ReminderDetailActionPolicy.lifecycleAction(for: rule, status: status)?.title, "Pause Pattern")
    }

    private func parsedEnvelope(for text: String) async throws -> ExtractionEnvelope {
        let payload = try await DeterministicMessageExtractionClient().extractRawResponse(for: text, now: fixedTestNow)
        return try ExtractionService.parse(rawResponseText: payload.rawResponseText).envelope
    }

    private func exportService(context: ModelContext) throws -> LocalJSONExportService {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalJSONExportService(
            modelContext: context,
            now: { fixedTestNow },
            calendar: calendar,
            timeZone: timeZone
        )
    }
}
