import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
extension LedgerReviewQueueConsistencyScenarioTests {
    struct MatrixFixture {
        let ambiguousMessage: ChatMessage
        let recoveryMessage: ChatMessage
        let partialMessage: ChatMessage
        let partialThing: Thing
        let partialEvent: LedgerEvent
        let partialRule: LedgerRule
        let partialNote: LedgerNote
        let duplicateTarget: Thing
        let duplicateSource: Thing
        let duplicateEvent: LedgerEvent
        let duplicateRule: LedgerRule
        let duplicateNote: LedgerNote
        let conflictEvent: LedgerEvent
    }

    func makeFixture(in context: ModelContext) throws -> MatrixFixture {
        let ambiguousMessage = ChatMessage(
            id: messageID,
            role: .user,
            text: "Maybe serviced the blue wagon last Tuesday, not sure if this was oil or inspection.",
            createdAt: scenarioNow,
            extractionStatus: .needsReview
        )
        let recoveryMessage = ChatMessage(
            id: recoveryMessageID,
            role: .user,
            text: "Need to retry this entry when the connection returns.",
            createdAt: scenarioNow,
            extractionStatus: .pendingToken,
            extractionErrorCode: .missingServiceToken
        )
        let partialMessage = ChatMessage(
            id: partialMessageID,
            role: .user,
            text: "Saved the kitchen filter note but reminder creation failed.",
            createdAt: scenarioNow,
            extractionStatus: .partiallySucceeded
        )
        let partialThing = Thing(id: partialThingID, name: "Kitchen Filter", createdAt: scenarioNow, updatedAt: scenarioNow)
        let partialEvent = LedgerEvent(
            id: partialEventID,
            title: "Kitchen filter replaced",
            occurredAt: scenarioNow,
            rawText: "Kitchen filter replaced.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            thing: partialThing
        )
        let partialRule = LedgerRule(
            id: partialRuleID,
            title: "Replace kitchen filter again",
            ruleType: .reminder,
            startsAt: scenarioNow.addingTimeInterval(90 * 86_400),
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            thing: partialThing
        )
        let partialNote = LedgerNote(
            id: partialNoteID,
            text: "Kitchen filter size is 16x20.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            linkedThings: [partialThing]
        )
        let partialAttempt = ExtractionAttempt(
            status: .partiallySucceeded,
            createdEventIDs: [partialEvent.id],
            createdRuleIDs: [partialRule.id],
            createdNoteIDs: [partialNote.id],
            createdThingIDs: [partialThing.id],
            sourceMessage: partialMessage
        )
        let duplicateTarget = Thing(id: thingAID, name: "Blue Wagon", createdAt: scenarioNow, updatedAt: scenarioNow)
        let duplicateSource = Thing(
            id: thingBID,
            name: "blue wagon",
            details: "Garage shelf",
            createdAt: scenarioNow,
            updatedAt: scenarioNow
        )
        let duplicateEvent = LedgerEvent(
            id: duplicateEventID,
            title: "Blue wagon service",
            occurredAt: scenarioNow,
            rawText: "Serviced wagon.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            thing: duplicateSource
        )
        let duplicateRule = LedgerRule(
            id: duplicateRuleID,
            title: "Blue wagon inspection",
            ruleType: .reminder,
            startsAt: scenarioNow.addingTimeInterval(30 * 86_400),
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            thing: duplicateSource
        )
        let duplicateNote = LedgerNote(
            id: duplicateNoteID,
            text: "Keep receipt in folder.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            linkedThings: [duplicateSource]
        )
        let conflictEvent = LedgerEvent(
            id: conflictEventID,
            title: "Window service renewal",
            occurredAt: scenarioNow,
            rawText: "Renewed window service, due 2026-05-15.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            eventType: .renewal,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .dueDate,
                    valueKind: .date,
                    dateValue: "2026-05-15",
                    sourceText: "due 2026-05-15"
                ),
            ]
        )
        context.insert(ambiguousMessage)
        context.insert(recoveryMessage)
        context.insert(partialMessage)
        context.insert(partialThing)
        context.insert(partialEvent)
        context.insert(partialRule)
        context.insert(partialNote)
        context.insert(partialAttempt)
        context.insert(duplicateTarget)
        context.insert(duplicateSource)
        context.insert(duplicateEvent)
        context.insert(duplicateRule)
        context.insert(duplicateNote)
        context.insert(conflictEvent)
        try context.save()
        return MatrixFixture(
            ambiguousMessage: ambiguousMessage,
            recoveryMessage: recoveryMessage,
            partialMessage: partialMessage,
            partialThing: partialThing,
            partialEvent: partialEvent,
            partialRule: partialRule,
            partialNote: partialNote,
            duplicateTarget: duplicateTarget,
            duplicateSource: duplicateSource,
            duplicateEvent: duplicateEvent,
            duplicateRule: duplicateRule,
            duplicateNote: duplicateNote,
            conflictEvent: conflictEvent
        )
    }

    func assertItem(
        _ item: LedgerReviewItem,
        kind: LedgerReviewItemKind,
        targetType: LedgerReviewItemTargetType,
        targetID: UUID,
        confidence: Double,
        title: String,
        actionTitle: String,
        detailContains detailFragments: [String],
        evidence expectedEvidence: [(sourceType: LedgerReviewItemTargetType, sourceID: UUID)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(item.kind, kind, file: file, line: line)
        XCTAssertEqual(item.state, .candidate, file: file, line: line)
        XCTAssertEqual(item.targetType, targetType, file: file, line: line)
        XCTAssertEqual(item.targetID, targetID, file: file, line: line)
        XCTAssertEqual(item.confidence, confidence, file: file, line: line)
        XCTAssertEqual(item.title, title, file: file, line: line)
        XCTAssertEqual(item.actionTitle, actionTitle, file: file, line: line)
        XCTAssertEqual(item.createdAt, scenarioNow, file: file, line: line)
        XCTAssertEqual(item.updatedAt, scenarioNow, file: file, line: line)
        XCTAssertTrue(item.dedupeKey.hasPrefix(kind.rawValue), file: file, line: line)
        for fragment in detailFragments {
            XCTAssertTrue(item.detail.contains(fragment), "\(item.detail) should contain \(fragment)", file: file, line: line)
        }
        for expected in expectedEvidence {
            XCTAssertTrue(
                item.evidence.contains { $0.sourceType == expected.sourceType && $0.sourceID == expected.sourceID },
                "Missing evidence \(expected.sourceType.rawValue) \(expected.sourceID)",
                file: file,
                line: line
            )
        }
        XCTAssertFalse(item.evidence.isEmpty, file: file, line: line)
    }

    func assertEntry(
        _ entry: LedgerReviewQueueEntry,
        for item: LedgerReviewItem,
        correctionClass: LedgerReviewCorrectionClass,
        blocked: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entry.itemID, item.id, file: file, line: line)
        XCTAssertEqual(entry.title, item.title, file: file, line: line)
        XCTAssertEqual(entry.detail, item.detail, file: file, line: line)
        XCTAssertEqual(entry.correctionClass, correctionClass, file: file, line: line)
        XCTAssertEqual(entry.primaryActionTitle, item.actionTitle, file: file, line: line)
        XCTAssertEqual(entry.isActionBlocked, blocked, file: file, line: line)
        XCTAssertEqual(entry.blockedMessage != nil, blocked, file: file, line: line)
    }

    func item(
        from items: [LedgerReviewItem],
        kind: LedgerReviewItemKind,
        targetID: UUID
    ) throws -> LedgerReviewItem {
        try XCTUnwrap(items.first { $0.kind == kind && $0.targetID == targetID })
    }

    func duplicateItem(from items: [LedgerReviewItem], sourceIDs: [UUID]) throws -> LedgerReviewItem {
        let expectedIDs = Set(sourceIDs)
        return try XCTUnwrap(items.first { item in
            item.kind == .duplicateThing && Set(item.evidence.map(\.sourceID)) == expectedIDs
        })
    }

    func generationService(_ context: ModelContext) -> LedgerReviewItemGenerationService {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return LedgerReviewItemGenerationService(modelContext: context, now: { self.scenarioNow }, calendar: calendar)
    }

    func queueService(
        _ context: ModelContext,
        tokenStore: any DeviceTokenStore = InMemoryDeviceTokenStore(token: "test-device-token")
    ) -> LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: tokenStore,
            dateProvider: TestDateProvider(now: scenarioNow)
        )
    }

    func date(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    var scenarioNow: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    var messageID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000101")! }
    var recoveryMessageID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000102")! }
    var partialMessageID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000103")! }
    var retryMessageID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000104")! }
    var thingAID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000201")! }
    var thingBID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000202")! }
    var partialThingID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000203")! }
    var eventID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000301")! }
    var duplicateEventID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000302")! }
    var partialEventID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000303")! }
    var conflictEventID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000304")! }
    var ruleID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000401")! }
    var duplicateRuleID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000402")! }
    var partialRuleID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000403")! }
    var missingRuleID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000404")! }
    var partialNoteID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000501")! }
    var duplicateNoteID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000502")! }
}
