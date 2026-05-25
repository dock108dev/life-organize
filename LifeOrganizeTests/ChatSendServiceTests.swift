import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatSendServiceTests: XCTestCase {
    @MainActor
    func testExtractedEventPersistsTypeSpanAndMetadata() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Honda", category: "vehicle")
                        ],
                        events: [
                            canonicalEvent(
                                "event_1",
                                title: "Logged Honda mileage",
                                thingRef: "thing_1",
                                occurredAt: "2027-01-15",
                                eventType: "measurement",
                                metadata: [
                                    canonicalEventMetadata(
                                        key: "mileage",
                                        valueKind: "number",
                                        numberValue: 48231,
                                        unit: "mi",
                                        sourceText: "48,231 miles"
                                    ),
                                    canonicalEventMetadata(
                                        key: "location",
                                        valueKind: "string",
                                        stringValue: "garage",
                                        sourceText: "in the garage"
                                    )
                                ],
                                rawText: "Honda is at 48,231 miles in the garage."
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Honda is at 48,231 miles in the garage. Also remember no domains.")

        let event = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerEvent>()).first)
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(event.rawText, "Honda is at 48,231 miles in the garage.")
        XCTAssertEqual(event.eventType, .measurement)
        XCTAssertEqual(event.metadataKeyRawValues, ["mileage", "location"])
        XCTAssertEqual(event.metadataEntries.count, 2)
        XCTAssertEqual(event.metadataEntries.first?.key, .mileage)
        XCTAssertEqual(event.metadataEntries.first?.numberValue, 48231)
        XCTAssertEqual(event.metadataEntries.first?.unit, "mi")
        XCTAssertEqual(event.metadataEntries.first?.sourceText, "48,231 miles")
        XCTAssertEqual(
            assistantMessage.text,
            """
            Event saved:
            Logged Honda mileage for Honda on January 15, 2027. Mileage was 48,231 mi. Location was garage.
            """
        )
    }

    @MainActor
    func testFutureTaskEventPayloadPersistsAsCarryForwardReminder() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Mother", category: "person"),
                            canonicalThing("thing_2", name: "Caitlyn", category: "person")
                        ],
                        events: [
                            canonicalEvent(
                                "event_1",
                                title: "Call my mother and Caitlyn",
                                thingRef: nil,
                                occurredAt: "2027-01-16",
                                eventType: "generic",
                                metadata: [
                                    canonicalEventMetadata(
                                        key: "due_date",
                                        valueKind: "date",
                                        dateValue: "2027-01-16T00:00:00-05:00",
                                        sourceText: "tomorrow"
                                    )
                                ],
                                rawText: "Call my mother and Caitlyn tomorrow."
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Call my mother and Caitlyn tomorrow.")

        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let reminders = try context.fetch(FetchDescriptor<LedgerRule>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)

        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "Call my mother and Caitlyn")
        XCTAssertEqual(reminders.first?.ruleType, .reminder)
        XCTAssertEqual(reminders.first?.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(DateFormatting.dateOnlyString(try XCTUnwrap(reminders.first?.startsAt), timeZone: TimeZone(secondsFromGMT: 0)!), "2027-01-16")
        XCTAssertEqual(Set(things.map(\.name)), ["Mother", "Caitlyn"])
        XCTAssertEqual(attempt.createdEventIDs.count, 0)
        XCTAssertEqual(attempt.createdRuleIDs.count, 1)
        XCTAssertEqual(attempt.createdThingIDs.count, 2)
    }

    @MainActor
    func testPartialExtractionCreatesValidEntitiesAndLinksSourceAttempt() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [
                            canonicalThing("thing_1", name: "Oil Change", category: "vehicle"),
                            canonicalThing("thing_2", name: "Domains", category: "purchase")
                        ],
                        events: [
                            canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15"),
                            canonicalEvent("event_2", title: "", thingRef: "thing_1", occurredAt: "soon")
                        ],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "No buying domains",
                                thingRef: "thing_2",
                                startsAt: "2027-01-15",
                                expiresAt: "2027-02-14"
                            )
                        ]
                    ),
                    requestJSON: #"{"model":"test"}"#,
                    modelName: "test-model"
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed oil today. No buying domains for 30 days.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(userMessage.extractionStatus, .partiallySucceeded)
        XCTAssertEqual(userMessage.extractionErrorCode, .partialValidationFailed)
        XCTAssertEqual(attempt.status, .partiallySucceeded)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.ruleType, .restriction)
        XCTAssertEqual(rules.first?.continuityBehavior, .timeLimitedWindow)
        XCTAssertEqual(things.count, 2)
        XCTAssertEqual(events.first?.sourceMessage?.id, userMessage.id)
        XCTAssertEqual(events.first?.sourceExtractionRunID, attempt.id)
        XCTAssertEqual(rules.first?.sourceMessage?.id, userMessage.id)
        XCTAssertEqual(rules.first?.sourceExtractionRunID, attempt.id)
        XCTAssertTrue(things.allSatisfy { $0.sourceMessageIDs.contains(userMessage.id) })
        XCTAssertTrue(things.allSatisfy { $0.sourceExtractionAttemptIDs.contains(attempt.id) })
        XCTAssertEqual(
            assistantMessage.text,
            """
            Event saved:
            Changed oil for Oil Change on January 15, 2027.

            Restriction saved:
            No buying domains until February 14, 2027.

            Some saved details need review.
            """
        )
        XCTAssertTrue(attempt.normalizedJSONText.contains("validation_failed"))
    }

    @MainActor
    func testLowInformationReviewReasonDoesNotCreateReviewWhenRecordsAreSaved() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [canonicalThing("thing_1", name: "Hole In Wall", category: "home_maintenance")],
                        notes: [
                            canonicalNote(
                                "note_1",
                                text: "Still have a hole in the wall and unsure what to do with it.",
                                linkedThingRefs: ["thing_1"]
                            )
                        ],
                        confidence: #"{"overall":0.62,"requiresReview":true,"reasons":["low_information_message"]}"#
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Still have a hole in the wall and unsure what to do with it.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let attempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let content = LedgerFeedRowContent(item: .message(userMessage))

        XCTAssertEqual(userMessage.extractionStatus, .succeeded)
        XCTAssertNil(userMessage.extractionErrorCode)
        XCTAssertEqual(attempt.status, .succeeded)
        XCTAssertNil(content.secondaryBadge)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerReviewItem>()).isEmpty)
    }

    @MainActor
    func testActionableReviewWarningRefreshesReviewItemsAfterSend() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [canonicalThing("thing_1", name: "Oil Change", category: "vehicle")],
                        events: [
                            canonicalEvent("event_1", title: "Changed oil", thingRef: "thing_1", occurredAt: "2027-01-15")
                        ],
                        confidence: #"{"overall":0.64,"requiresReview":true,"reasons":["possible_duplicate"]}"#
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed oil today.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let reviewItem = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerReviewItem>()).first)

        XCTAssertEqual(userMessage.extractionStatus, .partiallySucceeded)
        XCTAssertEqual(reviewItem.targetType, .chatMessage)
        XCTAssertEqual(reviewItem.targetID, userMessage.id)
    }

    @MainActor
    func testMonthPrecisionReminderDatePersistsOnFirstDayOfMonth() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [canonicalThing("thing_1", name: "Dryer vent", category: "home_maintenance")],
                        rules: [
                            canonicalRule(
                                "rule_1",
                                title: "Clean dryer vent",
                                thingRef: "thing_1",
                                startsAt: "2026-10",
                                expiresAt: nil,
                                ruleType: "reminder"
                            )
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Eventually need the dryer vent cleaned. HOA says October.")

        let reminder = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerRule>()).first)

        XCTAssertEqual(
            DateFormatting.dateOnlyString(reminder.startsAt, calendar: DateFormatting.utcGregorianCalendar, timeZone: DateFormatting.utcGregorianCalendar.timeZone),
            "2026-10-01"
        )
    }

    @MainActor
    func testNoteOnlyConfirmationPreservesQuotedText() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        notes: [
                            canonicalNote("note_1", text: "Garage filter should be replaced every 3 months.")
                        ]
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Remember garage filter should be replaced every 3 months.")

        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })

        XCTAssertEqual(
            assistantMessage.text,
            """
            Note saved:
            "Garage filter should be replaced every 3 months."
            """
        )
    }

    @MainActor
    func testEmptyExtractionUsesRawOnlyCopy() async throws {
        let context = makeInMemoryModelContext()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(rawResponseText: canonicalExtractionJSON())
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await service.send("Changed oil today.")

        let userMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .user })
        let assistantMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant })
        let feedItems = LedgerFeedProjection(calendar: Calendar(identifier: .gregorian), now: fixedTestNow).items(
            messages: [userMessage, assistantMessage],
            events: try context.fetch(FetchDescriptor<LedgerEvent>()),
            reminders: try context.fetch(FetchDescriptor<LedgerRule>()),
            notes: try context.fetch(FetchDescriptor<LedgerNote>())
        )

        XCTAssertEqual(userMessage.extractionStatus, .failedNeedsReview)
        XCTAssertEqual(assistantMessage.text, "Saved for review.\nOpen the timeline entry to review the saved text.")
        XCTAssertEqual(
            Set(feedItems.map(\.id)),
            Set([LedgerFeedItem.messageID(for: userMessage.id)])
        )
    }

    @MainActor
    func testStaleExtractionResultDoesNotWriteAfterGenerationInvalidation() async throws {
        let context = makeInMemoryModelContext()
        let generation = UUID()
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        events: [
                            canonicalEvent("event_1", title: "Changed oil", thingRef: nil, occurredAt: "2027-01-15")
                        ]
                    )
                )
            ),
            dataGeneration: generation,
            isDataGenerationCurrent: { _ in false }
        )

        _ = try await service.send("Changed oil.")

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let userMessage = try XCTUnwrap(messages.first { $0.role == .user })

        XCTAssertNil(userMessage.rawLLMResponse)
        XCTAssertEqual(messages.filter { $0.role == .assistant }.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
    }
}
