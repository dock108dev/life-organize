import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class TemporalPriorityResolutionTests: XCTestCase {
    func testReevaluationReminderUsesRelativeDateBeforeLongTermContext() async throws {
        let context = makeInMemoryModelContext()
        let input = "I don't want to bowl next year should probably reevaluate that in 90 days though"
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(payload: mistakenLongTermRulePayload()),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(input)

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let rule = try XCTUnwrap(rules.first)
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(rule.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-15")))
        XCTAssertNil(rule.expiresAt)
        XCTAssertEqual(rule.rawText, input)
        XCTAssertFalse(rules.contains { $0.startsAt == ExtractionService.parseDate("2028-01-01") })
        XCTAssertTrue(attempt.normalizedJSONText.contains("temporalResolutionDecisions"))
        XCTAssertTrue(attempt.normalizedJSONText.contains("in 90 days"))
        XCTAssertTrue(attempt.normalizedJSONText.contains("next year"))
        XCTAssertEqual(
            assistant.text,
            """
            Reminder saved:
            Reevaluate bowling on April 15, 2027.
            """
        )
    }

    func testStandingRestrictionKeepsFutureReviewSeparateFromExpiration() async throws {
        let context = makeInMemoryModelContext()
        let input = "No buying domains long term, reevaluate in 90 days."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Domains", category: "purchase"),
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "No buying domains",
                                thingRef: "thing_1",
                                startsAt: "2027-01-15",
                                expiresAt: "2027-04-15",
                                rawText: input
                            ),
                        ],
                        dates: [
                            canonicalDate(
                                "date_1",
                                sourceText: "in 90 days",
                                resolvedDateValue: "2027-04-15",
                                dateRole: "rule_expires_at",
                                ownerRef: "rule_1",
                                ownerField: "expiresAt"
                            ),
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send(input)

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let restriction = try XCTUnwrap(rules.first { $0.ruleType == .restriction })
        let reminder = try XCTUnwrap(rules.first { $0.ruleType == .reminder })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(restriction.continuityBehavior, .ongoing)
        XCTAssertNil(restriction.expiresAt)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-15")))
        XCTAssertNil(reminder.expiresAt)
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""rejectedDateClientIDs""#))
        XCTAssertTrue(attempt.normalizedJSONText.contains(#""ruleType":"reminder""#))
    }

    func testPendingRetryAppliesTemporalPriorityResolution() async throws {
        let context = makeInMemoryModelContext()
        let keyStore = InMemoryAPIKeyStore(key: "test-key")
        let message = ChatMessage(
            role: .user,
            text: "I don't want to bowl next year should probably reevaluate that in 90 days though",
            createdAt: fixedTestNow,
            extractionStatus: .pendingRetry,
            extractionAttemptCount: 1,
            nextExtractionRetryAt: fixedTestNow
        )
        context.insert(message)
        try context.save()

        try await PendingExtractionRetryService(
            modelContext: context,
            apiKeyStore: keyStore,
            dateProvider: TestDateProvider(now: fixedTestNow),
            extractorFactory: { _ in StaticMessageExtractionClient(payload: self.mistakenLongTermRulePayload()) }
        )
        .retryRecentPendingMessages()

        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)

        XCTAssertEqual(message.extractionStatus, .succeeded)
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-15")))
        XCTAssertNil(rule.expiresAt)
    }

    func testManualRetryAppliesTemporalPriorityResolution() async throws {
        let context = makeInMemoryModelContext()
        let message = ChatMessage(
            role: .user,
            text: "I don't want to bowl next year should probably reevaluate that in 90 days though",
            createdAt: fixedTestNow,
            extractionStatus: .failed,
            extractionAttemptCount: 1
        )
        context.insert(message)
        try context.save()

        var service = ManualExtractionRetryService(
            modelContext: context,
            apiKeyStore: InMemoryAPIKeyStore(key: "test-key"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        service.extractorFactory = { _ in
            StaticMessageExtractionClient(payload: self.mistakenLongTermRulePayload())
        }

        try await service.retry(message)

        let rule = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)

        XCTAssertEqual(message.extractionStatus, .succeeded)
        XCTAssertEqual(rule.ruleType, .reminder)
        XCTAssertEqual(rule.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-15")))
        XCTAssertNil(rule.expiresAt)
    }

    private func mistakenLongTermRulePayload() -> ExtractionResponsePayload {
        ExtractionResponsePayload(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Bowling", category: "other"),
                ],
                rules: [
                    canonicalRule(
                        "rule_1",
                        title: "Do not bowl next year",
                        thingRef: "thing_1",
                        startsAt: "2028-01-01",
                        expiresAt: nil,
                        rawText: "I don't want to bowl next year"
                    ),
                ],
                dates: [
                    canonicalDate(
                        "date_1",
                        sourceText: "next year",
                        resolvedDateValue: "2028-01-01",
                        dateRole: "rule_starts_at",
                        ownerRef: "rule_1",
                        ownerField: "startsAt"
                    ),
                    canonicalDate(
                        "date_2",
                        sourceText: "in 90 days",
                        resolvedDateValue: "2027-04-15",
                        dateRole: "duration",
                        ownerField: "duration"
                    ),
                ]
            )
        )
    }
}
