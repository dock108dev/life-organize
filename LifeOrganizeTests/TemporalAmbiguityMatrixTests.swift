import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class TemporalAmbiguityMatrixTests: XCTestCase {
    func testTemporalPhraseMatrixDocumentsOwnershipAndCommitPolicy() {
        let rows: [TemporalPhraseMatrixRow] = [
            TemporalPhraseMatrixRow(
                phrase: "reevaluate in 90 days",
                ownership: .deterministicResolver,
                preservesAmbiguityForReview: false,
                mustNotGuessCommittedReminder: false
            ),
            TemporalPhraseMatrixRow(
                phrase: "replace in 2 months",
                ownership: .deterministicFixture,
                preservesAmbiguityForReview: false,
                mustNotGuessCommittedReminder: false
            ),
            TemporalPhraseMatrixRow(
                phrase: "next year",
                ownership: .deterministicContextOnly,
                preservesAmbiguityForReview: true,
                mustNotGuessCommittedReminder: true
            ),
            TemporalPhraseMatrixRow(
                phrase: "later this month",
                ownership: .modelDependentAmbiguity,
                preservesAmbiguityForReview: true,
                mustNotGuessCommittedReminder: true
            ),
            TemporalPhraseMatrixRow(
                phrase: "revisit next season",
                ownership: .modelDependentAmbiguity,
                preservesAmbiguityForReview: true,
                mustNotGuessCommittedReminder: true
            ),
        ]

        XCTAssertEqual(rows.first { $0.phrase == "reevaluate in 90 days" }?.ownership, .deterministicResolver)
        XCTAssertEqual(rows.first { $0.phrase == "replace in 2 months" }?.ownership, .deterministicFixture)
        XCTAssertEqual(rows.first { $0.phrase == "next year" }?.ownership, .deterministicContextOnly)
        XCTAssertEqual(rows.first { $0.phrase == "later this month" }?.ownership, .modelDependentAmbiguity)
        XCTAssertEqual(rows.first { $0.phrase == "revisit next season" }?.ownership, .modelDependentAmbiguity)
        XCTAssertEqual(
            Set(rows.filter(\.mustNotGuessCommittedReminder).map(\.phrase)),
            ["next year", "later this month", "revisit next season"]
        )
        XCTAssertEqual(
            Set(rows.filter(\.preservesAmbiguityForReview).map(\.phrase)),
            ["next year", "later this month", "revisit next season"]
        )
    }

    func testNumericReviewDurationsResolveAgainstFixedClockAndTimeZone() throws {
        let cases: [(input: String, expectedDate: String)] = [
            ("Reevaluate pantry buying in 90 days.", "2027-04-15"),
            ("Check back in 2 weeks.", "2027-01-29"),
            ("Follow up in 1 month.", "2027-02-15"),
            ("Remind me in 1 year.", "2028-01-15"),
        ]

        for testCase in cases {
            let resolved = try resolveReminder(
                sourceText: testCase.input,
                startingEnvelope: parsedEnvelope(
                    rules: [
                        canonicalRule(
                            "rule_1",
                            title: "Review later",
                            thingRef: nil,
                            startsAt: "2028-01-01",
                            expiresAt: nil,
                            ruleType: "reminder",
                            rawText: testCase.input
                        ),
                    ]
                )
            )

            XCTAssertEqual(resolved.rules.first?.startsAt, testCase.expectedDate, testCase.input)
            XCTAssertEqual(resolved.rules.first?.ruleType, .reminder, testCase.input)
            XCTAssertEqual(resolved.rules.first?.continuityBehavior, .dateBasedReminder, testCase.input)
            XCTAssertFalse(resolved.temporalResolutionDecisions.isEmpty, testCase.input)
        }
    }

    func testLongTermAndVaguePhrasesDoNotCreateDeterministicDatesWithoutNumericDuration() throws {
        let cases = [
            "Maybe renew this next year.",
            "Revisit this later this month.",
            "Revisit this next season.",
        ]

        for input in cases {
            let original = parsedEnvelope(
                things: [canonicalThing("thing_1", name: "Open Decision", category: "other")],
                dates: [
                    canonicalDate(
                        "date_1",
                        sourceText: input,
                        resolvedDateValue: nil,
                        dateRole: "rule_starts_at",
                        ownerField: "unknown",
                        confidence: 0.3,
                        resolvedConfidence: 0.3
                    ),
                ],
                confidence: #"{"overall":0.35,"requiresReview":true,"reasons":["ambiguous_date"]}"#,
                errors: [
                    modelError(code: "ambiguous_date", message: "Temporal phrase needs review.", sourceText: input),
                ]
            )

            let resolved = TemporalPriorityResolver.resolve(
                envelope: original,
                sourceText: input,
                now: Self.matrixNow,
                calendar: Self.matrixCalendar
            )

            XCTAssertEqual(resolved.rules, [], input)
            XCTAssertTrue(resolved.temporalResolutionDecisions.isEmpty, input)
            XCTAssertEqual(resolved.dates.first?.date, nil, input)
            XCTAssertTrue(resolved.warnings.contains { $0.code == "ambiguous_date" }, input)
            XCTAssertTrue(resolved.warnings.contains { $0.code == "requires_review" }, input)
        }
    }

    func testDeterministicFixtureCoversReplacementInTwoMonths() async throws {
        let payload = try await DeterministicMessageExtractionClient()
            .extractRawResponse(for: "Replace air filter in 2 months", now: Self.matrixNow)
        let envelope = try ExtractionService.parse(rawResponseText: payload.rawResponseText).envelope

        XCTAssertEqual(envelope.rules.first?.title, "Replace air filters")
        XCTAssertEqual(envelope.rules.first?.ruleType, .reminder)
        XCTAssertEqual(envelope.rules.first?.startsAt, "2027-03-15")
        XCTAssertEqual(envelope.rules.first?.continuityBehavior, .dateBasedReminder)
    }

    func testStandingRestrictionKeepsOngoingSemanticsWithSeparateReviewReminder() async throws {
        let context = makeInMemoryModelContext()
        let input = "Pause buying tools indefinitely, check back after 2 weeks."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Tools", category: "purchase"),
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "Pause buying tools",
                                thingRef: "thing_1",
                                startsAt: "2027-01-15",
                                expiresAt: "2027-01-29",
                                rawText: input
                            ),
                        ],
                        dates: [
                            canonicalDate(
                                "date_1",
                                sourceText: "indefinitely",
                                resolvedDateValue: nil,
                                dateRole: "unknown",
                                ownerField: "context"
                            ),
                            canonicalDate(
                                "date_2",
                                sourceText: "after 2 weeks",
                                resolvedDateValue: "2027-01-29",
                                dateRole: "rule_expires_at",
                                ownerRef: "rule_1",
                                ownerField: "expiresAt"
                            ),
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: Self.matrixNow)
        )

        _ = try await service.send(input)

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let restriction = try XCTUnwrap(rules.first { $0.ruleType == .restriction })
        let reminder = try XCTUnwrap(rules.first { $0.ruleType == .reminder })

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(restriction.continuityBehavior, .ongoing)
        XCTAssertNil(restriction.expiresAt)
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-01-29")))
        XCTAssertNil(reminder.expiresAt)
    }

    func testExplicitWindowLanguageKeepsRestrictionWindowWhenReviewReminderExists() async throws {
        let context = makeInMemoryModelContext()
        let input = "No buying domains until April 1, reevaluate in 90 days."
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
                                expiresAt: "2027-04-01",
                                sourceText: "until April 1",
                                rawText: input
                            ),
                        ],
                        dates: [
                            canonicalDate(
                                "date_1",
                                sourceText: "until April 1",
                                resolvedDateValue: "2027-04-01",
                                dateRole: "rule_expires_at",
                                ownerRef: "rule_1",
                                ownerField: "expiresAt"
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
            ),
            dateProvider: TestDateProvider(now: Self.matrixNow)
        )

        _ = try await service.send(input)

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let restriction = try XCTUnwrap(rules.first { $0.ruleType == .restriction })
        let reminder = try XCTUnwrap(rules.first { $0.ruleType == .reminder })

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(restriction.continuityBehavior, .timeLimitedWindow)
        XCTAssertEqual(restriction.expiresAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-01")))
        XCTAssertEqual(reminder.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(reminder.startsAt, try XCTUnwrap(ExtractionService.parseDate("2027-04-15")))
        XCTAssertNil(reminder.expiresAt)
    }

    func testAmbiguousTemporalInterpretationCreatesReviewSignalWithoutCommittedReminder() async throws {
        let context = makeInMemoryModelContext()
        let input = "Revisit cabin filter next season."
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Cabin filter", category: "home_maintenance"),
                        ],
                        dates: [
                            canonicalDate(
                                "date_1",
                                sourceText: "next season",
                                resolvedDateValue: nil,
                                dateRole: "rule_starts_at",
                                ownerField: "unknown",
                                confidence: 0.25,
                                resolvedConfidence: 0.25
                            ),
                        ],
                        confidence: #"{"overall":0.42,"requiresReview":true,"reasons":["ambiguous_date"]}"#,
                        errors: [
                            modelError(code: "ambiguous_date", message: "Seasonal timing needs review.", sourceText: input),
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: Self.matrixNow)
        )

        let maybeSentMessage = try await service.send(input)
        let sentMessage = try XCTUnwrap(maybeSentMessage)
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let reviewItems = try LedgerReviewItemGenerationService(
            modelContext: context,
            now: { Self.matrixNow },
            calendar: Self.matrixCalendar
        ).refresh()

        XCTAssertEqual(sentMessage.extractionStatus, .partiallySucceeded)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerRule>()).isEmpty)
        XCTAssertTrue(attempt.normalizedJSONText.contains("ambiguous_date"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 1)
        XCTAssertTrue(reviewItems.contains { item in
            item.kind == .extractionReview
                && item.targetType == .chatMessage
                && item.targetID == sentMessage.id
        })
    }

    private func resolveReminder(
        sourceText: String,
        startingEnvelope: ExtractionEnvelope
    ) throws -> ExtractionEnvelope {
        TemporalPriorityResolver.resolve(
            envelope: startingEnvelope,
            sourceText: sourceText,
            now: Self.matrixNow,
            calendar: Self.matrixCalendar
        )
    }

    private func parsedEnvelope(
        things: [String] = [],
        rules: [String] = [],
        dates: [String] = [],
        confidence: String = #"{"overall":0.95,"requiresReview":false,"reasons":[]}"#,
        errors: [String] = []
    ) -> ExtractionEnvelope {
        try! ExtractionService.parse(
            rawResponseText: canonicalExtractionJSON(
                things: things,
                rules: rules,
                dates: dates,
                confidence: confidence,
                errors: errors
            )
        ).envelope
    }

    private func modelError(code: String, message: String, sourceText: String) -> String {
        #"{"code":"\#(code)","message":"\#(message)","severity":"warning","sourceText":\#(jsonLiteral(sourceText))}"#
    }

    private static let matrixTimeZone = TimeZone(identifier: "America/New_York")!

    private static let matrixCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = matrixTimeZone
        return calendar
    }()

    private static let matrixNow: Date = {
        DateComponents(
            calendar: matrixCalendar,
            timeZone: matrixTimeZone,
            year: 2027,
            month: 1,
            day: 15,
            hour: 9,
            minute: 30
        ).date!
    }()
}

private enum TemporalPhraseOwnership: Equatable {
    case deterministicResolver
    case deterministicFixture
    case deterministicContextOnly
    case modelDependentAmbiguity
}

private struct TemporalPhraseMatrixRow {
    let phrase: String
    let ownership: TemporalPhraseOwnership
    let preservesAmbiguityForReview: Bool
    let mustNotGuessCommittedReminder: Bool
}
