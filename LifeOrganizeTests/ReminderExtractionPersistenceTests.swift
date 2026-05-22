import SwiftData
import XCTest
@testable import LifeOrganize

final class ReminderExtractionPersistenceTests: XCTestCase {
    @MainActor
    func testAmbiguousGroomingReminderCreatesThingOnlyAndKeepsDateWindowReviewable() async throws {
        let context = makeInMemoryModelContext()
        let input = "I think Bogey needs a haircut in a week or two."
        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: bogeyScenarioNow)
        )

        let sentMessage = try await service.send(input)
        let message = try XCTUnwrap(sentMessage)
        let things = try context.fetch(FetchDescriptor<Thing>())
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let envelope = try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(attempt.normalizedJSONText.utf8))

        XCTAssertEqual(message.text, input)
        XCTAssertEqual(message.extractionStatus, .partiallySucceeded)
        XCTAssertEqual(things.map(\.name), ["Bogey"])
        XCTAssertTrue(things.first?.sourceMessageIDs.contains(message.id) == true)
        XCTAssertTrue(attempt.createdThingIDs.contains(things[0].id))
        XCTAssertTrue(attempt.createdRuleIDs.isEmpty)
        XCTAssertTrue(attempt.createdNoteIDs.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerRule>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerNote>()).isEmpty)
        XCTAssertEqual(envelope.dates.first?.sourceText, "in a week or two")
        XCTAssertNil(envelope.dates.first?.date)
        XCTAssertEqual(envelope.dates.first?.role, "rule_starts_at")
        XCTAssertTrue(envelope.warnings.contains { $0.code == "ambiguous_due_window" })
    }

    @MainActor
    func testAmbiguousGroomingLinksExistingThingWithoutDuplicateOrReminder() async throws {
        let context = makeInMemoryModelContext()
        let existingBogey = Thing(name: "Bogey", category: .pet, createdAt: bogeyScenarioNow, updatedAt: bogeyScenarioNow)
        context.insert(existingBogey)
        try context.save()

        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: bogeyScenarioNow)
        )

        _ = try await service.send("I think Bogey needs a haircut in a week or two.")

        let things = try context.fetch(FetchDescriptor<Thing>())
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(things.count, 1)
        XCTAssertEqual(things.first?.id, existingBogey.id)
        XCTAssertTrue(attempt.createdThingIDs.contains(existingBogey.id))
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerRule>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerNote>()).isEmpty)
    }

    @MainActor
    func testDateBasedReminderPersistsTypeBehaviorAndDueDate() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Air Filters", category: "home_maintenance")
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "Replace air filters",
                                thingRef: "thing_1",
                                startsAt: "2027-03-15",
                                expiresAt: nil,
                                ruleType: "reminder",
                                rawText: "Replace air filters in 2 months"
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Replace air filters in 2 months")

        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(rule.startsAt, ExtractionService.parseDate("2027-03-15"))
        XCTAssertNil(rule.expiresAt)
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""ruleType":"reminder""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""continuityBehavior":"date_based_reminder""#))
        XCTAssertEqual(
            assistantMessage.text,
            """
            Reminder saved:
            Replace air filters on March 15, 2027.
            """
        )
    }

    @MainActor
    func testCompletedActionAndNextDueReminderPersistAsSeparateRecords() async throws {
        let context = makeInMemoryModelContext()
        let input = "Changed furnace filter today. Next one due in 2 months."
        let service = ChatSendService(
            modelContext: context,
            extractor: DeterministicMessageExtractionClient(),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(input)

        let event = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerEvent>()).first)
        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })
        let sourceLinks = try context.fetch(FetchDescriptor<EntityLink>()).filter { $0.sourceMessageID == event.sourceMessageID }

        XCTAssertEqual(event.title, "Changed furnace filter")
        XCTAssertEqual(event.eventType, .maintenance)
        XCTAssertEqual(event.occurredAt, ExtractionService.parseDate("2027-01-15"))
        XCTAssertEqual(event.rawText, "Changed furnace filter")
        XCTAssertEqual(event.sourceExtractionRunID, attempt.id)
        XCTAssertEqual(event.sourceMessage?.text, input)

        XCTAssertEqual(rule.title, "Replace furnace filter")
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(rule.startsAt, ExtractionService.parseDate("2027-03-15"))
        XCTAssertNil(rule.expiresAt)
        XCTAssertEqual(rule.rawText, input)
        XCTAssertEqual(rule.sourceExtractionRunID, attempt.id)
        XCTAssertEqual(rule.sourceMessage?.text, input)

        XCTAssertEqual(attempt.createdEventIDs.count, 1)
        XCTAssertEqual(attempt.createdRuleIDs.count, 1)
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""ruleType":"reminder""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""continuityBehavior":"date_based_reminder""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""clientID":"date_furnace_filter_next_due""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""confidence":{"overall":0.95"#))
        XCTAssertTrue(sourceLinks.contains { $0.relation == .extractedFrom && $0.targetID == event.id })
        XCTAssertTrue(sourceLinks.contains { $0.relation == .extractedFrom && $0.targetID == rule.id })
        XCTAssertTrue(assistantMessage.text.contains("Event saved:"))
        XCTAssertTrue(assistantMessage.text.contains("Reminder saved:"))
    }

    @MainActor
    func testReevaluationReminderPersistsOperationalTitleAndPreservesSourceText() async throws {
        let context = makeInMemoryModelContext()
        let input = "No bowling next year, reevaluate in 90 days."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Bowling", category: "other")
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "No bowling",
                                thingRef: "thing_1",
                                startsAt: "2027-04-15",
                                expiresAt: nil,
                                ruleType: "reminder",
                                rawText: input
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(input)

        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(rule.title, "Reevaluate bowling")
        XCTAssertEqual(rule.rawText, input)
        XCTAssertEqual(rule.sourceMessage?.text, input)
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(
            assistantMessage.text,
            """
            Reminder saved:
            Reevaluate bowling on April 15, 2027.
            """
        )
    }

    func testRuleTitleNormalizerPreservesConcreteReminderActionsAndObjects() {
        XCTAssertEqual(
            RuleTitleNormalizer.normalizedTitle(
                extractedTitle: "Reminder to reevaluate insurance quote in 90 days",
                sourceText: "Reevaluate insurance quote in 90 days",
                ruleType: .reminder,
                thingName: "Insurance quote",
                startsAt: "2027-04-15",
                expiresAt: nil
            ),
            "Reevaluate insurance quote"
        )
        XCTAssertEqual(
            RuleTitleNormalizer.normalizedTitle(
                extractedTitle: "Follow up with Morgan about invoice",
                sourceText: "Follow up with Morgan about invoice next week",
                ruleType: .reminder,
                thingName: nil,
                startsAt: "2027-01-22",
                expiresAt: nil
            ),
            "Follow up with Morgan about invoice"
        )
        XCTAssertEqual(
            RuleTitleNormalizer.normalizedTitle(
                extractedTitle: "Replace air filter",
                sourceText: "Replace air filter in 2 months",
                ruleType: .reminder,
                thingName: "Air Filter",
                startsAt: "2027-03-15",
                expiresAt: nil
            ),
            "Replace air filter"
        )
    }

    @MainActor
    func testGenericExtractedReminderTitleRepairsFromSourceBeforePersistence() async throws {
        let context = makeInMemoryModelContext()
        let input = "Follow up with Morgan about invoice on Friday."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "Follow up",
                                thingRef: nil,
                                startsAt: "2027-01-22",
                                expiresAt: nil,
                                ruleType: "reminder",
                                rawText: input
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(input)

        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)

        XCTAssertEqual(rule.title, "Follow up with Morgan about invoice")
        XCTAssertNotEqual(rule.title, "Follow up")
        XCTAssertEqual(rule.rawText, input)
    }

    @MainActor
    func testRetryReusesExistingRuleTitleWithoutRenormalizingUserEdits() async throws {
        let context = makeInMemoryModelContext()
        let input = "Follow up with Morgan about invoice on Friday."
        let payload = ExtractionResponsePayload(
            rawResponseText: canonicalExtractionJSON(
                rules: [
                    canonicalRule(
                        "rule_1",
                        title: "Follow up",
                        thingRef: nil,
                        startsAt: "2027-01-22",
                        expiresAt: nil,
                        ruleType: "reminder",
                        rawText: input
                    )
                ]
            )
        )
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(payload: payload),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        let sentMessage = try await service.send(input)
        let message = try XCTUnwrap(sentMessage)
        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)
        rule.title = "Invoice check-in with Morgan"
        try context.save()

        _ = try await service.retryExtraction(for: message)

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let retriedRule = try XCTUnwrap(rules.first)

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(retriedRule.title, "Invoice check-in with Morgan")
    }

    private var bogeyScenarioNow: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12))!
    }
}
