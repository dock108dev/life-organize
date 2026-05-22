import SwiftData
import XCTest
@testable import LifeOrganize

final class SwiftDataMigrationTests: XCTestCase {
    func testV1StoreMigratesToActiveSchemaAndPreservesLedgerRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LifeOrganizeMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "Ledger.store")
        let seed = MigrationSeed()

        try createV1Store(at: storeURL, seed: seed)

        let container = ModelContainerFactory.make(storeURL: storeURL)
        let context = ModelContext(container)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())

        XCTAssertEqual(messages.map(\.id), [seed.messageID])
        XCTAssertEqual(messages.first?.text, "Changed HVAC filter and set a replacement reminder.")
        XCTAssertEqual(attempts.map(\.id), [seed.attemptID])
        XCTAssertEqual(things.map(\.id), [seed.thingID])
        XCTAssertEqual(events.map(\.id), [seed.eventID])
        XCTAssertEqual(events.first?.thing?.id, seed.thingID)
        XCTAssertEqual(events.first?.sourceMessage?.id, seed.messageID)
        XCTAssertEqual(events.first?.eventType, .generic)
        XCTAssertEqual(events.first?.metadataEntries, [])
        XCTAssertEqual(events.first?.metadataKeyRawValues, [])
        XCTAssertEqual(rules.map(\.id), [seed.ruleID])
        XCTAssertEqual(rules.first?.thing?.id, seed.thingID)
        XCTAssertEqual(rules.first?.ruleType, .restriction)
        XCTAssertEqual(rules.first?.continuityBehavior, .ongoing)
        XCTAssertEqual(rules.first?.lifecycleState, .open)
        XCTAssertEqual(notes.map(\.id), [seed.noteID])
        XCTAssertEqual(notes.first?.linkedThings.map(\.id), [seed.thingID])
        XCTAssertEqual(links.map(\.id), [seed.linkID])
    }

    func testV2StoreMigratesToActiveSchemaAndPreservesLedgerRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LifeOrganizeMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "Ledger.store")
        let seed = MigrationSeed()

        try createV2Store(at: storeURL, seed: seed)

        let container = ModelContainerFactory.make(storeURL: storeURL)
        let context = ModelContext(container)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let attempts = try context.fetch(FetchDescriptor<ExtractionAttempt>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())

        XCTAssertEqual(messages.map(\.id), [seed.messageID])
        XCTAssertEqual(attempts.map(\.id), [seed.attemptID])
        XCTAssertEqual(things.map(\.id), [seed.thingID])
        XCTAssertEqual(events.map(\.id), [seed.eventID])
        XCTAssertEqual(events.first?.eventType, .maintenance)
        XCTAssertEqual(events.first?.thing?.id, seed.thingID)
        XCTAssertEqual(rules.map(\.id), [seed.ruleID])
        XCTAssertEqual(rules.first?.ruleType, .reminder)
        XCTAssertEqual(rules.first?.continuityBehavior, .dateBasedReminder)
        XCTAssertEqual(rules.first?.lifecycleState, .deactivated)
        XCTAssertFalse(rules.first?.isActive ?? true)
        XCTAssertEqual(rules.first?.manuallyDeactivatedAt, seed.deactivatedAt)
        XCTAssertEqual(notes.map(\.id), [seed.noteID])
        XCTAssertEqual(notes.first?.linkedThings.map(\.id), [seed.thingID])
        XCTAssertEqual(links.map(\.id), [seed.linkID])
    }

    func testVersionedSchemasKeepPersistedModelNamesStable() {
        let historicalNames = [
            "ChatMessage",
            "ExtractionAttempt",
            "EntityLink",
            "Thing",
            "LedgerEvent",
            "LedgerRule",
            "LedgerNote",
        ]
        let activeNames = historicalNames + ["LedgerReviewItem"]

        XCTAssertEqual(LifeOrganizeSchemaV1.models.map { String(describing: $0) }, historicalNames)
        XCTAssertEqual(LifeOrganizeSchemaV2.models.map { String(describing: $0) }, historicalNames)
        XCTAssertEqual(LifeOrganizeSchemaV3.models.map { String(describing: $0) }, activeNames)
        XCTAssertTrue(LifeOrganizeSchemaV2.models.allSatisfy { String(reflecting: $0).contains("LifeOrganizeSchemaV2") })
        XCTAssertFalse(LifeOrganizeSchemaV3.models.contains { String(reflecting: $0).contains("LifeOrganizeSchemaV2") })
    }

    private func createV1Store(at storeURL: URL, seed: MigrationSeed) throws {
        let schema = Schema(versionedSchema: LifeOrganizeSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let message = LifeOrganizeSchemaV1.ChatMessage(
            id: seed.messageID,
            roleRawValue: ChatRole.user.rawValue,
            text: "Changed HVAC filter and set a replacement reminder.",
            createdAt: seed.createdAt,
            rawLLMResponse: #"{"events":[],"rules":[],"notes":[],"things":[]}"#,
            extractionStatusRawValue: ExtractionStatus.succeeded.rawValue,
            extractionVersion: 1
        )
        let attempt = LifeOrganizeSchemaV1.ExtractionAttempt(
            id: seed.attemptID,
            statusRawValue: ExtractionAttemptStatus.succeeded.rawValue,
            schemaVersion: 1,
            promptVersion: "migration-test",
            normalizedJSONText: ExtractionEnvelope.emptyJSON(),
            startedAt: seed.createdAt,
            completedAt: seed.createdAt,
            createdEventIDs: [seed.eventID],
            createdRuleIDs: [seed.ruleID],
            createdNoteIDs: [seed.noteID],
            createdThingIDs: [seed.thingID],
            sourceMessage: message
        )
        let thing = LifeOrganizeSchemaV1.Thing(
            id: seed.thingID,
            name: "HVAC",
            normalizedKey: "hvac",
            details: "Home system",
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceMessageIDs: [seed.messageID],
            sourceExtractionAttemptIDs: [seed.attemptID],
            eventCount: 1,
            lastEventAt: seed.createdAt
        )
        let event = LifeOrganizeSchemaV1.LedgerEvent(
            id: seed.eventID,
            title: "Changed HVAC filter",
            occurredAt: seed.createdAt,
            rawText: message.text,
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceClientID: "event_1",
            sourceExtractionRunID: seed.attemptID,
            thing: thing,
            sourceMessage: message
        )
        let rule = LifeOrganizeSchemaV1.LedgerRule(
            id: seed.ruleID,
            title: "Replace HVAC filter",
            reason: "Replace the filter again later.",
            rawText: message.text,
            startsAt: seed.createdAt,
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceClientID: "rule_1",
            sourceExtractionRunID: seed.attemptID,
            thing: thing,
            sourceMessage: message
        )
        let note = LifeOrganizeSchemaV1.LedgerNote(
            id: seed.noteID,
            text: "Filter size is 20x25x1.",
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceClientID: "note_1",
            sourceExtractionRunID: seed.attemptID,
            sourceMessage: message,
            linkedThings: [thing]
        )
        let link = LifeOrganizeSchemaV1.EntityLink(
            id: seed.linkID,
            sourceTypeRawValue: EntityLinkType.chatMessage.rawValue,
            sourceID: seed.messageID,
            targetTypeRawValue: EntityLinkType.event.rawValue,
            targetID: seed.eventID,
            relationRawValue: EntityLinkRelation.extractedFrom.rawValue,
            createdAt: seed.createdAt,
            confidence: 1,
            createdByRawValue: EntityLinkCreator.extraction.rawValue,
            sourceMessageID: seed.messageID
        )

        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(link)
        try context.save()
    }

    private func createV2Store(at storeURL: URL, seed: MigrationSeed) throws {
        let schema = Schema(versionedSchema: LifeOrganizeSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let message = LifeOrganizeSchemaV2.ChatMessage(
            id: seed.messageID,
            roleRawValue: ChatRole.user.rawValue,
            text: "Replaced HVAC filter and marked the reminder done.",
            createdAt: seed.createdAt,
            rawLLMResponse: #"{"events":[],"rules":[],"notes":[],"things":[]}"#,
            extractionStatusRawValue: ExtractionStatus.succeeded.rawValue,
            extractionVersion: 2
        )
        let attempt = LifeOrganizeSchemaV2.ExtractionAttempt(
            id: seed.attemptID,
            statusRawValue: ExtractionAttemptStatus.succeeded.rawValue,
            schemaVersion: 2,
            promptVersion: "migration-test",
            normalizedJSONText: ExtractionEnvelope.emptyJSON(),
            startedAt: seed.createdAt,
            completedAt: seed.createdAt,
            createdEventIDs: [seed.eventID],
            createdRuleIDs: [seed.ruleID],
            createdNoteIDs: [seed.noteID],
            createdThingIDs: [seed.thingID],
            sourceMessage: message
        )
        let thing = LifeOrganizeSchemaV2.Thing(
            id: seed.thingID,
            name: "HVAC",
            normalizedKey: "hvac",
            details: "Home system",
            createdAt: seed.createdAt,
            updatedAt: seed.deactivatedAt,
            sourceMessageIDs: [seed.messageID],
            sourceExtractionAttemptIDs: [seed.attemptID],
            eventCount: 1,
            lastEventAt: seed.createdAt
        )
        let event = LifeOrganizeSchemaV2.LedgerEvent(
            id: seed.eventID,
            title: "Replaced HVAC filter",
            occurredAt: seed.createdAt,
            rawText: message.text,
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceClientID: "event_1",
            sourceExtractionRunID: seed.attemptID,
            thing: thing,
            sourceMessage: message
        )
        event.eventTypeRawValue = LedgerEventType.maintenance.rawValue
        let rule = LifeOrganizeSchemaV2.LedgerRule(
            id: seed.ruleID,
            title: "Replace HVAC filter",
            reason: "Done today.",
            rawText: message.text,
            startsAt: seed.createdAt,
            createdAt: seed.createdAt,
            updatedAt: seed.deactivatedAt,
            sourceClientID: "rule_1",
            sourceExtractionRunID: seed.attemptID,
            thing: thing,
            sourceMessage: message
        )
        rule.isActive = false
        rule.manuallyDeactivatedAt = seed.deactivatedAt
        rule.ruleTypeRawValue = LedgerRuleType.reminder.rawValue
        rule.continuityBehaviorRawValue = LedgerContinuityBehavior.dateBasedReminder.rawValue
        let note = LifeOrganizeSchemaV2.LedgerNote(
            id: seed.noteID,
            text: "Filter size is 20x25x1.",
            createdAt: seed.createdAt,
            updatedAt: seed.createdAt,
            sourceClientID: "note_1",
            sourceExtractionRunID: seed.attemptID,
            sourceMessage: message,
            linkedThings: [thing]
        )
        let link = LifeOrganizeSchemaV2.EntityLink(
            id: seed.linkID,
            sourceTypeRawValue: EntityLinkType.chatMessage.rawValue,
            sourceID: seed.messageID,
            targetTypeRawValue: EntityLinkType.rule.rawValue,
            targetID: seed.ruleID,
            relationRawValue: EntityLinkRelation.extractedFrom.rawValue,
            createdAt: seed.createdAt,
            confidence: 1,
            createdByRawValue: EntityLinkCreator.extraction.rawValue,
            sourceMessageID: seed.messageID
        )

        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(link)
        try context.save()
    }
}

private struct MigrationSeed {
    let messageID = UUID()
    let attemptID = UUID()
    let thingID = UUID()
    let eventID = UUID()
    let ruleID = UUID()
    let noteID = UUID()
    let linkID = UUID()
    let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let deactivatedAt = Date(timeIntervalSinceReferenceDate: 800_086_400)
}
