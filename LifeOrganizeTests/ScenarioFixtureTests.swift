import XCTest
@testable import LifeOrganize

final class ScenarioFixtureTests: XCTestCase {
    func testBundledScenarioFixturesDecodeAndValidate() throws {
        let expectedIDs = [
            "ambiguous_dog_grooming",
            "car_maintenance",
            "first_launch_empty",
            "heavy_history",
            "operational_home",
            "timeline_search",
            "work_continuity",
        ]

        XCTAssertEqual(try ScenarioFixture.allBundledScenarioIDs(), expectedIDs)
        let fixtures = try ScenarioFixture.loadAllBundledScenarios()

        XCTAssertEqual(fixtures.map(\.id), expectedIDs)
        XCTAssertTrue(fixtures.allSatisfy { $0.fixtureSchemaVersion == 1 })
        XCTAssertTrue(fixtures.allSatisfy { $0.ledgerSchemaVersion == 3 })
        XCTAssertTrue(fixtures.contains { $0.records.chatMessages.isEmpty && $0.records.things.isEmpty })
        XCTAssertTrue(fixtures.contains { !$0.records.entityLinks.isEmpty })
        XCTAssertTrue(fixtures.contains { !$0.expectations.reviewQueueExpectations.isEmpty })
    }

    func testFixtureExpectationsDocumentSupportedAssertionShapes() throws {
        let fixture = try ScenarioFixture.load("car_maintenance")

        XCTAssertEqual(fixture.expectations.requiredCounts?.things, 1)
        XCTAssertEqual(fixture.expectations.requiredVisibleSurfaces.map(\.surface), ["log", "reminders"])
        XCTAssertEqual(fixture.expectations.relationshipChecks.first?.kind, "thingHasEvent")
        XCTAssertEqual(fixture.expectations.searchExpectations.first?.query, "oil change mileage")
        XCTAssertEqual(fixture.expectations.replayExpectations.first?.requiredText, ["oil", "mileage", "reminder"])
    }

    func testOperationalHomeFixtureDocumentsContinuityScenario() throws {
        let fixture = try ScenarioFixture.load("operational_home")

        XCTAssertEqual(fixture.title, "Operational Home Continuity")
        XCTAssertEqual(fixture.expectations.requiredCounts?.things, 7)
        XCTAssertEqual(fixture.expectations.requiredCounts?.events, 20)
        XCTAssertEqual(fixture.expectations.requiredCounts?.rules, 1)
        XCTAssertEqual(fixture.expectations.requiredCounts?.ledgerReviewItems, 2)
        XCTAssertTrue(fixture.records.things.contains { $0.name == "Home Air Filters" })
        XCTAssertTrue(fixture.records.things.contains { $0.name == "Dog food" && $0.aliases.contains("kibble") })
        XCTAssertTrue(fixture.records.events.contains { $0.rawText.contains("Harbor Warehouse") })
        XCTAssertTrue(fixture.expectations.searchExpectations.contains { $0.query == "Harbor Warehouse" })
        XCTAssertTrue(fixture.expectations.replayExpectations.contains { $0.sourceType == "thing" && $0.requiredText.contains("30 lb") })
    }

    func testAmbiguousGroomingFixtureDocumentsConcreteReviewQueueScenario() throws {
        let fixture = try ScenarioFixture.load("ambiguous_dog_grooming")
        let reviewItem = try XCTUnwrap(fixture.records.ledgerReviewItems.first)

        XCTAssertEqual(fixture.title, "Ambiguous Bogey Haircut Review")
        XCTAssertEqual(fixture.records.chatMessages.first?.text, "I think Bogey needs a haircut in a week or two.")
        XCTAssertEqual(fixture.records.things.map(\.name), ["Bogey"])
        XCTAssertTrue(fixture.records.rules.isEmpty)
        XCTAssertTrue(fixture.records.notes.isEmpty)
        XCTAssertEqual(reviewItem.kind, "extraction_review")
        XCTAssertEqual(reviewItem.state, "candidate")
        XCTAssertEqual(reviewItem.title, "Review reminder for Bogey")
        XCTAssertEqual(reviewItem.actionTitle, "Choose Date")
        XCTAssertTrue(reviewItem.detail.contains("May 27 to June 3, 2026"))
        XCTAssertTrue(reviewItem.evidence.contains { $0.summary == "Suggested reminder: Haircut for Bogey" })
        XCTAssertTrue(reviewItem.evidence.contains { $0.sourceType == "thing" && $0.summary.contains("Bogey") })
        XCTAssertEqual(fixture.expectations.reviewQueueExpectations.first?.requiredEvidenceIds.count, 2)
    }

    func testDecodingRejectsMissingRequiredFields() {
        let json = validFixtureJSON()
            .replacingOccurrences(of: #""title": "Inline fixture""#, with: #""titleText": "Inline fixture""#)

        assertFixtureThrows(json, containing: "Missing required field title")
    }

    func testValidationRejectsInvalidTimestamps() {
        let json = validFixtureJSON()
            .replacingOccurrences(of: "2026-05-20T12:00:00Z", with: "not-a-timestamp")

        assertFixtureThrows(json, containing: "clock.now has invalid timestamp")
    }

    func testValidationRejectsDuplicateIDsWithinARecordType() {
        let duplicateThing = """
            {
              "aliases": [],
              "category": "other",
              "createdAt": "2026-05-20T12:00:00Z",
              "eventCount": 0,
              "id": "90000000-0000-4000-8000-000000000101",
              "lastEventAt": null,
              "name": "Duplicate Thing",
              "source": {
                "chatMessageId": null,
                "extractionRunId": null,
                "kind": "manual",
                "sourceClientId": null
              },
              "updatedAt": "2026-05-20T12:00:00Z"
            },
        """
        let json = validFixtureJSON()
            .replacingOccurrences(
                of: #""things": ["#,
                with: """
                "things": [
                              \(duplicateThing)
                """
            )

        assertFixtureThrows(json, containing: "things contains duplicate id")
    }

    func testValidationRejectsUnresolvedReferences() {
        let json = validFixtureJSON()
            .replacingOccurrences(
                of: #""thingId": "90000000-0000-4000-8000-000000000101""#,
                with: #""thingId": "90000000-0000-4000-8000-000000009999""#
            )

        assertFixtureThrows(json, containing: "events.thingId references missing record")
    }

    func testValidationRejectsInvalidEnumValues() {
        let json = validFixtureJSON()
            .replacingOccurrences(of: #""role": "user""#, with: #""role": "visitor""#)

        assertFixtureThrows(json, containing: "chatMessages.role has invalid value")
    }

    func testValidationRejectsInconsistentSourceLinks() {
        let json = validFixtureJSON()
            .replacingOccurrences(
                of: #""linkedEntityIds": ["90000000-0000-4000-8000-000000000201"]"#,
                with: #""linkedEntityIds": []"#
            )

        assertFixtureThrows(json, containing: "linkedEntityIds must include source-linked record")
    }

    private func assertFixtureThrows(_ json: String, containing expectedText: String, line: UInt = #line) {
        XCTAssertThrowsError(try ScenarioFixture.decode(Data(json.utf8)), line: line) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(expectedText),
                "Expected \(error.localizedDescription) to contain \(expectedText)",
                line: line
            )
        }
    }

    private func validFixtureJSON() -> String {
        """
        {
          "clock": {
            "calendar": "gregorian",
            "now": "2026-05-20T12:00:00Z",
            "timeZone": "America/New_York"
          },
          "description": "Inline validation fixture.",
          "expectations": {
            "relationshipChecks": [],
            "replayExpectations": [],
            "requiredCounts": {
              "chatMessages": 1,
              "entityLinks": 0,
              "events": 1,
              "extractionRuns": 0,
              "ledgerReviewItems": 0,
              "notes": 0,
              "rules": 0,
              "things": 1
            },
            "requiredVisibleSurfaces": [],
            "reviewQueueExpectations": [],
            "searchExpectations": []
          },
          "fixtureSchemaVersion": 1,
          "id": "inline_validation",
          "ledgerSchemaVersion": 3,
          "records": {
            "chatMessages": [
              {
                "createdAt": "2026-05-20T12:00:00Z",
                "extractionRunId": null,
                "extractionRunIds": [],
                "extractionState": {
                  "attemptCount": 0,
                  "errorCode": null,
                  "errorMessage": null,
                  "extractionVersion": 3,
                  "lastAttemptAt": null,
                  "latestAttemptErrorCode": null,
                  "latestAttemptStatus": null,
                  "nextRetryAt": null,
                  "recoveryAction": null,
                  "status": "not_required"
                },
                "id": "90000000-0000-4000-8000-000000000001",
                "latestExtractionRunId": null,
                "linkedEntityIds": ["90000000-0000-4000-8000-000000000201"],
                "role": "user",
                "successfulExtractionRunIds": [],
                "text": "Inline event."
              }
            ],
            "entityLinks": [],
            "events": [
              {
                "createdAt": "2026-05-20T12:00:00Z",
                "eventType": "generic",
                "id": "90000000-0000-4000-8000-000000000201",
                "metadata": [],
                "note": null,
                "occurredAt": "2026-05-20",
                "rawText": "Inline event.",
                "source": {
                  "chatMessageId": "90000000-0000-4000-8000-000000000001",
                  "extractionRunId": null,
                  "kind": "extracted",
                  "sourceClientId": null
                },
                "thingId": "90000000-0000-4000-8000-000000000101",
                "title": "Inline event",
                "updatedAt": "2026-05-20T12:00:00Z"
              }
            ],
            "extractionRuns": [],
            "ledgerReviewItems": [],
            "notes": [],
            "rules": [],
            "things": [
              {
                "aliases": [],
                "category": "other",
                "createdAt": "2026-05-20T12:00:00Z",
                "eventCount": 1,
                "id": "90000000-0000-4000-8000-000000000101",
                "lastEventAt": "2026-05-20",
                "name": "Inline Thing",
                "source": {
                  "chatMessageId": null,
                  "extractionRunId": null,
                  "kind": "manual",
                  "sourceClientId": null
                },
                "updatedAt": "2026-05-20T12:00:00Z"
              }
            ]
          },
          "title": "Inline fixture"
        }
        """
    }
}
