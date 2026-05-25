import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class PersistenceCoverageTests: XCTestCase {
    func testModelContainerFactoryCreatesStandardInMemoryAndURLBackedStores() throws {
        _ = try ModelContext(ModelContainerFactory.make(configuration: .standard))
            .fetch(FetchDescriptor<ChatMessage>())

        let inMemoryContext = ModelContext(ModelContainerFactory.make(configuration: .inMemory))
        inMemoryContext.insert(ChatMessage(role: .user, text: "In-memory persistence check."))
        try inMemoryContext.save()
        XCTAssertEqual(try inMemoryContext.fetch(FetchDescriptor<ChatMessage>()).count, 1)

        let directory = try makeTemporaryDirectory(prefix: "LifeOrganize-ModelContainerFactory")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Ledger.store")
        try writeURLBackedMessage(at: storeURL)

        let reopenedContext = ModelContext(ModelContainerFactory.make(configuration: .store(url: storeURL)))
        XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<ChatMessage>()).map(\.text), ["URL-backed persistence check."])
    }

    func testActiveSchemaURLStoreReopensAndPreservesCurrentModels() throws {
        let directory = try makeTemporaryDirectory(prefix: "LifeOrganize-ActiveSchemaStore")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Ledger.store")
        let ids = try writeCurrentSchemaRecords(at: storeURL)

        let context = ModelContext(ModelContainerFactory.make(storeURL: storeURL))

        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).map(\.id), [ids.message])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).map(\.id), [ids.attempt])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).map(\.id), [ids.thing])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).map(\.id), [ids.event])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).map(\.id), [ids.rule])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).map(\.id), [ids.note])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).map(\.id), [ids.reviewItem])
        XCTAssertEqual(try context.fetch(FetchDescriptor<EntityLink>()).map(\.id), [ids.link])
    }

    func testMigrationPlanAndActiveSchemaDeclareExpectedRuntimeSurface() {
        XCTAssertEqual(LifeOrganizeMigrationPlan.schemas.map { String(describing: $0) }, [
            "LifeOrganizeSchemaV1",
            "LifeOrganizeSchemaV2",
            "LifeOrganizeSchemaV3"
        ])
        XCTAssertEqual(LifeOrganizeMigrationPlan.stages.count, 2)
        XCTAssertEqual(LifeOrganizeSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(ModelContainerFactory.modelTypeNames, Set(LifeOrganizeSchemaV3.models.map { String(describing: $0) }))
    }

    func testSeedLoaderHonorsAutomationGateAliasesAndFixtureFallback() throws {
        let gatedContainer = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(["overview-basic"], into: gatedContainer, isAutomationRuntime: false)
        XCTAssertTrue(try ModelContext(gatedContainer).fetch(FetchDescriptor<Thing>()).isEmpty)

        let fixture = try SeedScenarioLoader.fixture(for: .carMaintenance)
        XCTAssertEqual(fixture.id, "car_maintenance")
        XCTAssertFalse(fixture.records.events.isEmpty)

        let seededContainer = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(["overview-basic", "review-partial"], into: seededContainer, isAutomationRuntime: true)
        let context = ModelContext(seededContainer)

        XCTAssertFalse(try context.fetch(FetchDescriptor<ChatMessage>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<LedgerEvent>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<LedgerReviewItem>()).isEmpty)
    }

    func testScreenshotSeedScenariosLoadExpectedRecords() throws {
        let scenarioIDs = SeedScenario.allCases.map(\.fixtureID)
        let container = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(scenarioIDs, into: container, isAutomationRuntime: true)
        let context = ModelContext(container)

        let fixtures = try scenarioIDs.map(ScenarioFixture.load)
        let expectedCounts = fixtures.reduce(ScenarioCounts()) { partial, fixture in
            partial.adding(fixture.records)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, expectedCounts.chatMessages)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, expectedCounts.things)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, expectedCounts.events)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, expectedCounts.rules)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).count, expectedCounts.notes)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerReviewItem>()).count, expectedCounts.reviewItems)
    }

    func testThingDeletionWithReassignmentKeepsDependentProjectionsCurrent() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let source = Thing(name: "Legacy Vendor")
        let target = Thing(name: "Current Vendor")
        let message = ChatMessage(role: .user, text: "Recorded vendor work.", createdAt: now, extractionStatus: .partiallySucceeded)
        let event = LedgerEvent(title: "Completed renewal", occurredAt: now, rawText: "Recorded renewal.", thing: source, sourceMessage: message)
        let rule = LedgerRule(title: "Review renewal", ruleType: .reminder, startsAt: now, thing: source, sourceMessage: message)
        let note = LedgerNote(text: "Renewal notes", createdAt: now, updatedAt: now, sourceMessage: message, linkedThings: [source])
        let attempt = ExtractionAttempt(
            status: .partiallySucceeded,
            startedAt: now,
            createdEventIDs: [event.id],
            createdRuleIDs: [rule.id],
            createdNoteIDs: [note.id],
            createdThingIDs: [source.id],
            sourceMessage: message
        )
        let link = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: source.id,
            relation: .mentionsThing,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        let reviewItem = LedgerReviewItem(
            dedupeKey: "vendor-normalization-\(source.id.uuidString)",
            kind: .normalizationCandidate,
            title: "Review vendor records",
            detail: "Records can be attached to the current vendor.",
            targetType: .thing,
            targetID: source.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: source.id, summary: source.name, detail: nil),
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .none, sourceID: note.id, summary: note.text, detail: nil)
            ],
            createdAt: now,
            updatedAt: now
        )
        context.insert(source)
        context.insert(target)
        context.insert(message)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(attempt)
        context.insert(link)
        context.insert(reviewItem)

        try DerivedFieldMaintenanceService(modelContext: context, now: { now }).deleteThing(source, reassigningRecordsTo: target)
        try context.save()

        XCTAssertFalse(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(attempt.createdThingIDs, [target.id])
        XCTAssertEqual(reviewItem.targetID, target.id)
        XCTAssertTrue(reviewItem.evidence.contains { $0.sourceType == .thing && $0.sourceID == target.id })
        XCTAssertFalse(try context.fetch(FetchDescriptor<EntityLink>()).contains { $0.sourceID == source.id || $0.targetID == source.id })

        try assertStoreIntegrity(context, now: now)
        try assertExportAuditPasses(context, scenarioID: "thing-reassignment")
        assertProjectionText("Legacy Vendor", isAbsentFrom: context, now: now)
        XCTAssertEqual(ThingDetailSnapshot(thing: target, now: now).countSummary, "1 event · 1 note · 1 active reminder")
        XCTAssertEqual(try LedgerReviewQueueService(modelContext: context, deviceTokenStore: InMemoryDeviceTokenStore(token: "token")).entries(from: [reviewItem]).count, 1)
    }

    func testDeletingLedgerRecordsClearsReviewReferencesAndProjectionTargets() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let thing = Thing(name: "HVAC")
        let event = LedgerEvent(title: "Changed filter", occurredAt: now, rawText: "Changed filter.", thing: thing)
        let rule = LedgerRule(title: "Replace filter", ruleType: .reminder, startsAt: now, thing: thing)
        let note = LedgerNote(text: "Filter size 20x25x1", createdAt: now, updatedAt: now, linkedThings: [thing])
        let reviewItem = LedgerReviewItem(
            dedupeKey: "record-cleanup-\(event.id.uuidString)",
            kind: .conflictingDate,
            title: "Review dated records",
            detail: "Saved records need cleanup.",
            targetType: .event,
            targetID: event.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .none, sourceID: note.id, summary: note.text, detail: nil)
            ],
            createdAt: now,
            updatedAt: now
        )
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(reviewItem)

        let maintenance = DerivedFieldMaintenanceService(modelContext: context, now: { now })
        try maintenance.deleteEvent(event)
        try maintenance.deleteRule(rule)
        try maintenance.deleteNote(note)
        try context.save()

        XCTAssertEqual(reviewItem.state, .superseded)
        XCTAssertNil(reviewItem.targetID)
        XCTAssertTrue(reviewItem.evidence.isEmpty)
        XCTAssertTrue(try LedgerReviewQueueService(modelContext: context, deviceTokenStore: InMemoryDeviceTokenStore(token: "token")).entries(from: [reviewItem]).isEmpty)
        XCTAssertTrue(SearchService().search("filter", in: SearchService().records(things: [thing])).isEmpty)
        XCTAssertTrue(TimelineSliceProjection(now: now).rows(things: [thing], events: [], reminders: [], notes: []).allSatisfy { $0.sourceKind == .thing })
        try assertStoreIntegrity(context, now: now)
        try assertExportAuditPasses(context, scenarioID: "record-deletion")
    }

    func testLocalClearLeavesNoExportedRecordsAndPreservesExplicitTokenLifecycle() throws {
        let context = makeInMemoryModelContext()
        let tokenStore = InMemoryDeviceTokenStore()
        try tokenStore.saveDeviceToken("unit-test-token")
        context.insert(ChatMessage(role: .user, text: "Clear me.", createdAt: fixedTestNow))
        context.insert(Thing(name: "Temporary"))
        try context.save()

        try LocalDataClearService(modelContext: context).clearLedgerData()

        let envelope = try LocalJSONExportService(modelContext: context).envelope()
        XCTAssertTrue(envelope.records.chatMessages.isEmpty)
        XCTAssertTrue(envelope.records.things.isEmpty)
        XCTAssertEqual(try tokenStore.loadDeviceToken(), "unit-test-token")

        try tokenStore.deleteDeviceToken()
        XCTAssertNil(try tokenStore.loadDeviceToken())
    }

    private func writeURLBackedMessage(at storeURL: URL) throws {
        let context = ModelContext(ModelContainerFactory.make(storeURL: storeURL))
        context.insert(ChatMessage(role: .user, text: "URL-backed persistence check."))
        try context.save()
    }

    private func writeCurrentSchemaRecords(at storeURL: URL) throws -> CurrentSchemaIDs {
        let context = ModelContext(ModelContainerFactory.make(storeURL: storeURL))
        let now = fixedTestNow
        let message = ChatMessage(role: .user, text: "Persist every model.", createdAt: now, extractionStatus: .partiallySucceeded)
        let thing = Thing(name: "Persistence", createdAt: now, updatedAt: now)
        let event = LedgerEvent(title: "Saved event", occurredAt: now, rawText: message.text, thing: thing, sourceMessage: message)
        let rule = LedgerRule(title: "Saved reminder", ruleType: .reminder, startsAt: now, thing: thing, sourceMessage: message)
        let note = LedgerNote(text: "Saved note", createdAt: now, updatedAt: now, sourceMessage: message, linkedThings: [thing])
        let attempt = ExtractionAttempt(
            status: .partiallySucceeded,
            startedAt: now,
            createdEventIDs: [event.id],
            createdRuleIDs: [rule.id],
            createdNoteIDs: [note.id],
            createdThingIDs: [thing.id],
            sourceMessage: message
        )
        let reviewItem = LedgerReviewItem(
            dedupeKey: "active-schema-\(thing.id.uuidString)",
            kind: .normalizationCandidate,
            title: "Review persisted records",
            detail: "Current schema review item.",
            targetType: .thing,
            targetID: thing.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil)],
            createdAt: now,
            updatedAt: now
        )
        let link = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .mentionsThing,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(reviewItem)
        context.insert(link)
        try context.save()
        return CurrentSchemaIDs(
            message: message.id,
            attempt: attempt.id,
            thing: thing.id,
            event: event.id,
            rule: rule.id,
            note: note.id,
            reviewItem: reviewItem.id,
            link: link.id
        )
    }

    private func assertStoreIntegrity(_ context: ModelContext, now: Date, line: UInt = #line) throws {
        let result = try ScenarioRelationshipIntegrityValidator(modelContext: context).validate(now: now)
        XCTAssertFalse(result.hasErrors, result.failures.map(\.description).joined(separator: "\n"), line: line)
    }

    private func assertExportAuditPasses(_ context: ModelContext, scenarioID: String, line: UInt = #line) throws {
        let envelope = try LocalJSONExportService(modelContext: context).envelope()
        let report = RelationshipAuditService().audit(envelope, scenarioId: scenarioID)
        XCTAssertEqual(report.status, "passed", RelationshipAuditService().markdown(for: report), line: line)
    }

    private func assertProjectionText(_ text: String, isAbsentFrom context: ModelContext, now: Date, line: UInt = #line) {
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<LedgerEvent>())) ?? []
        let rules = (try? context.fetch(FetchDescriptor<LedgerRule>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<LedgerNote>())) ?? []
        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []
        let links = (try? context.fetch(FetchDescriptor<EntityLink>())) ?? []
        let searchResults = SearchService().search(text, in: SearchService().records(things: things, events: events, rules: rules, notes: notes, messages: messages))
        let timelineRows = TimelineSliceProjection(now: now).rows(messages: messages, things: things, events: events, reminders: rules, notes: notes, entityLinks: links)

        XCTAssertTrue(searchResults.isEmpty, line: line)
        XCTAssertFalse(timelineRows.contains { row in row.linkedThings.contains { thing in thing.name == text } }, line: line)
    }
}

private struct CurrentSchemaIDs {
    let message: UUID
    let attempt: UUID
    let thing: UUID
    let event: UUID
    let rule: UUID
    let note: UUID
    let reviewItem: UUID
    let link: UUID
}

private struct ScenarioCounts {
    var chatMessages = 0
    var things = 0
    var events = 0
    var rules = 0
    var notes = 0
    var reviewItems = 0

    func adding(_ records: ExportRecords) -> ScenarioCounts {
        ScenarioCounts(
            chatMessages: chatMessages + records.chatMessages.count,
            things: things + records.things.count,
            events: events + records.events.count,
            rules: rules + records.rules.count,
            notes: notes + records.notes.count,
            reviewItems: reviewItems + records.ledgerReviewItems.count
        )
    }
}
