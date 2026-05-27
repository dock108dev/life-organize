import XCTest
@testable import LifeOrganize

final class ExtractionServiceParserTests: XCTestCase {
    func testDateOnlyParsingUsesLocalCalendarNoonInsteadOfUTCMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let date = try XCTUnwrap(ExtractionService.parseDate("2026-05-26", calendar: calendar))

        XCTAssertEqual(calendar.component(.year, from: date), 2026)
        XCTAssertEqual(calendar.component(.month, from: date), 5)
        XCTAssertEqual(calendar.component(.day, from: date), 26)
        XCTAssertEqual(calendar.component(.hour, from: date), 12)
    }

    func testParserNormalizesUnsupportedEventTypeAndDropsMalformedMetadata() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Car", category: "vehicle")
                ],
                events: [
                    canonicalEvent(
                        "event_1",
                        title: "Logged car details",
                        thingRef: "thing_1",
                        occurredAt: "2027-01-15",
                        eventType: "vehicle_odometer_event",
                        metadata: [
                            canonicalEventMetadata(
                                key: "mileage",
                                valueKind: "number",
                                sourceText: "forty thousand miles"
                            ),
                            canonicalEventMetadata(
                                key: "warranty_code",
                                valueKind: "string",
                                stringValue: "ABC123",
                                sourceText: "ABC123"
                            )
                        ]
                    )
                ]
            )
        ).envelope
        XCTAssertEqual(envelope.events.first?.eventType, "other")
        XCTAssertEqual(envelope.events.first?.metadata.count, 1)
        XCTAssertEqual(envelope.events.first?.metadata.first?.key, "other")
        XCTAssertEqual(envelope.events.first?.metadata.first?.stringValue, "ABC123")
    }

    func testParserNormalizesMetadataDatetimesToDateOnlyValues() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                events: [
                    canonicalEvent(
                        "event_1",
                        title: "Call my mother and Caitlyn",
                        thingRef: nil,
                        occurredAt: "2026-05-24",
                        metadata: [
                            canonicalEventMetadata(
                                key: "due_date",
                                valueKind: "date",
                                dateValue: "2026-05-24T00:00:00-04:00",
                                sourceText: "tomorrow"
                            )
                        ]
                    )
                ]
            )
        ).envelope

        XCTAssertEqual(envelope.events.first?.metadata.first?.dateValue, "2026-05-24")
    }

    func testParserPreservesDateEvidenceSignals() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                dates: [
                    canonicalDate(
                        "date_1",
                        sourceText: "next Friday",
                        resolvedDateValue: "2027-01-22",
                        dateRole: "rule_starts_at",
                        ownerRef: "rule_1",
                        ownerField: "startsAt",
                        isInferred: true,
                        confidence: 0.62,
                        resolvedConfidence: 0.71,
                        resolvedSourceText: "next Friday"
                    )
                ],
                confidence: #"{"overall":0.58,"requiresReview":true,"reasons":["ambiguous_date"]}"#
            )
        ).envelope

        let date = try XCTUnwrap(envelope.dates.first)
        XCTAssertEqual(date.clientID, "date_1")
        XCTAssertEqual(date.sourceText, "next Friday")
        XCTAssertEqual(date.date, "2027-01-22")
        XCTAssertEqual(date.precision, "day")
        XCTAssertEqual(date.role, "rule_starts_at")
        XCTAssertEqual(date.ownerClientID, "rule_1")
        XCTAssertEqual(date.ownerField, "startsAt")
        XCTAssertTrue(date.isInferred)
        XCTAssertEqual(date.confidence, 0.62)
        XCTAssertEqual(date.resolvedConfidence, 0.71)
        XCTAssertEqual(date.resolvedSourceText, "next Friday")
        XCTAssertEqual(envelope.confidence.overall, 0.58)
        XCTAssertEqual(envelope.confidence.reasons, ["ambiguous_date"])
        XCTAssertEqual(envelope.temporalResolutionDecisions, [])
    }

    func testParserPreservesThingAliasConfidenceAndPossibleDuplicateReason() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Vulnerabilities", category: "work")
                ],
                aliases: [
                    canonicalAlias("thing_1", alias: "vulns")
                ],
                confidence: #"{"overall":0.64,"requiresReview":true,"reasons":["possible_duplicate"]}"#
            )
        ).envelope

        XCTAssertEqual(envelope.things.first?.confidence, 0.97)
        XCTAssertEqual(envelope.aliases.first?.confidence, 0.95)
        XCTAssertEqual(envelope.confidence.reasons, ["possible_duplicate"])
        XCTAssertEqual(envelope.warnings.first { $0.code == "requires_review" }?.message, "possible_duplicate")
    }

    func testParserPreservesRecurringReminderAsTextOnlyBehavior() throws {
        let envelope = try ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Air Filters", category: "home_maintenance")
                ],
                rules: [
                    canonicalRule(
                        "rule_1",
                        title: "Replace air filters every 90 days",
                        thingRef: "thing_1",
                        startsAt: "2027-01-15",
                        expiresAt: nil,
                        ruleType: "reminder",
                        rawText: "Replace air filters every 90 days"
                    )
                ]
            )
        ).envelope

        XCTAssertEqual(envelope.rules.first?.ruleType, .reminder)
        XCTAssertEqual(envelope.rules.first?.continuityBehavior, .recurringText)
    }
}
