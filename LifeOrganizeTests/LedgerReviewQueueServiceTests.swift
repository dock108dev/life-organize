import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewQueueServiceTests: XCTestCase {
    func testQueueEntriesCoverReviewStatusesAndBlockedRecoveryStates() throws {
        let context = makeInMemoryModelContext()
        let messages: [ChatMessage] = [
            message("Needs retry", status: .failed),
            message("Failed with review", status: .failedNeedsReview),
            message("Needs review", status: .needsReview),
            message("Partial", status: .partiallySucceeded),
            message("Waiting for key", status: .pendingToken),
            message("Retry later", status: .pendingRetry),
        ]
        messages.forEach(context.insert)
        try context.save()

        let items = try generationService(context).refresh()
        let entries = try queueService(context, tokenStore: InMemoryDeviceTokenStore()).entries(from: items)

        XCTAssertEqual(entries.filter { $0.correctionClass == .quickReview }.count, 6)
        XCTAssertTrue(entries.contains { $0.title == "Entry recovery is available" && $0.primaryActionTitle == "Retry Now" })
        XCTAssertTrue(entries.contains { $0.detail.contains("Retry this entry") })
        XCTAssertTrue(entries.contains { $0.detail.contains("Edit the records") || $0.detail.contains("needs review") })
    }

    func testPartialEntryLinksCreatedRecordsForEditing() throws {
        let context = makeInMemoryModelContext()
        let message = message("Changed oil and set a reminder.", status: .partiallySucceeded)
        let thing = Thing(name: "Blue sedan")
        let event = LedgerEvent(title: "Changed oil", occurredAt: fixedTestNow, rawText: "Changed oil", thing: thing)
        let rule = LedgerRule(title: "Change oil again", ruleType: .reminder, startsAt: fixedTestNow, thing: thing)
        let note = LedgerNote(text: "Use synthetic oil", linkedThings: [thing])
        let attempt = ExtractionAttempt(
            status: .partiallySucceeded,
            createdEventIDs: [event.id],
            createdRuleIDs: [rule.id],
            createdNoteIDs: [note.id],
            createdThingIDs: [thing.id],
            sourceMessage: message
        )
        context.insert(message)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(attempt)
        try context.save()

        let item = try XCTUnwrap(try generationService(context).refresh().first { $0.kind == .extractionReview })
        let entry = try queueService(context).entry(for: item)

        XCTAssertEqual(Set(entry.createdRecords.map(\.subtitle)), ["Thing", "Event", "Reminder", "Note"])
        XCTAssertTrue(entry.detail.contains("Open those records"))
        XCTAssertEqual(entry.blockedMessage, ManualExtractionRetryBlockedReason.createdRecordsExist.message)
    }

    func testQueueEntriesCoverNormalizationDuplicateConflictAndReminderTimingClasses() throws {
        let context = makeInMemoryModelContext()
        let duplicateA = Thing(name: "Printer Paper")
        let duplicateB = Thing(name: "printer paper")
        let normalized = Thing(name: "changed oil", normalizedKey: "changed oil")
        let event = LedgerEvent(
            title: "Dentist appointment",
            occurredAt: fixedTestNow,
            rawText: "Dentist",
            metadataEntries: [
                LedgerEventMetadataEntry(key: .dueDate, valueKind: .date, dateValue: "2026-05-15"),
            ]
        )
        let overdue = LedgerRule(
            title: "Renew registration",
            ruleType: .deadline,
            startsAt: fixedTestNow.addingTimeInterval(-86_400),
            expiresAt: fixedTestNow.addingTimeInterval(-86_400)
        )
        context.insert(duplicateA)
        context.insert(duplicateB)
        context.insert(normalized)
        context.insert(event)
        context.insert(overdue)
        try context.save()

        let items = try generationService(context, now: fixedTestNow).refresh()
        let entries = try queueService(context).entries(from: items)

        XCTAssertTrue(entries.contains { $0.correctionClass == .mergeDuplicateThings })
        XCTAssertTrue(entries.contains { $0.correctionClass == .reassignRecordsToThing })
        XCTAssertTrue(entries.contains { $0.correctionClass == .quickReview && $0.title == "Event has conflicting dates" })
        XCTAssertTrue(entries.contains { $0.correctionClass == .adjustReminderTiming && $0.title == "Reminder is in review" })
    }

    func testMergeDuplicateThingsMovesRecordsAndKeepsCancelAsNoMutation() throws {
        let context = makeInMemoryModelContext()
        let target = Thing(name: "Printer Paper")
        let source = Thing(name: "printer paper", details: "Office shelf")
        let event = LedgerEvent(title: "Bought paper", occurredAt: fixedTestNow, rawText: "Bought paper", thing: source)
        let rule = LedgerRule(title: "Buy paper again", ruleType: .reminder, startsAt: fixedTestNow, thing: source)
        let note = LedgerNote(text: "Coupon in drawer", linkedThings: [source])
        context.insert(target)
        context.insert(source)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        try context.save()

        let item = try XCTUnwrap(try generationService(context).refresh().first { $0.kind == .duplicateThing })
        XCTAssertEqual(source.eventCount, 0)

        try queueService(context).mergeDuplicateThings(for: item, into: target.id)

        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertTrue(note.linkedThings.contains { $0.id == target.id })
        XCTAssertEqual(item.state, .accepted)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
    }

    func testDismissDuplicateReviewLeavesThingsUnmerged() throws {
        let context = makeInMemoryModelContext()
        let target = Thing(name: "Printer Paper")
        let source = Thing(name: "printer paper")
        let event = LedgerEvent(title: "Bought paper", occurredAt: fixedTestNow, rawText: "Bought paper", thing: source)
        context.insert(target)
        context.insert(source)
        context.insert(event)
        try context.save()

        let item = try XCTUnwrap(try generationService(context).refresh().first { $0.kind == .duplicateThing })
        try queueService(context).dismiss(item)

        XCTAssertEqual(event.thing?.id, source.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
        XCTAssertEqual(item.state, .dismissed)
    }

    func testReassignRecordsMovesEvidenceTargetsToSelectedThing() throws {
        let context = makeInMemoryModelContext()
        let source = Thing(name: "NWS")
        let target = Thing(name: "Nimbus Web Services")
        let event = LedgerEvent(title: "Deploy", occurredAt: fixedTestNow, rawText: "Deploy", thing: source)
        let rule = LedgerRule(title: "Review deploy", ruleType: .reminder, startsAt: fixedTestNow, thing: source)
        let note = LedgerNote(text: "Deploy notes", linkedThings: [source])
        let item = LedgerReviewItem(
            dedupeKey: "normalization_candidate|test",
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "NWS may match Nimbus Web Services. No records have been merged.",
            targetType: .thing,
            targetID: source.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .none, sourceID: note.id, summary: note.text, detail: nil),
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: target.id, summary: target.name, detail: nil),
            ]
        )
        context.insert(source)
        context.insert(target)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(item)
        try context.save()

        try queueService(context).reassignRecords(from: item, to: target.id)

        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(item.state, .accepted)
    }

    func testAdjustReminderTimingAcceptsReviewItem() throws {
        let context = makeInMemoryModelContext()
        let originalDate = fixedTestNow.addingTimeInterval(-86_400)
        let newDate = fixedTestNow.addingTimeInterval(3 * 86_400)
        let rule = LedgerRule(title: "Renew license", ruleType: .deadline, startsAt: originalDate, expiresAt: originalDate)
        let item = LedgerReviewItem(
            dedupeKey: "overdue_reminder_review|test",
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Date passed.",
            targetType: .rule,
            targetID: rule.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil)]
        )
        context.insert(rule)
        context.insert(item)
        try context.save()

        try queueService(context).adjustReminderTiming(for: item, startsAt: newDate)

        XCTAssertEqual(rule.startsAt, DateFormatting.normalizedDateOnly(newDate))
        XCTAssertEqual(item.state, .accepted)
    }

    func testIntervalReminderActionBuildsDraftWithoutMutatingRecords() throws {
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "HVAC air filter")
        let event = LedgerEvent(title: "Replaced filter", occurredAt: fixedTestNow, rawText: "Filter", thing: thing)
        let item = LedgerReviewItem(
            dedupeKey: "interval_reminder|test",
            kind: .intervalReminder,
            title: "Air filter cadence is ready for review",
            detail: "Saved records show about every 90 days. next date range 2026-05-22 to 2026-05-29. No reminder has been created or changed.",
            actionTitle: "Review reminder setup",
            targetType: .thing,
            targetID: thing.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: "90-day interval"),
            ]
        )
        context.insert(thing)
        context.insert(event)
        context.insert(item)
        try context.save()

        let draft = try queueService(context).reminderDraft(for: item)

        XCTAssertEqual(draft.title, "HVAC air filter reminder")
        XCTAssertEqual(draft.thingID, thing.id)
        XCTAssertTrue(draft.reason.contains("90-day interval"))
        XCTAssertTrue(draft.reason.contains("No automatic recurrence has been scheduled."))
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerRule>()).isEmpty)
        XCTAssertEqual(item.state, .candidate)
    }

    func testReminderLifecycleActionUsesExistingRuleMutationAndAcceptsItem() throws {
        let context = makeInMemoryModelContext()
        let originalDate = fixedTestNow.addingTimeInterval(-86_400)
        let rule = LedgerRule(title: "Renew license", ruleType: .deadline, startsAt: originalDate, expiresAt: originalDate)
        let item = LedgerReviewItem(
            dedupeKey: "overdue_reminder_review|lifecycle",
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Date passed.",
            targetType: .rule,
            targetID: rule.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .rule, sourceID: rule.id, summary: rule.title, detail: nil)]
        )
        context.insert(rule)
        context.insert(item)
        try context.save()

        try queueService(context).applyReminderLifecycleAction(for: item)

        XCTAssertEqual(rule.manuallyDeactivatedAt, fixedTestNow)
        XCTAssertEqual(rule.lifecycleState, .deactivated)
        XCTAssertEqual(item.state, .accepted)
    }

    func testStaleSourceTargetPreservesReviewItemState() throws {
        let context = makeInMemoryModelContext()
        let item = LedgerReviewItem(
            dedupeKey: "overdue_reminder_review|missing",
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Date passed.",
            targetType: .rule,
            targetID: UUID(),
            evidence: []
        )
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).applyReminderLifecycleAction(for: item)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .missingTarget)
        }
        XCTAssertEqual(item.state, .candidate)
        XCTAssertNil(item.failureReason)
    }

    func testDuplicateActionIsRejectedWithoutSecondMutation() throws {
        let context = makeInMemoryModelContext()
        let target = Thing(name: "Printer Paper")
        let source = Thing(name: "printer paper")
        let event = LedgerEvent(title: "Bought paper", occurredAt: fixedTestNow, rawText: "Bought paper", thing: source)
        let item = LedgerReviewItem(
            dedupeKey: "duplicate_thing|closed",
            kind: .duplicateThing,
            state: .accepted,
            title: "Possible duplicate Things",
            detail: "No records have been merged.",
            targetType: .thing,
            targetID: target.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: target.id, summary: target.name, detail: nil),
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: source.id, summary: source.name, detail: nil),
            ]
        )
        context.insert(target)
        context.insert(source)
        context.insert(event)
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).mergeDuplicateThings(for: item, into: target.id)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .actionUnavailable)
        }
        XCTAssertEqual(event.thing?.id, source.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
    }

    func testNoActionableRecordsFailureKeepsRecordsAndReviewItemOpen() throws {
        let context = makeInMemoryModelContext()
        let source = Thing(name: "NWS")
        let target = Thing(name: "Nimbus Web Services")
        let item = LedgerReviewItem(
            dedupeKey: "normalization_candidate|empty",
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "No records have been merged.",
            targetType: .thing,
            targetID: source.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .thing, sourceID: target.id, summary: target.name, detail: nil)]
        )
        context.insert(source)
        context.insert(target)
        context.insert(item)
        try context.save()

        XCTAssertThrowsError(try queueService(context).reassignRecords(from: item, to: target.id)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .noActionableRecords)
        }
        XCTAssertEqual(item.state, .candidate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
    }

    func testLifecycleTransitionsSuppressRepeatPromptsUntilDedupeChanges() throws {
        let item = LedgerReviewItem(
            dedupeKey: "local_recovery|entry",
            kind: .localRecovery,
            title: "Entry recovery is available",
            detail: "The original entry is saved locally.",
            targetType: .chatMessage,
            targetID: UUID(),
            evidence: []
        )

        item.dismiss(at: fixedTestNow)
        XCTAssertTrue(item.suppressesRepeat)
        item.snooze(until: fixedTestNow.addingTimeInterval(86_400), at: fixedTestNow)
        XCTAssertTrue(item.suppressesRepeat)
        item.supersede(at: fixedTestNow)
        XCTAssertTrue(item.suppressesRepeat)
        item.expire(at: fixedTestNow)
        XCTAssertTrue(item.suppressesRepeat)
    }

    func testOriginFilteringPreservesReturnContextAndDismissalIsExplicit() throws {
        let context = makeInMemoryModelContext()
        let originMessage = message("Review this.", status: .failed)
        let otherMessage = message("Not this.", status: .failed)
        context.insert(originMessage)
        context.insert(otherMessage)
        try context.save()

        let items = try generationService(context).refresh()
        let origin = LedgerReviewOrigin(targetType: .chatMessage, targetID: originMessage.id, label: "Log entry")
        let entries = try queueService(context).entries(from: items, origin: origin)
        let item = try XCTUnwrap(items.first { $0.targetID == originMessage.id })

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.origin, origin)
        XCTAssertEqual(item.state, .candidate)

        try queueService(context).dismiss(item)

        XCTAssertEqual(item.state, .dismissed)
    }

    private func message(_ text: String, status: ExtractionStatus) -> ChatMessage {
        ChatMessage(role: .user, text: text, createdAt: fixedTestNow, extractionStatus: status)
    }

    private func generationService(
        _ context: ModelContext,
        now: Date = fixedTestNow
    ) -> LedgerReviewItemGenerationService {
        LedgerReviewItemGenerationService(
            modelContext: context,
            now: { now },
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func queueService(
        _ context: ModelContext,
        tokenStore: any DeviceTokenStore = InMemoryDeviceTokenStore(token: "test-device-token")
    ) -> LedgerReviewQueueService {
        LedgerReviewQueueService(
            modelContext: context,
            deviceTokenStore: tokenStore,
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
    }
}
