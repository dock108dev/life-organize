import XCTest
@testable import LifeOrganize

final class DeterministicExtractionClientTests: XCTestCase {
    @MainActor
    func testDeterministicClientSupportsEventFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Changed oil today.")
        XCTAssertEqual(envelope.events.map(\.title), ["Changed oil"])
        XCTAssertEqual(envelope.events.first?.thingName, "Oil Change")
        XCTAssertEqual(envelope.events.first?.occurredAt, "2027-01-15")
    }

    @MainActor
    func testDeterministicClientSupportsOilMileageFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Changed oil at 40k miles.")
        let event = try XCTUnwrap(envelope.events.first)
        XCTAssertEqual(event.title, "Changed oil")
        XCTAssertEqual(event.thingName, "Car")
        XCTAssertEqual(event.eventType, "maintenance")
        XCTAssertEqual(event.metadata.first?.key, "mileage")
        XCTAssertEqual(event.metadata.first?.numberValue, 40000)
        XCTAssertEqual(event.metadata.first?.unit, "mi")
    }

    @MainActor
    func testDeterministicClientCoversLightweightEventTypes() async throws {
        let examples = [
            ("Changed oil at 40k miles.", "maintenance", ["mileage"]),
            ("Bought printer paper from Staples for $12.50, 2 reams.", "purchase", ["vendor", "amount", "quantity"]),
            ("Cleaned garage.", "cleaning", []),
            ("Visited dentist office.", "visit", ["location"]),
            ("Replaced smoke detector battery.", "replacement", []),
            ("Cleaned dryer vent.", "cleaning", []),
            ("Renewed passport.", "renewal", ["identifier"]),
            ("Dentist appointment Jan 20.", "appointment", ["due_date"]),
            ("Kitchen remodel project started.", "project", []),
            ("Noted washer serial A123.", "note", ["identifier"])
        ]
        for (input, eventType, metadataKeys) in examples {
            let envelope = try await parsedEnvelope(for: input)
            let event = try XCTUnwrap(envelope.events.first, input)

            XCTAssertEqual(event.eventType, eventType, input)
            XCTAssertEqual(event.metadata.map(\.key), metadataKeys, input)
        }
    }

    @MainActor
    func testActionInputsDoNotBecomeNoteOnlyRecords() async throws {
        let examples = [
            ("Changed oil at 40k miles.", "event", "Changed oil", "maintenance"),
            ("Bought dog food.", "event", "Bought dog food", "purchase"),
            ("Cleaned garage.", "event", "Cleaned garage", "cleaning"),
            ("Replace filter in 2 months.", "rule", "Replace filter", "reminder"),
            ("Reevaluate buying domains in 90 days.", "rule", "Reevaluate buying domains", "reminder")
        ]

        for (input, expectedKind, expectedTitle, expectedType) in examples {
            let envelope = try await parsedEnvelope(for: input)

            XCTAssertEqual(envelope.notes, [], input)
            switch expectedKind {
            case "event":
                let event = try XCTUnwrap(envelope.events.first, input)
                XCTAssertEqual(event.title, expectedTitle, input)
                XCTAssertEqual(event.eventType, expectedType, input)
                XCTAssertEqual(envelope.rules, [], input)
            case "rule":
                let rule = try XCTUnwrap(envelope.rules.first, input)
                XCTAssertEqual(rule.title, expectedTitle, input)
                XCTAssertEqual(rule.ruleType.rawValue, expectedType, input)
                XCTAssertEqual(envelope.events, [], input)
            default:
                XCTFail("Unexpected fixture kind \(expectedKind)")
            }
        }
    }

    @MainActor
    func testPlainFactCanBecomeLinkedStandaloneNote() async throws {
        let envelope = try await parsedEnvelope(for: "Gate code is 4821.")
        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(envelope.notes.map(\.text), ["Gate code is 4821."])
        XCTAssertEqual(envelope.notes.first?.linkedThingNames, ["Gate"])
    }

    @MainActor
    func testDeterministicClientFallsBackToNoteOnlyWhenNoUsefulEventExists() async throws {
        let envelope = try await parsedEnvelope(for: "Ambiguous note only.")
        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(envelope.notes.map(\.text), ["Ambiguous note only."])
    }

    @MainActor
    func testDeterministicClientSupportsRuleFixture() async throws {
        let envelope = try await parsedEnvelope(for: "No buying domains for 30 days.")

        XCTAssertEqual(envelope.rules.map(\.title), ["No buying domains"])
        XCTAssertEqual(envelope.rules.first?.thingName, "Domains")
        XCTAssertEqual(envelope.rules.first?.ruleType, .restriction)
        XCTAssertEqual(envelope.rules.first?.continuityBehavior, .timeLimitedWindow)
        XCTAssertEqual(envelope.rules.first?.startsAt, "2027-01-15")
        XCTAssertEqual(envelope.rules.first?.expiresAt, "2027-02-14")
    }

    @MainActor
    func testDeterministicClientSupportsDateBasedReminderFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Replace air filter in 2 months.")
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(reminder.title, "Replace air filters")
        XCTAssertEqual(reminder.thingName, "Air Filters")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-03-15")
        XCTAssertNil(reminder.expiresAt)
    }

    @MainActor
    func testDeterministicClientSupportsFutureReminderFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Remind me to call dentist Jan 20.")
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(reminder.title, "Call dentist")
        XCTAssertEqual(reminder.thingName, "Dentist")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-01-20")
        XCTAssertNil(reminder.expiresAt)
    }

    @MainActor
    func testTemporalPriorityUsesExplicitPastDateForCompletedEvent() async throws {
        let envelope = try await parsedEnvelope(for: "Changed furnace filter yesterday.")
        let event = try XCTUnwrap(envelope.events.first)

        XCTAssertEqual(envelope.events.count, 1)
        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(event.title, "Changed furnace filter")
        XCTAssertEqual(event.eventType, "maintenance")
        XCTAssertEqual(event.thingName, "Furnace Filter")
        XCTAssertEqual(event.occurredAt, "2027-01-14")
    }

    @MainActor
    func testTemporalPriorityCreatesDateBasedReminderForFutureInstruction() async throws {
        let envelope = try await parsedEnvelope(for: "Remind me to replace furnace filter tomorrow.")
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(reminder.title, "Replace furnace filter")
        XCTAssertEqual(reminder.thingName, "Furnace Filter")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-01-16")
        XCTAssertNil(reminder.expiresAt)
    }

    @MainActor
    func testTemporalPrioritySplitsCompletedEventAndNextDueReminder() async throws {
        let envelope = try await parsedEnvelope(for: "Changed furnace filter today. Next one due in 2 months.")
        let event = try XCTUnwrap(envelope.events.first)
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(envelope.events.count, 1)
        XCTAssertEqual(envelope.rules.count, 1)
        XCTAssertEqual(event.title, "Changed furnace filter")
        XCTAssertEqual(event.eventType, "maintenance")
        XCTAssertEqual(event.occurredAt, "2027-01-15")
        XCTAssertEqual(reminder.title, "Replace furnace filter")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-03-15")
        XCTAssertNil(reminder.expiresAt)
        XCTAssertEqual(envelope.dates.map(\.ownerField), ["occurredAt", "startsAt"])
        XCTAssertEqual(envelope.dates.first { $0.ownerField == "startsAt" }?.sourceText, "in 2 months")
    }

    @MainActor
    func testTemporalPriorityKeepsAppointmentDateOnAppointmentEvent() async throws {
        let envelope = try await parsedEnvelope(for: "Scheduled dentist appointment for Jan 20.")
        let event = try XCTUnwrap(envelope.events.first)

        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(event.title, "Dentist appointment")
        XCTAssertEqual(event.eventType, "appointment")
        XCTAssertEqual(event.occurredAt, "2027-01-20")
        XCTAssertEqual(event.metadata.map(\.key), ["due_date"])
    }

    @MainActor
    func testDeterministicClientSupportsReevaluationReminderFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Reevaluate buying domains in 90 days.")
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(envelope.notes, [])
        XCTAssertEqual(envelope.rules.count, 1)
        XCTAssertEqual(reminder.title, "Reevaluate buying domains")
        XCTAssertEqual(reminder.thingName, "Domains")
        XCTAssertEqual(reminder.ruleType, .reminder)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-04-15")
        XCTAssertNil(reminder.expiresAt)
    }

    @MainActor
    func testTitleNormalizationRemovesLogRequestFraming() async throws {
        let envelope = try await parsedEnvelope(for: "Please log that I changed the furnace filter today.")
        let event = try XCTUnwrap(envelope.events.first)

        XCTAssertEqual(event.title, "Changed furnace filter")
        XCTAssertFalse(event.title.localizedCaseInsensitiveContains("please"))
        XCTAssertFalse(event.title.localizedCaseInsensitiveContains("log that"))
        XCTAssertFalse(event.title.localizedCaseInsensitiveContains("today"))
    }

    @MainActor
    func testTitleNormalizationUsesTaskTitleForReminder() async throws {
        let envelope = try await parsedEnvelope(for: "Please remind me tomorrow to replace furnace filter.")
        let reminder = try XCTUnwrap(envelope.rules.first)

        XCTAssertEqual(reminder.title, "Replace furnace filter")
        XCTAssertFalse(reminder.title.localizedCaseInsensitiveContains("remind me"))
        XCTAssertFalse(reminder.title.localizedCaseInsensitiveContains("tomorrow"))
        XCTAssertEqual(reminder.startsAt, "2027-01-16")
    }

    @MainActor
    func testTitleNormalizationPreservesFactTextForRememberPrefix() async throws {
        let envelope = try await parsedEnvelope(for: "Remember that gate code is 4821.")

        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(envelope.notes.map(\.text), ["Gate code is 4821."])
        XCTAssertEqual(envelope.notes.first?.linkedThingNames, ["Gate"])
    }

    @MainActor
    func testTitleNormalizationRemovesStructuredDateFromAppointmentTitle() async throws {
        let envelope = try await parsedEnvelope(for: "Dentist appointment on Jan 20.")
        let event = try XCTUnwrap(envelope.events.first)

        XCTAssertEqual(event.title, "Dentist appointment")
        XCTAssertEqual(event.occurredAt, "2027-01-20")
        XCTAssertFalse(event.title.localizedCaseInsensitiveContains("Jan"))
        XCTAssertFalse(event.title.contains("20"))
    }

    @MainActor
    func testDeterministicClientKeepsLongTermRestrictionAndReviewReminderSeparate() async throws {
        let envelope = try await parsedEnvelope(for: "No buying domains long term, reevaluate in 90 days.")
        let restriction = try XCTUnwrap(envelope.rules.first { $0.ruleType == .restriction })
        let reminder = try XCTUnwrap(envelope.rules.first { $0.ruleType == .reminder })

        XCTAssertEqual(envelope.rules.count, 2)
        XCTAssertEqual(envelope.notes, [])
        XCTAssertEqual(restriction.title, "No buying domains")
        XCTAssertEqual(restriction.continuityBehavior, .ongoing)
        XCTAssertNil(restriction.expiresAt)
        XCTAssertEqual(reminder.title, "Reevaluate buying domains")
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, "2027-04-15")
        XCTAssertNil(reminder.expiresAt)
    }

    @MainActor
    func testDeterministicClientSupportsNoteFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Remember garage filter location.")

        XCTAssertEqual(envelope.notes.map(\.text), ["Garage filter is in the cabinet."])
        XCTAssertEqual(envelope.notes.first?.linkedThingNames, ["Garage Filter"])
    }

    @MainActor
    func testDeterministicClientSupportsMultiEntityFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Started migration work for claims repo.")

        XCTAssertEqual(envelope.things.map(\.name), ["Claims Repo"])
        XCTAssertEqual(envelope.events.map(\.title), ["Started migration work"])
        XCTAssertEqual(envelope.events.first?.note, "Migration work started.")
    }

    @MainActor
    func testDeterministicClientSupportsPartialSuccessFixture() async throws {
        let envelope = try await parsedEnvelope(for: "Partial oil update.")

        XCTAssertEqual(envelope.events.map(\.title), ["Changed oil"])
        XCTAssertEqual(envelope.warnings.map(\.code), ["validation_failed"])
    }

    @MainActor
    func testDeterministicClientSupportsInvalidJSONFixture() async throws {
        let payload = try await DeterministicMessageExtractionClient().extractRawResponse(
            for: "Please return invalid JSON.",
            now: fixedTestNow
        )

        XCTAssertThrowsError(try ExtractionService.parse(rawResponseText: payload.rawResponseText))
    }

    @MainActor
    func testDeterministicClientSupportsRecallFixture() async throws {
        let envelope = try await parsedEnvelope(for: "When did I last change oil?")
        XCTAssertEqual(envelope.classification, "recall_query")
        XCTAssertEqual(envelope.recallQueries.first?.queryType, "last_time")
        XCTAssertEqual(envelope.recallQueries.first?.thingName, "Oil Change")
    }

    func testDeterministicFixtureIDsAreUnique() {
        let ids = DeterministicMessageExtractionFixtureLibrary.fixtures.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    @MainActor
    func testDeterministicClientPreservesExtractorMetadata() async throws {
        let payload = try await DeterministicMessageExtractionClient().extractRawResponse(for: "Changed oil today.", now: fixedTestNow)

        XCTAssertEqual(payload.requestJSON, #"{"mode":"deterministic"}"#)
        XCTAssertEqual(payload.modelName, "deterministic-extractor")
    }

    @MainActor
    func testSpecificFixturesWinBeforeOverlappingGenericFixtures() async throws {
        let dogFood = try await parsedEnvelope(for: "Bought dog food, 30 lb bag.")
        XCTAssertEqual(dogFood.events.first?.metadata.map(\.key), ["package_quantity"])
        let interval = try await parsedEnvelope(for: "Replaced air filter today, every 90 days.")
        XCTAssertEqual(interval.events.first?.metadata.map(\.key), ["calendar_interval", "service_reset"])
        let domains = try await parsedEnvelope(for: "No buying domains long term, reevaluate in 90 days.")
        XCTAssertEqual(domains.rules.map(\.title), ["No buying domains", "Reevaluate buying domains"])
        XCTAssertNil(domains.rules.first?.expiresAt)
    }

    @MainActor
    func testDeterministicClientUsesStableFallbackForUnmatchedMessages() async throws {
        let first = try await DeterministicMessageExtractionClient().extractRawResponse(for: "A message outside fixtures.", now: fixedTestNow)
        let second = try await DeterministicMessageExtractionClient().extractRawResponse(for: "Another message outside fixtures.", now: fixedTestNow)
        XCTAssertEqual(first.rawResponseText, second.rawResponseText)
        let envelope = try ExtractionService.parse(rawResponseText: first.rawResponseText).envelope
        XCTAssertEqual(envelope.events.map(\.title), ["Changed oil"])
    }

    @MainActor
    func testDeterministicClientSupportsFirstLaunchNoOpFixture() async throws {
        let envelope = try await parsedEnvelope(for: "")
        XCTAssertEqual(envelope.events, [])
        XCTAssertEqual(envelope.rules, [])
        XCTAssertEqual(envelope.notes, [])
        XCTAssertEqual(envelope.things, [])
    }

    @MainActor
    func testDeterministicClientSupportsAmbiguousGroomingReviewFixture() async throws {
        let input = "I think Bogey needs a haircut in a week or two."
        let envelope = try await parsedEnvelope(for: input)

        XCTAssertEqual(envelope.things.map(\.name), ["Bogey"])
        XCTAssertEqual(envelope.rules.map(\.title), [])
        XCTAssertEqual(envelope.notes.map(\.text), [])
        XCTAssertEqual(envelope.dates.map(\.sourceText), ["in a week or two"])
        XCTAssertNil(envelope.dates.first?.date)
        XCTAssertEqual(envelope.dates.first?.role, "rule_starts_at")
        XCTAssertEqual(envelope.dates.first?.ownerClientID, nil)
        XCTAssertEqual(envelope.dates.first?.ownerField, "unknown")
        XCTAssertEqual(envelope.extractionErrors.first?.code, "ambiguous_due_window")
        XCTAssertEqual(envelope.extractionErrors.first?.severity, "warning")
        XCTAssertEqual(envelope.extractionErrors.first?.sourceText, input)
        XCTAssertTrue(envelope.extractionErrors.first?.message.contains("Haircut for Bogey") == true)
        XCTAssertTrue(envelope.confidence.requiresReview)
        XCTAssertEqual(envelope.warnings.map(\.code), ["ambiguous_due_window", "requires_review"])
    }

    @MainActor
    private func parsedEnvelope(for text: String) async throws -> ExtractionEnvelope {
        let payload = try await DeterministicMessageExtractionClient().extractRawResponse(for: text, now: fixedTestNow)
        return try ExtractionService.parse(rawResponseText: payload.rawResponseText).envelope
    }
}
