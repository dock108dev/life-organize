import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerExportCompareServiceTests: XCTestCase {
    func testCanonicalLedgerPolicyIgnoresEnvelopeVolatilityAndNormalizesOrdering() throws {
        let expected = makeEnvelope(records: canonicalRecords(), exportedAt: "2026-05-17T18:30:00Z")
        let actual = makeEnvelope(
            records: reorderedRecords(),
            exportedAt: "2026-05-18T18:30:00Z",
            appBuild: "99",
            platform: "iOS"
        )

        let exactResult = LedgerExportCompareService().compare(
            expected: expected,
            actual: actual,
            policy: .exactExportEquality
        )
        XCTAssertFalse(exactResult.isEqual)

        let canonicalResult = LedgerExportCompareService().compare(
            expected: expected,
            actual: actual,
            policy: .canonicalLedgerEquality
        )
        XCTAssertTrue(canonicalResult.isEqual, canonicalResult.differences.description)
    }

    func testComparisonReportsPathAndExpectedActualValues() throws {
        var actualRecords = canonicalRecords()
        let changedThing = ThingExport(
            id: "thing-a",
            name: "HVAC filter",
            aliases: ["filter"],
            category: "home_maintenance",
            createdAt: "2026-05-17T13:42:00Z",
            updatedAt: "2026-05-17T13:42:00Z",
            lastEventAt: "2026-05-17",
            eventCount: 1,
            source: ExportSource(kind: "manual")
        )
        actualRecords = ExportRecords(
            chatMessages: actualRecords.chatMessages,
            extractionRuns: actualRecords.extractionRuns,
            things: [changedThing],
            events: actualRecords.events,
            rules: actualRecords.rules,
            notes: actualRecords.notes,
            ledgerReviewItems: actualRecords.ledgerReviewItems,
            entityLinks: actualRecords.entityLinks
        )

        let result = LedgerExportCompareService().compare(
            expected: makeEnvelope(records: canonicalRecords()),
            actual: makeEnvelope(records: actualRecords),
            policy: .canonicalLedgerEquality
        )

        XCTAssertFalse(result.isEqual)
        let difference = try XCTUnwrap(result.differences.first)
        XCTAssertEqual(difference.path, "/records/things[id=thing-a]/name")
        XCTAssertEqual(difference.kind, .valueMismatch)
        XCTAssertEqual(difference.expected, "Air filter")
        XCTAssertEqual(difference.actual, "HVAC filter")
    }

    func testSeededScenarioExportMatchesCanonicalFixtureBaseline() throws {
        let context = makeInMemoryModelContext()
        let fixture = try SeedScenarioLoader.fixture(for: .ambiguousDogGrooming)
        try SeedScenarioLoader.loadFixture(fixture, into: context)

        let actual = try LocalJSONExportService(
            modelContext: context,
            now: { fixedTestNow },
            calendar: try scenarioCalendar(fixture.clock),
            timeZone: try XCTUnwrap(TimeZone(identifier: fixture.clock.timeZone))
        ).envelope()
        let expected = LedgerExportEnvelope(
            schemaVersion: fixture.ledgerSchemaVersion,
            exportedAt: fixture.clock.now,
            exportedFrom: ExportedFrom(appName: "LifeOrganize", appBuild: "fixture", platform: "fixture"),
            locale: ExportLocale(calendar: fixture.clock.calendar, timeZone: fixture.clock.timeZone),
            records: fixture.records
        )

        let result = LedgerExportCompareService().compare(
            expected: expected,
            actual: actual,
            policy: .uiFacingScenarioEquality
        )

        XCTAssertTrue(result.isEqual, result.differences.description)
    }

    private func makeEnvelope(
        records: ExportRecords,
        exportedAt: String = "2026-05-17T18:30:00Z",
        appBuild: String = "1",
        platform: String = "iOS Simulator"
    ) -> LedgerExportEnvelope {
        LedgerExportEnvelope(
            schemaVersion: 3,
            exportedAt: exportedAt,
            exportedFrom: ExportedFrom(appName: "LifeOrganize", appBuild: appBuild, platform: platform),
            locale: ExportLocale(calendar: "gregorian", timeZone: "America/New_York"),
            records: records
        )
    }

    private func canonicalRecords() -> ExportRecords {
        let source = ExportSource(kind: "manual")
        let message = ChatMessageExport(
            id: "message-a",
            role: "user",
            text: "Replaced the air filter.",
            createdAt: "2026-05-17T13:42:00Z",
            linkedEntityIds: ["thing-a", "event-a"],
            extractionRunId: "run-a",
            extractionRunIds: ["run-a", "run-b"],
            latestExtractionRunId: "run-b",
            successfulExtractionRunIds: ["run-a", "run-b"],
            extractionState: nil
        )
        let runA = ExtractionRunExport(
            id: "run-a",
            chatMessageId: "message-a",
            provider: "openai",
            model: "gpt-5.5",
            purpose: "extraction",
            extractionSchemaVersion: 3,
            promptVersion: "test",
            requestedAt: "2026-05-17T13:42:01Z",
            completedAt: "2026-05-17T13:42:02Z",
            status: "succeeded",
            input: nil,
            requestJSON: #"{"input":"filter"}"#,
            rawResponseText: #"{"events":[]}"#,
            normalizedJSONText: #"{"events":[]}"#,
            parsedResponse: nil,
            createdEntities: ExtractionRunCreatedEntitiesExport(
                things: ["thing-a"],
                events: ["event-a"],
                rules: ["rule-a"],
                notes: ["note-a"]
            ),
            createdEntityIds: ["event-a", "note-a", "rule-a", "thing-a"],
            error: nil
        )
        let runB = ExtractionRunExport(
            id: "run-b",
            chatMessageId: "message-a",
            provider: "openai",
            model: "gpt-5.5",
            purpose: "extraction",
            extractionSchemaVersion: 3,
            promptVersion: "test",
            requestedAt: "2026-05-17T13:43:01Z",
            completedAt: nil,
            status: "failed",
            input: nil,
            requestJSON: nil,
            rawResponseText: nil,
            normalizedJSONText: "{}",
            parsedResponse: nil,
            createdEntities: ExtractionRunCreatedEntitiesExport(things: [], events: [], rules: [], notes: []),
            createdEntityIds: [],
            error: ExtractionRunErrorExport(kind: "network", message: "offline")
        )
        let thing = ThingExport(
            id: "thing-a",
            name: "Air filter",
            aliases: ["filter"],
            category: "home_maintenance",
            createdAt: "2026-05-17T13:42:00Z",
            updatedAt: "2026-05-17T13:42:00Z",
            lastEventAt: "2026-05-17",
            eventCount: 1,
            source: source
        )
        let event = EventExport(
            id: "event-a",
            thingId: "thing-a",
            title: "Replaced air filter",
            eventType: "replacement",
            rawText: "Replaced the air filter.",
            occurredAt: "2026-05-17",
            createdAt: "2026-05-17T13:42:00Z",
            updatedAt: "2026-05-17T13:42:00Z",
            note: nil,
            metadata: [
                EventMetadataExport(
                    key: "interval_days",
                    valueKind: "number",
                    stringValue: nil,
                    numberValue: 90,
                    dateValue: nil,
                    boolValue: nil,
                    unit: "days",
                    sourceText: "90 days"
                ),
                EventMetadataExport(
                    key: "location",
                    valueKind: "string",
                    stringValue: "hallway",
                    numberValue: nil,
                    dateValue: nil,
                    boolValue: nil,
                    unit: nil,
                    sourceText: "hallway"
                ),
            ],
            source: source
        )
        return ExportRecords(
            chatMessages: [message],
            extractionRuns: [runA, runB],
            things: [thing],
            events: [event],
            rules: [],
            notes: [],
            ledgerReviewItems: [],
            entityLinks: []
        )
    }

    private func reorderedRecords() -> ExportRecords {
        let records = canonicalRecords()
        let message = records.chatMessages[0]
        let reorderedMessage = ChatMessageExport(
            id: message.id,
            role: message.role,
            text: message.text,
            createdAt: message.createdAt,
            linkedEntityIds: Array(message.linkedEntityIds.reversed()),
            extractionRunId: message.extractionRunId,
            extractionRunIds: Array(message.extractionRunIds.reversed()),
            latestExtractionRunId: message.latestExtractionRunId,
            successfulExtractionRunIds: Array(message.successfulExtractionRunIds.reversed()),
            extractionState: message.extractionState
        )
        let event = records.events[0]
        let reorderedEvent = EventExport(
            id: event.id,
            thingId: event.thingId,
            title: event.title,
            eventType: event.eventType,
            rawText: event.rawText,
            occurredAt: event.occurredAt,
            createdAt: event.createdAt,
            updatedAt: event.updatedAt,
            note: event.note,
            metadata: Array(event.metadata.reversed()),
            source: event.source
        )
        return ExportRecords(
            chatMessages: [reorderedMessage],
            extractionRuns: Array(records.extractionRuns.reversed()),
            things: records.things,
            events: [reorderedEvent],
            rules: records.rules,
            notes: records.notes,
            ledgerReviewItems: records.ledgerReviewItems,
            entityLinks: records.entityLinks
        )
    }

    private func scenarioCalendar(_ clock: SeedScenarioClock) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: clock.timeZone))
        return calendar
    }
}
