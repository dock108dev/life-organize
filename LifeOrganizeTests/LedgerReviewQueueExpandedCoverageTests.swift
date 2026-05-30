import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewQueueExpandedCoverageTests: XCTestCase {
    func testGenerationCreatesQueueItemsForReviewInputMatrixAndImportedWebRecords() async throws {
        let context = makeInMemoryModelContext()
        let failed = message("Dryer vent cleaning failed.", status: .failed, errorCode: .serverError)
        let needsReview = message("Maybe renewed the storage lease.", status: .needsReview)
        let retryable = message("Network dropped while logging paint color.", status: .pendingRetry, errorCode: .rateLimited)
        let staleReminder = LedgerRule(
            title: "Renew tenant parking permit",
            ruleType: .deadline,
            startsAt: fixedTestNow.addingTimeInterval(-86_400),
            expiresAt: fixedTestNow.addingTimeInterval(-86_400)
        )
        let duplicateA = Thing(name: "Printer Paper")
        let duplicateB = Thing(name: "printer paper")
        let namingCandidate = Thing(name: "changed oil", normalizedKey: "changed oil")
        context.insert(failed)
        context.insert(needsReview)
        context.insert(retryable)
        context.insert(staleReminder)
        context.insert(duplicateA)
        context.insert(duplicateB)
        context.insert(namingCandidate)
        try context.save()

        let importService = ChatSendService(
            modelContext: context,
            extractor: ThrowingMessageExtractionClient(error: AppError.serverError),
            webRequestClient: StaticWebRequestClient(
                result: WebRequestResult(
                    assistantText: nil,
                    extractionPayload: ExtractionResponsePayload(
                        rawResponseText: canonicalExtractionJSON(
                            events: [
                                canonicalEvent(
                                    "event_rutgers_iowa",
                                    title: "Rutgers vs Iowa",
                                    thingRef: nil,
                                    occurredAt: "2027-09-05"
                                )
                            ],
                            confidence: #"{"overall":0.72,"requiresReview":true,"reasons":["possible_duplicate"]}"#
                        )
                    )
                )
            ),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )

        _ = try await importService.send("Add all Rutgers football home games to my things.")

        let items = try reviewGenerationService(context).refresh()
        let importMessage = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>()).first {
            $0.text == "Add all Rutgers football home games to my things."
        })
        let importEvent = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerEvent>()).first {
            $0.title == "Rutgers vs Iowa"
        })
        let importItem = try XCTUnwrap(items.first {
            $0.kind == .extractionReview && $0.targetID == importMessage.id
        })
        let importEntry = try reviewQueueService(context).entry(for: importItem)

        XCTAssertEqual(item(for: failed, in: items)?.actionTitle, "Retry Now")
        XCTAssertEqual(item(for: needsReview, in: items)?.actionTitle, "Retry Now")
        XCTAssertEqual(items.first { $0.kind == .localRecovery && $0.targetID == retryable.id }?.actionTitle, "Retry Now")
        XCTAssertTrue(items.contains { $0.kind == .overdueReminderReview && $0.targetID == staleReminder.id })
        XCTAssertTrue(items.contains { $0.kind == .duplicateThing && $0.evidence.map(\.sourceID).contains(duplicateA.id) })
        XCTAssertTrue(items.contains { $0.kind == .normalizationCandidate && $0.targetID == namingCandidate.id })
        XCTAssertEqual(importMessage.extractionStatus, .partiallySucceeded)
        XCTAssertEqual(importItem.actionTitle, "Open")
        XCTAssertTrue(importItem.evidence.contains { $0.sourceType == .event && $0.sourceID == importEvent.id })
        XCTAssertEqual(importEntry.createdRecords.map(\.title), ["Rutgers vs Iowa"])
        XCTAssertEqual(importEntry.blockedMessage, ManualExtractionRetryBlockedReason.createdRecordsExist.message)
    }

    func testReviewActionsKeepQueueSearchTimelineRulesAndThingsConsistent() throws {
        let context = makeInMemoryModelContext()
        let source = Thing(name: "NWS")
        let target = Thing(name: "Nimbus Web Services")
        let event = LedgerEvent(title: "Deploy scanner", occurredAt: fixedTestNow, rawText: "Deploy scanner", thing: source)
        let rule = LedgerRule(title: "Review scanner deploy", ruleType: .reminder, startsAt: fixedTestNow, thing: source)
        let note = LedgerNote(text: "Scanner deploy notes", linkedThings: [source])
        let item = LedgerReviewItem(
            dedupeKey: "normalization_candidate|expanded-coverage",
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "NWS may match Nimbus Web Services. No items have been merged.",
            actionTitle: "Review Thing",
            targetType: .thing,
            targetID: source.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .none, sourceID: note.id, summary: note.text, detail: nil),
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: target.id, summary: target.name, detail: nil)
            ]
        )
        context.insert(source)
        context.insert(target)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(item)
        try context.save()

        try reviewQueueService(context).reassignRecords(from: item, to: target.id)

        let things = try context.fetch(FetchDescriptor<Thing>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let records = SearchService().records(things: things, events: events, rules: rules, notes: notes)
        let searchResults = SearchService().search("Nimbus", in: records)
        let eventRecord = records.first { $0.kind == .event && $0.id == event.id }
        let ruleRecord = records.first { $0.kind == .rule && $0.id == rule.id }
        let feedItems = LedgerFeedProjection(calendar: utcCalendar, now: fixedTestNow).items(
            messages: [],
            events: events,
            reminders: rules,
            notes: notes
        )
        let targetSnapshot = try XCTUnwrap(things.first { $0.id == target.id }).detailSnapshot

        XCTAssertEqual(item.state, .accepted)
        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(eventRecord?.linkedThingName, target.name)
        XCTAssertEqual(ruleRecord?.linkedThingName, target.name)
        XCTAssertTrue(searchResults.contains { $0.sourceKind == .event && $0.linkedThingName == target.name })
        XCTAssertTrue(searchResults.contains { $0.sourceKind == .rule && $0.linkedThingName == target.name })
        XCTAssertTrue(feedItems.contains { $0.id == "event-\(event.id.uuidString)" })
        XCTAssertTrue(feedItems.contains { $0.id == "reminder-\(rule.id.uuidString)" })
        XCTAssertEqual(targetSnapshot.countSummary, "1 event · 1 note · 1 active reminder")
    }

    func testPresentationVisualLanguageAlignsAcrossReviewQueueAndLedgerSurfaces() {
        let messageID = UUID()
        let thingID = UUID()
        let ruleID = UUID()
        let messageItem = reviewItem(
            kind: .extractionReview,
            title: "Entry needs review",
            actionTitle: "Open",
            targetType: .chatMessage,
            targetID: messageID
        )
        let thingItem = reviewItem(
            kind: .duplicateThing,
            title: "Possible duplicate Things",
            actionTitle: "Review Things",
            targetType: .thing,
            targetID: thingID,
            evidence: [LedgerReviewItemEvidence(sourceType: .thing, sourceID: thingID, summary: "Printer Paper", detail: nil)]
        )
        let ruleItem = reviewItem(
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            actionTitle: "Review reminder",
            targetType: .rule,
            targetID: ruleID
        )
        let entry = LedgerReviewQueueEntry(
            itemID: messageItem.id,
            title: messageItem.title,
            detail: messageItem.detail,
            correctionClass: .quickReview,
            primaryActionTitle: "Open",
            blockedMessage: nil,
            createdRecords: [LedgerReviewCreatedRecord(targetType: .event, targetID: UUID(), title: "Changed filter", subtitle: "Event")],
            origin: nil
        )

        let queueRow = LedgerReviewQueueRowPresentation(item: messageItem, entry: entry, now: fixedTestNow)
        let itemService = LedgerReviewItemPresentationService()
        let thingPresentation = itemService.primaryPresentation(for: .thing, targetID: thingID, in: [thingItem])
        let rulePresentation = itemService.primaryPresentation(for: .rule, targetID: ruleID, in: [ruleItem])
        let searchMessageBadge = LedgerBadgePresentation.searchCategory(for: .chatMessage)
        let timelineMessageBadge = LedgerBadgePresentation.timelineCategory(for: .message)
        let carryForwardReviewBadge = LedgerBadgePresentation.reminderStatus(for: .review)

        XCTAssertEqual(queueRow.badges.map(\.semantic), [.actionReview])
        XCTAssertEqual(queueRow.badges.map(\.role), [.action])
        XCTAssertEqual(queueRow.hiddenBadgeAccessibilityText, "Context: Message")
        XCTAssertEqual(searchMessageBadge.semantic, .categoryMessage)
        XCTAssertEqual(timelineMessageBadge.semantic, .categoryMessage)
        XCTAssertEqual(thingPresentation?.badge.semantic, .actionReview)
        XCTAssertEqual(thingPresentation?.tone, .muted)
        XCTAssertEqual(rulePresentation?.badge.semantic, .actionReview)
        XCTAssertEqual(rulePresentation?.tone, .attention)
        XCTAssertEqual(carryForwardReviewBadge.semantic, .actionReview)
        XCTAssertEqual(carryForwardReviewBadge.tone, .attention)
        XCTAssertEqual(queueRow.accessibilityLabel.occurrenceCount(of: "Entry needs review"), 1)
        XCTAssertEqual(queueRow.accessibilityLabel.occurrenceCount(of: "Suggested:"), 0)
        XCTAssertEqual(queueRow.accessibilityLabel.occurrenceCount(of: "Saved items include"), 1)
    }

    func testScenarioReviewFixtureReloadsAfterLocalClearWithoutDuplicateQueueItems() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let fixture = try SeedScenarioLoader.fixture(for: .ambiguousDogGrooming)

        try SeedScenarioLoader.loadFixture(fixture, into: context)
        let firstItems = try reviewGenerationService(context).refresh().filter { $0.state.isAmbientlyVisible }
        let firstEntry = try reviewQueueService(context).entry(for: try XCTUnwrap(firstItems.first))

        try LocalDataClearService(modelContext: context).clearLedgerData()
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerReviewItem>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessage>()).isEmpty)

        try SeedScenarioLoader.loadFixture(fixture, into: context)
        let reloadedItems = try reviewGenerationService(context).refresh().filter { $0.state.isAmbientlyVisible }
        let reloadedEntry = try reviewQueueService(context).entry(for: try XCTUnwrap(reloadedItems.first))

        XCTAssertEqual(reloadedItems.count, 1)
        XCTAssertEqual(reloadedItems.map(\.title), firstItems.map(\.title))
        XCTAssertEqual(reloadedEntry.title, firstEntry.title)
        XCTAssertEqual(reloadedEntry.primaryActionTitle, "Choose Date")
        XCTAssertTrue(try XCTUnwrap(reloadedItems.first).evidence.contains { $0.sourceType == .thing })
    }

    private func item(for message: ChatMessage, in items: [LedgerReviewItem]) -> LedgerReviewItem? {
        items.first { $0.kind == .extractionReview && $0.targetID == message.id }
    }

    private func message(_ text: String, status: ExtractionStatus, errorCode: ExtractionErrorCode? = nil) -> ChatMessage {
        ChatMessage(role: .user, text: text, createdAt: fixedTestNow, extractionStatus: status, extractionErrorCode: errorCode)
    }

    private func reviewItem(
        kind: LedgerReviewItemKind,
        title: String,
        actionTitle: String,
        targetType: LedgerReviewItemTargetType,
        targetID: UUID,
        evidence: [LedgerReviewItemEvidence] = []
    ) -> LedgerReviewItem {
        LedgerReviewItem(
            dedupeKey: "\(kind.rawValue)|\(targetID.uuidString)|expanded-coverage",
            kind: kind,
            title: title,
            detail: "Open the saved context to resolve this review.",
            actionTitle: actionTitle,
            targetType: targetType,
            targetID: targetID,
            evidence: evidence,
            createdAt: fixedTestNow,
            updatedAt: fixedTestNow
        )
    }

    private func reviewGenerationService(_ context: ModelContext) -> LedgerReviewItemGenerationService {
        LedgerReviewItemGenerationService(modelContext: context, now: { fixedTestNow }, calendar: utcCalendar)
    }

    private func reviewQueueService(_ context: ModelContext) -> LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: InMemoryDeviceTokenStore(token: "test-device-token"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private extension Thing {
    var detailSnapshot: ThingDetailSnapshot {
        ThingDetailSnapshot(thing: self, now: fixedTestNow)
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
