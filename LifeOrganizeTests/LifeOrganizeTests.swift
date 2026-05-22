import SwiftData
import XCTest
@testable import LifeOrganize

final class LifeOrganizeTests: XCTestCase {
    func testAppShellLaunchesIntoLogTab() {
        XCTAssertEqual(AppRootView.initialTab, .log)
    }

    func testAppShellUsesOnlyCurrentPrimaryTabs() {
        XCTAssertEqual(AppTab.allCases, V1ScopeContract.activeRootTabs)
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Timeline", "Things", "Carry Forward"])
    }

    func testAppShellAvoidsOutOfScopePrimaryTabLabels() {
        let forbiddenLabels = [
            "Dashboard",
            "Calendar",
            "Analytics",
            "Profile",
            "Account",
            "Today",
            "Memory Hub",
            "AI Ledger",
            "Life OS",
            "Insights",
            "Assistant",
            "Settings",
        ]

        XCTAssertTrue(Set(AppTab.allCases.map(\.title)).isDisjoint(with: forbiddenLabels))
    }

    func testInMemoryModelContainerCanBeCreated() {
        _ = ModelContainerFactory.make(inMemory: true)
    }

    func testAPIKeyStoreTrimsReplacesAndDeletesKey() throws {
        let store = InMemoryAPIKeyStore()

        try store.saveOpenAIAPIKey("  unit-test-key-old  ")
        XCTAssertEqual(try store.loadOpenAIAPIKey(), "unit-test-key-old")

        try store.saveOpenAIAPIKey("unit-test-key-new")
        XCTAssertEqual(try store.loadOpenAIAPIKey(), "unit-test-key-new")

        try store.deleteOpenAIAPIKey()
        XCTAssertNil(try store.loadOpenAIAPIKey())
        XCTAssertThrowsError(try store.saveOpenAIAPIKey("   "))
    }

    func testRuleStatusMarksExpiredRulesInactive() {
        let rule = LedgerRule(
            title: "No buying domains",
            startsAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertFalse(RuleStatusService().isActive(rule, at: Date(timeIntervalSince1970: 101)))
        XCTAssertEqual(RuleStatusService().status(for: rule, at: Date(timeIntervalSince1970: 100)), .expired)
    }

    func testRuleStatusHonorsFutureStartNoExpirationAndManualDeactivation() {
        let futureRule = LedgerRule(
            title: "No monitors",
            startsAt: Date(timeIntervalSince1970: 200),
            expiresAt: nil
        )
        let noExpirationRule = LedgerRule(
            title: "No new equipment",
            startsAt: Date(timeIntervalSince1970: 0),
            expiresAt: nil
        )
        let deactivatedRule = LedgerRule(
            title: "No domains",
            startsAt: Date(timeIntervalSince1970: 0),
            manuallyDeactivatedAt: Date(timeIntervalSince1970: 50)
        )
        let statusService = RuleStatusService()

        XCTAssertFalse(statusService.isActive(futureRule, at: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(statusService.status(for: futureRule, at: Date(timeIntervalSince1970: 100)), .scheduled)
        XCTAssertTrue(statusService.isActive(noExpirationRule, at: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(statusService.expirationDisplay(for: noExpirationRule, at: Date(timeIntervalSince1970: 100)), "No expiration")
        XCTAssertFalse(statusService.isActive(deactivatedRule, at: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(statusService.status(for: deactivatedRule, at: Date(timeIntervalSince1970: 100)), .inactive)
    }

    func testRuleStatusDaysRemainingUsesExclusiveExpirationDate() {
        let statusService = RuleStatusService()
        let now = fixedTestNow
        let expiresAt = Date(timeIntervalSince1970: 1_802_592_000)

        XCTAssertEqual(statusService.daysRemaining(until: expiresAt, at: now), 30)
        XCTAssertEqual(statusService.daysRemainingDisplay(until: expiresAt, at: now), "30 days left.")
    }

    func testReminderStatusDisplaysDueDateInsteadOfNoExpiration() throws {
        let statusService = RuleStatusService()
        let dueDate = try XCTUnwrap(ExtractionService.parseDate("2027-03-15"))
        let reminder = LedgerRule(
            title: "Replace air filters",
            ruleType: .reminder,
            rawText: "Replace air filters in 2 months",
            startsAt: dueDate,
            expiresAt: nil,
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow
        )

        XCTAssertEqual(statusService.status(for: reminder, at: fixedTestNow), .scheduled)
        XCTAssertEqual(statusService.expirationDisplay(for: reminder, at: fixedTestNow), "Due March 15, 2027")
        XCTAssertEqual(statusService.expirationDisplay(for: reminder, at: dueDate), "Due today")
    }

    func testExtractedRecordsKeepSourceMessageRelationships() throws {
        let context = makeInMemoryModelContext()
        let now = fixedTestNow
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today. No buying domains for 30 days.",
            createdAt: now,
            rawLLMResponse: #"{"events":[],"rules":[],"notes":[],"things":[]}"#,
            extractionStatus: .succeeded
        )
        let thing = Thing(name: "Oil Change", aliases: ["oil"], category: .maintenance, createdAt: now, updatedAt: now)
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: now,
            rawText: message.text,
            createdAt: now,
            updatedAt: now,
            sourceClientID: "event-1",
            sourceExtractionRunID: UUID(),
            thing: thing,
            sourceMessage: message
        )
        let rule = LedgerRule(
            title: "No buying domains",
            reason: "30 day pause",
            rawText: message.text,
            startsAt: now,
            createdAt: now,
            updatedAt: now,
            sourceClientID: "rule-1",
            sourceExtractionRunID: UUID(),
            sourceMessage: message
        )
        let note = LedgerNote(
            text: "Oil change logged from chat.",
            createdAt: now,
            updatedAt: now,
            sourceClientID: "note-1",
            sourceExtractionRunID: UUID(),
            sourceMessage: message,
            linkedThings: [thing]
        )

        context.insert(message)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        try context.save()

        XCTAssertEqual(message.extractionStatus, .succeeded)
        XCTAssertEqual(event.sourceMessage?.id, message.id)
        XCTAssertEqual(rule.sourceMessage?.id, message.id)
        XCTAssertEqual(note.sourceMessage?.id, message.id)
        XCTAssertEqual(event.thing?.id, thing.id)
        XCTAssertEqual(note.linkedThingIDs, [thing.id])
    }

    @MainActor
    func testRuleRelatedEventsPreferDirectLinksThenThingHistoryThenTextOverlap() {
        let now = fixedTestNow
        let domains = Thing(name: "Domains", aliases: ["domain names"])
        let rule = LedgerRule(
            title: "No buying domains",
            rawText: "No buying domains for 30 days.",
            startsAt: now,
            thing: domains
        )
        let directEvent = LedgerEvent(
            title: "Bought hosting",
            occurredAt: Date(timeIntervalSince1970: 400),
            rawText: "Bought hosting today.",
            thing: nil
        )
        let sharedThingEvent = LedgerEvent(
            title: "Renewed personal domain",
            occurredAt: Date(timeIntervalSince1970: 300),
            rawText: "Renewed personal domain.",
            thing: domains
        )
        let textOverlapEvent = LedgerEvent(
            title: "Reviewed domain ideas",
            occurredAt: Date(timeIntervalSince1970: 200),
            rawText: "Reviewed domain ideas.",
            thing: nil
        )
        let unrelatedEvent = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 100),
            rawText: "Changed oil.",
            thing: nil
        )
        let link = EntityLink(
            sourceType: .rule,
            sourceID: rule.id,
            targetType: .event,
            targetID: directEvent.id,
            relation: .sameMessage,
            createdBy: .system
        )

        let related = RuleRelatedEventService().relatedEvents(
            for: rule,
            events: [textOverlapEvent, unrelatedEvent, sharedThingEvent, directEvent],
            entityLinks: [link]
        )

        XCTAssertEqual(related.map { $0.event.id }, [directEvent.id, sharedThingEvent.id, textOverlapEvent.id])
        XCTAssertEqual(related.map(\.source), [.sameMessage, .sharedThing, .textOverlap])
    }

    func testDiskBackedModelContainerKeepsMessagesAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LifeOrganizeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "Ledger.store")
        let messageID: UUID

        do {
            let container = ModelContainerFactory.make(storeURL: storeURL)
            let context = ModelContext(container)
            let message = ChatMessage(
                role: .user,
                text: "Replaced HVAC filter.",
                rawLLMResponse: #"{"events":[],"rules":[],"notes":[],"things":[]}"#,
                extractionStatus: .succeeded
            )
            messageID = message.id
            context.insert(message)
            try context.save()
        }

        do {
            let container = ModelContainerFactory.make(storeURL: storeURL)
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.id == messageID
                }
            )
            let messages = try context.fetch(descriptor)

            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?.text, "Replaced HVAC filter.")
            XCTAssertEqual(messages.first?.rawLLMResponse, #"{"events":[],"rules":[],"notes":[],"things":[]}"#)
        }
    }

    @MainActor
    func testClearLocalDataDeletesLedgerRecordsAndKeepsAPIKey() throws {
        let context = makeInMemoryModelContext()
        let keyStore = InMemoryAPIKeyStore()
        let message = ChatMessage(role: .user, text: "Changed oil.", extractionStatus: .succeeded)
        let attempt = ExtractionAttempt(sourceMessage: message)
        let thing = Thing(name: "Oil Change")
        let event = LedgerEvent(title: "Changed oil", occurredAt: Date(), rawText: message.text, thing: thing, sourceMessage: message)
        let rule = LedgerRule(title: "No domains", sourceMessage: message)
        let note = LedgerNote(text: "Remember filter size.", sourceMessage: message, linkedThings: [thing])

        try keyStore.saveOpenAIAPIKey("unit-test-key")
        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        try context.save()

        try LocalDataClearService(modelContext: context).clearLedgerData()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEvent>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerRule>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerNote>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Thing>()).count, 0)
        XCTAssertEqual(try keyStore.loadOpenAIAPIKey(), "unit-test-key")
    }
}
