import SwiftData
import XCTest
@testable import LifeOrganize

final class ChatSendServiceIdempotencyTests: XCTestCase {
    @MainActor
    func testRetryReusesExtractedRecordsForSameMessageAndClientIDs() async throws {
        let context = makeInMemoryModelContext()
        let payload = ExtractionResponsePayload(
            rawResponseText: canonicalExtractionJSON(
                things: [
                    canonicalThing("thing_1", name: "Honda", category: "vehicle"),
                    canonicalThing("thing_2", name: "Domains", category: "purchase")
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
                            )
                        ],
                        rawText: "Honda is at 48,231 miles."
                    )
                ],
                rules: [
                    canonicalRule(
                        "rule_1",
                        title: "No buying domains",
                        thingRef: "thing_2",
                        startsAt: "2027-01-15",
                        expiresAt: "2027-02-14"
                    )
                ],
                notes: [
                    canonicalNote("note_1", text: "Honda receipt is in the glove box.", linkedThingRefs: ["thing_1"])
                ]
            )
        )
        let service = ChatSendService(
            modelContext: context,
            extractor: StaticMessageExtractionClient(payload: payload),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        let sentMessage = try await service.send("Honda is at 48,231 miles. No domains. Remember the receipt.")
        let message = try XCTUnwrap(sentMessage)
        let firstAttempt = try XCTUnwrap(try context.fetch(FetchDescriptor<ExtractionAttempt>()).first)
        let linkCountAfterFirstExtraction = try context.fetch(FetchDescriptor<EntityLink>()).count

        _ = try await service.retryExtraction(for: message)
        _ = try await service.retryExtraction(for: message)

        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())
        let retryAttempts = attempts.filter { $0.id != firstAttempt.id }
        let event = try XCTUnwrap(events.first)
        let rule = try XCTUnwrap(rules.first)
        let note = try XCTUnwrap(notes.first)
        let honda = try XCTUnwrap(things.first { $0.name == "Honda" })

        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(retryAttempts.count, 2)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(things.count, 2)
        XCTAssertEqual(links.count, linkCountAfterFirstExtraction)
        XCTAssertEqual(Set(links.map(uniqueKey)).count, links.count)

        for retryAttempt in retryAttempts {
            XCTAssertEqual(retryAttempt.status, .succeeded)
            XCTAssertEqual(retryAttempt.createdEventIDs, [event.id])
            XCTAssertEqual(retryAttempt.createdRuleIDs, [rule.id])
            XCTAssertEqual(retryAttempt.createdNoteIDs, [note.id])
            XCTAssertEqual(Set(retryAttempt.createdThingIDs), Set(things.map(\.id)))
        }

        XCTAssertEqual(event.sourceClientID, "event_1")
        XCTAssertEqual(event.sourceExtractionRunID, firstAttempt.id)
        XCTAssertEqual(event.sourceMessage?.id, message.id)
        XCTAssertEqual(event.thing?.id, honda.id)
        XCTAssertEqual(event.eventType, .measurement)
        XCTAssertEqual(event.metadataEntries.first?.numberValue, 48231)
        XCTAssertEqual(honda.sourceMessageIDs, [message.id])
        XCTAssertEqual(Set(honda.sourceExtractionAttemptIDs), Set(attempts.map(\.id)))
        XCTAssertEqual(honda.eventCount, 1)
        XCTAssertEqual(honda.lastEventAt, ExtractionService.parseDate("2027-01-15"))
    }

    private func uniqueKey(_ link: EntityLink) -> String {
        [
            link.sourceType.rawValue,
            link.sourceID.uuidString,
            link.targetType.rawValue,
            link.targetID.uuidString,
            link.relation.rawValue
        ].joined(separator: "|")
    }
}
