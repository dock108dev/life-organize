import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LedgerReviewQueueConsistencyScenarioTests: XCTestCase {
    func testGeneratedScenarioMatrixPreservesRecordsAndBuildsStableQueueEntries() throws {
        let context = makeInMemoryModelContext()
        let fixture = try makeFixture(in: context)
        let originalConflictDate = fixture.conflictEvent.occurredAt
        let originalConflictMetadata = fixture.conflictEvent.metadataEntries
        let originalRetryAttemptCount = try context.fetch(FetchDescriptor<ExtractionAttempt>()).count

        let items = try generationService(context).refresh()

        let ambiguous = try item(from: items, kind: .extractionReview, targetID: fixture.ambiguousMessage.id)
        assertItem(
            ambiguous,
            kind: .extractionReview,
            targetType: .chatMessage,
            targetID: fixture.ambiguousMessage.id,
            confidence: 1,
            title: "Entry needs review",
            actionTitle: "Retry Now",
            detailContains: ["original entry is saved locally", "Retry this entry"],
            evidence: [(sourceType: .chatMessage, sourceID: fixture.ambiguousMessage.id)]
        )

        let partial = try item(from: items, kind: .extractionReview, targetID: fixture.partialMessage.id)
        assertItem(
            partial,
            kind: .extractionReview,
            targetType: .chatMessage,
            targetID: fixture.partialMessage.id,
            confidence: 1,
            title: "Entry needs review",
            actionTitle: "Open",
            detailContains: ["created 4 saved items", "Open them"],
            evidence: [
                (sourceType: .chatMessage, sourceID: fixture.partialMessage.id),
                (sourceType: .thing, sourceID: fixture.partialThing.id),
                (sourceType: .event, sourceID: fixture.partialEvent.id),
                (sourceType: .rule, sourceID: fixture.partialRule.id),
                (sourceType: .none, sourceID: fixture.partialNote.id)
            ]
        )

        let recovery = try item(from: items, kind: .localRecovery, targetID: fixture.recoveryMessage.id)
        assertItem(
            recovery,
            kind: .localRecovery,
            targetType: .chatMessage,
            targetID: fixture.recoveryMessage.id,
            confidence: 1,
            title: "Entry recovery is available",
            actionTitle: "Retry Now",
            detailContains: ["original entry is saved locally", "Retry this entry"],
            evidence: [(sourceType: .chatMessage, sourceID: fixture.recoveryMessage.id)]
        )

        let duplicate = try duplicateItem(
            from: items,
            sourceIDs: [fixture.duplicateTarget.id, fixture.duplicateSource.id]
        )
        let duplicateTargetIDs = [fixture.duplicateTarget.id, fixture.duplicateSource.id]
        assertItem(
            duplicate,
            kind: .duplicateThing,
            targetType: .thing,
            targetID: try XCTUnwrap(duplicate.targetID),
            confidence: 0.8,
            title: "Possible duplicate Things",
            actionTitle: "Review Things",
            detailContains: ["share a saved name or alias", "No items have been merged"],
            evidence: [
                (sourceType: .thing, sourceID: fixture.duplicateTarget.id),
                (sourceType: .thing, sourceID: fixture.duplicateSource.id)
            ]
        )
        XCTAssertTrue(duplicateTargetIDs.contains(try XCTUnwrap(duplicate.targetID)))

        let conflict = try item(from: items, kind: .conflictingDate, targetID: fixture.conflictEvent.id)
        assertItem(
            conflict,
            kind: .conflictingDate,
            targetType: .event,
            targetID: fixture.conflictEvent.id,
            confidence: 0.85,
            title: "Event has conflicting dates",
            actionTitle: "Review event",
            detailContains: [
                "Window service renewal",
                "is dated",
                "saved metadata includes 2026-05-15",
                "Review the event before changing dates"
            ],
            evidence: [(sourceType: .event, sourceID: fixture.conflictEvent.id)]
        )

        let keyedQueue = queueService(context)
        let ambiguousEntry = try keyedQueue.entry(for: ambiguous)
        let partialEntry = try keyedQueue.entry(for: partial)
        let duplicateEntry = try keyedQueue.entry(for: duplicate)
        let conflictEntry = try keyedQueue.entry(for: conflict)
        let recoveryEntry = try queueService(context, tokenStore: InMemoryDeviceTokenStore()).entry(for: recovery)

        assertEntry(ambiguousEntry, for: ambiguous, correctionClass: .quickReview, blocked: false)
        assertEntry(partialEntry, for: partial, correctionClass: .quickReview, blocked: true)
        XCTAssertEqual(Set(partialEntry.createdRecords.map(\.subtitle)), ["Thing", "Event", "Reminder", "Note"])
        assertEntry(duplicateEntry, for: duplicate, correctionClass: .mergeDuplicateThings, blocked: false)
        assertEntry(conflictEntry, for: conflict, correctionClass: .quickReview, blocked: false)
        assertEntry(recoveryEntry, for: recovery, correctionClass: .quickReview, blocked: false)

        let presentations = [ambiguousEntry, partialEntry, duplicateEntry, conflictEntry, recoveryEntry].map { entry in
            LedgerReviewQueueRowPresentation(
                item: items.first { $0.id == entry.itemID }!,
                entry: entry,
                now: scenarioNow
            )
        }
        XCTAssertEqual(presentations.map(\.question), [
            "Entry needs review",
            "Entry needs review",
            "Possible duplicate Things",
            "Event has conflicting dates",
            "Entry recovery is available"
        ])
        XCTAssertEqual(presentations.map(\.nextActionTitle), [
            "Retry Now",
            "Open",
            "Review Things",
            "Review event",
            "Retry Now"
        ])
        XCTAssertEqual(presentations.map(\.isBlocked), [false, true, false, false, false])

        let orderedEntries = try keyedQueue.entries(from: items)
        XCTAssertEqual(orderedEntries.first?.itemID, ambiguous.id)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtractionAttempt>()).count, originalRetryAttemptCount)
        XCTAssertEqual(fixture.duplicateEvent.thing?.id, fixture.duplicateSource.id)
        XCTAssertEqual(fixture.duplicateRule.thing?.id, fixture.duplicateSource.id)
        XCTAssertEqual(fixture.duplicateNote.linkedThingIDs, [fixture.duplicateSource.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == fixture.duplicateSource.id })
        XCTAssertEqual(fixture.conflictEvent.occurredAt, originalConflictDate)
        XCTAssertEqual(fixture.conflictEvent.metadataEntries, originalConflictMetadata)
    }

    func testReviewActionsCompleteOrFailWithoutPartialMutation() async throws {
        let context = makeInMemoryModelContext()
        let fixture = try makeFixture(in: context)
        let items = try generationService(context).refresh()
        let recovery = try item(from: items, kind: .localRecovery, targetID: fixture.recoveryMessage.id)
        let duplicate = try duplicateItem(
            from: items,
            sourceIDs: [fixture.duplicateTarget.id, fixture.duplicateSource.id]
        )
        let conflict = try item(from: items, kind: .conflictingDate, targetID: fixture.conflictEvent.id)
        let queue = queueService(context)

        XCTAssertThrowsError(try queue.saveAsNote(recovery, body: " \n ")) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .noActionableRecords)
        }
        XCTAssertEqual(recovery.state, .candidate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerNote>()).contains { $0.id == fixture.partialNote.id })

        let savedNote = try queue.saveAsNote(recovery, body: "Keep this entry as a review note.")
        XCTAssertEqual(savedNote.sourceMessage?.id, fixture.recoveryMessage.id)
        XCTAssertEqual(recovery.state, .accepted)

        try queue.mergeDuplicateThings(for: duplicate, into: fixture.duplicateTarget.id)
        XCTAssertEqual(fixture.duplicateEvent.thing?.id, fixture.duplicateTarget.id)
        XCTAssertEqual(fixture.duplicateRule.thing?.id, fixture.duplicateTarget.id)
        XCTAssertEqual(fixture.duplicateNote.linkedThingIDs, [fixture.duplicateTarget.id])
        XCTAssertFalse(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == fixture.duplicateSource.id })
        XCTAssertEqual(duplicate.state, .accepted)
        XCTAssertThrowsError(try queue.mergeDuplicateThings(for: duplicate, into: fixture.duplicateTarget.id)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .actionUnavailable)
        }

        let conflictDate = fixture.conflictEvent.occurredAt
        try queue.markReviewed(conflict)
        XCTAssertEqual(fixture.conflictEvent.occurredAt, conflictDate)
        XCTAssertEqual(conflict.state, .accepted)

        let retryContext = makeInMemoryModelContext()
        let retryMessage = ChatMessage(
            id: retryMessageID,
            role: .user,
            text: "Need to retry this entry when the connection returns.",
            createdAt: scenarioNow,
            extractionStatus: .failed
        )
        retryContext.insert(retryMessage)
        try retryContext.save()
        let retryItem = try XCTUnwrap(try generationService(retryContext).refresh().first { $0.kind == .extractionReview })
        var retryQueue = queueService(retryContext)
        retryQueue.extractorFactory = { _ in
            StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [canonicalThing("thing_blue_wagon", name: "Blue Wagon", category: "vehicle")],
                        events: [
                            canonicalEvent(
                                "event_blue_wagon_retry",
                                title: "Blue wagon service",
                                thingRef: "thing_blue_wagon",
                                occurredAt: "2027-01-15",
                                eventType: "maintenance",
                                rawText: "Need to retry this entry when the connection returns."
                            )
                        ]
                    )
                )
            )
        }

        try await retryQueue.retryEntry(retryItem)

        XCTAssertEqual(retryItem.state, .accepted)
        XCTAssertEqual(retryMessage.extractionStatus, .succeeded)
        XCTAssertEqual(try retryContext.fetch(FetchDescriptor<ExtractionAttempt>()).count, 1)
        XCTAssertEqual(try retryContext.fetch(FetchDescriptor<LedgerEvent>()).count, 1)
    }

    func testBlockedRetryAndNavigationContextRemainStableAfterFailure() async throws {
        let context = makeInMemoryModelContext()
        let fixture = try makeFixture(in: context)
        let items = try generationService(context).refresh()
        let recovery = try item(from: items, kind: .localRecovery, targetID: fixture.recoveryMessage.id)
        let origin = LedgerReviewOrigin(
            targetType: .chatMessage,
            targetID: fixture.recoveryMessage.id,
            label: "Recovery entry"
        )
        var tokenlessQueue = queueService(context, tokenStore: InMemoryDeviceTokenStore())
        tokenlessQueue.extractorFactory = { _ in
            StaticMessageExtractionClient(
                payload: ExtractionResponsePayload(
                    rawResponseText: canonicalExtractionJSON(
                        things: [canonicalThing("thing_recovery_retry", name: "Recovery Entry")],
                        events: [
                            canonicalEvent(
                                "event_recovery_retry",
                                title: "Recovered entry",
                                thingRef: "thing_recovery_retry",
                                occurredAt: "2027-01-15",
                                rawText: fixture.recoveryMessage.text
                            )
                        ]
                    )
                )
            )
        }
        let entriesBeforeRetry = try tokenlessQueue.entries(from: items, origin: origin)

        try await tokenlessQueue.retryEntry(recovery)

        let entriesAfterRetry = try tokenlessQueue.entries(from: items, origin: origin)

        XCTAssertEqual(entriesBeforeRetry.map(\.itemID), [recovery.id])
        XCTAssertEqual(entriesAfterRetry.map(\.itemID), [])
        XCTAssertEqual(recovery.state, .accepted)
        XCTAssertNil(recovery.failureReason)
        XCTAssertEqual(fixture.recoveryMessage.extractionStatus, .succeeded)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExtractionAttempt>()).contains { $0.sourceMessage?.id == fixture.recoveryMessage.id })
    }

    func testRegenerationSuppressesResolvedItemsAllowsFailedRetryAndSupersedesStaleItems() throws {
        let context = makeInMemoryModelContext()
        let fixture = try makeFixture(in: context)
        let service = generationService(context)
        let items = try service.refresh()
        let ambiguous = try item(from: items, kind: .extractionReview, targetID: fixture.ambiguousMessage.id)
        let duplicate = try duplicateItem(
            from: items,
            sourceIDs: [fixture.duplicateTarget.id, fixture.duplicateSource.id]
        )
        let conflict = try item(from: items, kind: .conflictingDate, targetID: fixture.conflictEvent.id)

        try queueService(context).dismiss(ambiguous)
        let dismissedRefresh = try service.refresh().filter {
            $0.kind == .extractionReview && $0.targetID == fixture.ambiguousMessage.id
        }
        XCTAssertEqual(dismissedRefresh.count, 1)
        XCTAssertEqual(dismissedRefresh.first?.id, ambiguous.id)
        XCTAssertEqual(dismissedRefresh.first?.state, .dismissed)

        ambiguous.fail(reason: "Retry should regenerate this review.", at: scenarioNow)
        try context.save()
        let failedRefresh = try service.refresh().filter {
            $0.kind == .extractionReview && $0.targetID == fixture.ambiguousMessage.id
        }
        XCTAssertEqual(failedRefresh.count, 1)
        XCTAssertEqual(failedRefresh.first?.id, ambiguous.id)
        XCTAssertEqual(failedRefresh.first?.state, .candidate)
        XCTAssertNil(failedRefresh.first?.failureReason)

        fixture.duplicateSource.name = "Garden Cart"
        fixture.duplicateSource.normalizedKey = ThingNormalizer.normalizeKey("Garden Cart")
        fixture.conflictEvent.occurredAt = date(year: 2026, month: 5, day: 15)
        try context.save()

        _ = try service.refresh()

        XCTAssertEqual(duplicate.state, .superseded)
        XCTAssertEqual(conflict.state, .superseded)
    }

    func testManualReviewActionsPreserveAtomicityForReassignAndReminderTiming() throws {
        let context = makeInMemoryModelContext()
        let source = Thing(id: thingAID, name: "NWS", createdAt: scenarioNow, updatedAt: scenarioNow)
        let target = Thing(id: thingBID, name: "North Window Service", createdAt: scenarioNow, updatedAt: scenarioNow)
        let event = LedgerEvent(
            id: eventID,
            title: "Window service renewal",
            occurredAt: scenarioNow,
            rawText: "Renewed window service.",
            createdAt: scenarioNow,
            updatedAt: scenarioNow,
            thing: source
        )
        let reassignItem = LedgerReviewItem(
            dedupeKey: "normalization_candidate|matrix",
            kind: .normalizationCandidate,
            title: "Thing match needs review",
            detail: "NWS may match North Window Service. No items have been merged.",
            actionTitle: "Review Thing",
            targetType: .thing,
            targetID: source.id,
            evidence: [
                LedgerReviewItemEvidence(sourceType: .event, sourceID: event.id, summary: event.title, detail: nil),
                LedgerReviewItemEvidence(sourceType: .thing, sourceID: target.id, summary: target.name, detail: nil)
            ],
            createdAt: scenarioNow,
            updatedAt: scenarioNow
        )
        let reminder = LedgerRule(
            id: ruleID,
            title: "Renew window service",
            ruleType: .deadline,
            startsAt: scenarioNow.addingTimeInterval(-86_400),
            expiresAt: scenarioNow.addingTimeInterval(-86_400),
            createdAt: scenarioNow,
            updatedAt: scenarioNow
        )
        let timingItem = LedgerReviewItem(
            dedupeKey: "overdue_reminder_review|matrix",
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Renew window service was due.",
            actionTitle: "Review reminder",
            targetType: .rule,
            targetID: reminder.id,
            evidence: [LedgerReviewItemEvidence(sourceType: .rule, sourceID: reminder.id, summary: reminder.title, detail: nil)],
            createdAt: scenarioNow,
            updatedAt: scenarioNow
        )
        let missingTimingItem = LedgerReviewItem(
            dedupeKey: "overdue_reminder_review|missing-matrix",
            kind: .overdueReminderReview,
            title: "Reminder is in review",
            detail: "Missing reminder was due.",
            actionTitle: "Review reminder",
            targetType: .rule,
            targetID: missingRuleID,
            evidence: [],
            createdAt: scenarioNow,
            updatedAt: scenarioNow
        )
        context.insert(source)
        context.insert(target)
        context.insert(event)
        context.insert(reassignItem)
        context.insert(reminder)
        context.insert(timingItem)
        context.insert(missingTimingItem)
        try context.save()

        let queue = queueService(context)
        XCTAssertThrowsError(try queue.adjustReminderTiming(for: missingTimingItem, startsAt: scenarioNow)) { error in
            XCTAssertEqual(error as? LedgerReviewQueueError, .missingTarget)
        }
        XCTAssertEqual(missingTimingItem.state, .candidate)
        XCTAssertNil(missingTimingItem.failureReason)

        try queue.reassignRecords(from: reassignItem, to: target.id)
        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(reassignItem.state, .accepted)

        let newDate = scenarioNow.addingTimeInterval(3 * 86_400)
        try queue.adjustReminderTiming(for: timingItem, startsAt: newDate)
        XCTAssertEqual(reminder.startsAt, DateFormatting.normalizedDateOnly(newDate))
        XCTAssertEqual(timingItem.state, .accepted)
    }

}
