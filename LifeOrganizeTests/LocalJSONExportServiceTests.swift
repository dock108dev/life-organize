import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class LocalJSONExportServiceTests: XCTestCase {
    func testEmptyDatabaseExportsVersionedEnvelope() throws {
        let context = makeInMemoryModelContext()
        let exportedAt = try makeDate("2026-05-17T18:30:00Z")

        let envelope = try makeService(context: context, exportedAt: exportedAt).envelope()

        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(envelope.exportedAt, "2026-05-17T18:30:00Z")
        XCTAssertEqual(envelope.locale.calendar, "gregorian")
        XCTAssertEqual(envelope.locale.timeZone, "America/New_York")
        XCTAssertTrue(envelope.records.chatMessages.isEmpty)
        XCTAssertTrue(envelope.records.extractionRuns.isEmpty)
        XCTAssertTrue(envelope.records.things.isEmpty)
        XCTAssertTrue(envelope.records.events.isEmpty)
        XCTAssertTrue(envelope.records.rules.isEmpty)
        XCTAssertTrue(envelope.records.notes.isEmpty)
        XCTAssertTrue(envelope.records.ledgerReviewItems.isEmpty)
        XCTAssertTrue(envelope.records.entityLinks.isEmpty)
    }

    func testExportPreservesRawMessagesExtractionRecordsAndSourceLinks() throws {
        let context = makeInMemoryModelContext()
        let messageDate = try makeDate("2026-05-17T13:42:10Z")
        let completedAt = try makeDate("2026-05-17T13:42:12Z")
        let editedAt = try makeDate("2026-05-17T15:00:00Z")
        let message = ChatMessage(
            role: .user,
            text: "Changed oil today. No buying domains for 30 days.",
            createdAt: messageDate,
            rawLLMResponse: #"{"events":[{"title":"Changed oil"}],"rules":[{"title":"No buying domains"}]}"#,
            extractionStatus: .succeeded
        )
        let attempt = ExtractionAttempt(
            status: .succeeded,
            promptVersion: "openai-extractor-v1",
            modelName: "gpt-4.1-mini",
            rawResponseText: message.rawLLMResponse,
            normalizedJSONText: #"{"events":[{"title":"Changed oil"}],"rules":[{"title":"No buying domains"}]}"#,
            startedAt: messageDate,
            completedAt: completedAt,
            sourceMessage: message
        )
        let thing = Thing(
            name: "Oil Change",
            aliases: ["oil"],
            category: .maintenance,
            createdAt: completedAt,
            updatedAt: editedAt,
            sourceMessageIDs: [message.id],
            sourceExtractionAttemptIDs: [attempt.id],
            eventCount: 1,
            lastEventAt: messageDate
        )
        let event = LedgerEvent(
            title: "Changed engine oil",
            occurredAt: messageDate,
            rawText: "Changed oil today. No buying domains for 30 days.",
            createdAt: completedAt,
            updatedAt: editedAt,
            note: "Corrected title manually.",
            sourceClientID: "event_1",
            sourceExtractionRunID: attempt.id,
            eventType: .maintenance,
            metadataEntries: [
                LedgerEventMetadataEntry(
                    key: .mileage,
                    valueKind: .number,
                    numberValue: 48231,
                    unit: "mi",
                    sourceText: "48,231 miles"
                ),
            ],
            thing: thing,
            sourceMessage: message
        )
        let rule = LedgerRule(
            title: "No buying domains",
            reason: "30 day pause",
            rawText: "No buying domains for 30 days.",
            startsAt: messageDate,
            expiresAt: try makeDate("2026-06-16T04:00:00Z"),
            createdAt: completedAt,
            updatedAt: completedAt,
            sourceClientID: "rule_1",
            sourceExtractionRunID: attempt.id,
            thing: thing,
            sourceMessage: message
        )
        let note = LedgerNote(
            text: "Oil filter size is 16x20.",
            createdAt: completedAt,
            updatedAt: editedAt,
            sourceClientID: "note_1",
            sourceExtractionRunID: attempt.id,
            sourceMessage: message,
            linkedThings: [thing]
        )
        let link = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: thing.id,
            relation: .mentionsThing,
            createdAt: completedAt,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        attempt.createdThingIDs = [thing.id]
        attempt.createdEventIDs = [event.id]
        attempt.createdRuleIDs = [rule.id]
        attempt.createdNoteIDs = [note.id]

        context.insert(message)
        context.insert(attempt)
        context.insert(thing)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(link)
        try context.save()

        let records = try makeService(context: context).envelope().records

        XCTAssertEqual(records.chatMessages.first?.text, message.text)
        XCTAssertEqual(records.chatMessages.first?.role, "user")
        XCTAssertEqual(records.chatMessages.first?.extractionRunId, attempt.id.uuidString)
        XCTAssertEqual(records.chatMessages.first?.extractionRunIds, [attempt.id.uuidString])
        XCTAssertEqual(records.chatMessages.first?.latestExtractionRunId, attempt.id.uuidString)
        XCTAssertEqual(records.chatMessages.first?.successfulExtractionRunIds, [attempt.id.uuidString])
        XCTAssertEqual(records.chatMessages.first?.extractionState?.status, "succeeded")
        XCTAssertEqual(records.chatMessages.first?.extractionState?.extractionVersion, ExtractionContract.schemaVersion)
        XCTAssertEqual(records.chatMessages.first?.extractionState?.latestAttemptStatus, "succeeded")
        XCTAssertNil(records.chatMessages.first?.extractionState?.recoveryAction)
        XCTAssertEqual(Set(records.chatMessages.first?.linkedEntityIds ?? []), Set([
            thing.id.uuidString,
            event.id.uuidString,
            rule.id.uuidString,
            note.id.uuidString,
        ]))

        let exportedAttempt = try XCTUnwrap(records.extractionRuns.first)
        XCTAssertEqual(exportedAttempt.extractionSchemaVersion, ExtractionContract.schemaVersion)
        XCTAssertEqual(exportedAttempt.rawResponseText, message.rawLLMResponse)
        XCTAssertEqual(exportedAttempt.normalizedJSONText, #"{"events":[{"title":"Changed oil"}],"rules":[{"title":"No buying domains"}]}"#)
        XCTAssertNotNil(exportedAttempt.parsedResponse)
        XCTAssertEqual(exportedAttempt.input?.userText, message.text)
        XCTAssertEqual(exportedAttempt.createdEntities.things, [thing.id.uuidString])
        XCTAssertEqual(exportedAttempt.createdEntities.events, [event.id.uuidString])
        XCTAssertEqual(exportedAttempt.createdEntities.rules, [rule.id.uuidString])
        XCTAssertEqual(exportedAttempt.createdEntities.notes, [note.id.uuidString])
        XCTAssertEqual(Set(exportedAttempt.createdEntityIds), Set([
            thing.id.uuidString,
            event.id.uuidString,
            rule.id.uuidString,
            note.id.uuidString,
        ]))

        XCTAssertEqual(records.things.first?.source.chatMessageId, message.id.uuidString)
        XCTAssertEqual(records.things.first?.source.extractionRunId, attempt.id.uuidString)
        XCTAssertEqual(records.events.first?.rawText, message.text)
        XCTAssertEqual(records.events.first?.eventType, "maintenance")
        XCTAssertEqual(records.events.first?.metadata.first?.key, "mileage")
        XCTAssertEqual(records.events.first?.metadata.first?.numberValue, 48231)
        XCTAssertEqual(records.events.first?.metadata.first?.unit, "mi")
        XCTAssertEqual(records.events.first?.updatedAt, "2026-05-17T15:00:00Z")
        XCTAssertEqual(records.events.first?.source.sourceClientId, "event_1")
        XCTAssertEqual(records.events.first?.source.extractionRunId, attempt.id.uuidString)
        XCTAssertEqual(records.rules.first?.reason, "30 day pause")
        XCTAssertEqual(records.rules.first?.ruleType, "restriction")
        XCTAssertEqual(records.rules.first?.continuityBehavior, "time_limited_window")
        XCTAssertEqual(records.rules.first?.lifecycleState, "open")
        XCTAssertNil(records.rules.first?.manuallyDeactivatedAt)
        XCTAssertEqual(records.rules.first?.source.sourceClientId, "rule_1")
        XCTAssertEqual(records.rules.first?.source.chatMessageId, message.id.uuidString)
        XCTAssertEqual(records.notes.first?.source.sourceClientId, "note_1")
        XCTAssertEqual(records.notes.first?.linkedThingIds, [thing.id.uuidString])
        XCTAssertEqual(records.entityLinks.first?.relationship, "mentions")
    }

    func testExportPreservesRetryStateRecoveryActionAndCreatedIds() throws {
        let context = makeInMemoryModelContext()
        let startedAt = try makeDate("2026-05-17T13:42:10Z")
        let retryAt = try makeDate("2026-05-17T13:43:10Z")
        let eventID = UUID()
        let ruleID = UUID()
        let noteID = UUID()
        let thingID = UUID()
        let message = ChatMessage(
            role: .user,
            text: "Changed filter before connection failed.",
            createdAt: startedAt,
            extractionStatus: .pendingRetry,
            extractionError: "The network is unavailable.",
            extractionErrorCode: .networkUnavailable,
            extractionVersion: ExtractionContract.schemaVersion,
            extractionAttemptCount: 1,
            lastExtractionAttemptAt: startedAt,
            nextExtractionRetryAt: retryAt
        )
        let attempt = ExtractionAttempt(
            status: .failed,
            errorCode: .networkUnavailable,
            errorMessage: "The network is unavailable.",
            startedAt: startedAt,
            completedAt: retryAt,
            createdEventIDs: [eventID],
            createdRuleIDs: [ruleID],
            createdNoteIDs: [noteID],
            createdThingIDs: [thingID],
            sourceMessage: message
        )
        context.insert(message)
        context.insert(attempt)
        try context.save()

        let exportedMessage = try XCTUnwrap(makeService(context: context).envelope().records.chatMessages.first)
        let state = try XCTUnwrap(exportedMessage.extractionState)

        XCTAssertEqual(exportedMessage.latestExtractionRunId, attempt.id.uuidString)
        XCTAssertEqual(state.status, "pending_retry")
        XCTAssertEqual(state.errorCode, "network_unavailable")
        XCTAssertEqual(state.lastAttemptAt, "2026-05-17T13:42:10Z")
        XCTAssertEqual(state.nextRetryAt, "2026-05-17T13:43:10Z")
        XCTAssertEqual(state.latestAttemptStatus, "failed")
        XCTAssertEqual(state.latestAttemptErrorCode, "network_unavailable")
        XCTAssertEqual(state.recoveryAction, "Retry this entry now, or wait for the next automatic retry.")
        XCTAssertEqual(Set(exportedMessage.linkedEntityIds), Set([
            thingID.uuidString,
            eventID.uuidString,
            ruleID.uuidString,
            noteID.uuidString,
        ]))
    }

    func testReviewItemsExportLifecycleAndEvidence() throws {
        let context = makeInMemoryModelContext()
        let createdAt = try makeDate("2026-05-17T13:42:10Z")
        let thing = Thing(name: "HVAC air filter", category: .homeMaintenance, createdAt: createdAt, updatedAt: createdAt)
        let event = LedgerEvent(
            title: "Replaced HVAC air filter",
            occurredAt: createdAt,
            rawText: "Replaced HVAC air filter every 90 days.",
            createdAt: createdAt,
            updatedAt: createdAt,
            eventType: .replacement,
            thing: thing
        )
        let item = LedgerReviewItem(
            dedupeKey: "interval_reminder|\(thing.id.uuidString)|air_filter|\(event.id.uuidString)",
            kind: .intervalReminder,
            title: "Air filter cadence is ready for review",
            detail: "Saved records show about every 90 days. No reminder has been created or changed.",
            actionTitle: "Review reminder setup",
            targetType: .thing,
            targetID: thing.id,
            confidence: 0.9,
            evidence: [
                LedgerReviewItemEvidence(
                    sourceType: .event,
                    sourceID: event.id,
                    summary: event.title,
                    detail: "90-day interval"
                ),
            ],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        item.markPresented(at: try makeDate("2026-05-17T13:45:00Z"))
        item.snooze(until: try makeDate("2026-05-18T13:45:00Z"), at: try makeDate("2026-05-17T13:46:00Z"))
        context.insert(thing)
        context.insert(event)
        context.insert(item)
        try context.save()

        let exportedItem = try XCTUnwrap(makeService(context: context).envelope().records.ledgerReviewItems.first)

        XCTAssertEqual(exportedItem.kind, "interval_reminder")
        XCTAssertEqual(exportedItem.state, "snoozed")
        XCTAssertEqual(exportedItem.targetType, "thing")
        XCTAssertEqual(exportedItem.targetId, thing.id.uuidString)
        XCTAssertEqual(exportedItem.dedupeKey, item.dedupeKey)
        XCTAssertEqual(exportedItem.evidence.first?.sourceType, "event")
        XCTAssertEqual(exportedItem.evidence.first?.sourceId, event.id.uuidString)
        XCTAssertEqual(exportedItem.detail, item.detail)
        XCTAssertEqual(exportedItem.presentedAt, "2026-05-17T13:45:00Z")
        XCTAssertEqual(exportedItem.snoozedUntil, "2026-05-18T13:45:00Z")
    }

    func testManualEventExportsManualSourceAndDatedFilename() throws {
        let context = makeInMemoryModelContext()
        let occurredAt = try makeDate("2026-05-17T16:30:00Z")
        let event = LedgerEvent(
            title: "Dropped package",
            occurredAt: occurredAt,
            rawText: "Dropped package off at 4:30.",
            createdAt: occurredAt,
            updatedAt: occurredAt
        )
        context.insert(event)
        try context.save()

        let service = try makeService(context: context, exportedAt: makeDate("2026-05-17T18:30:00Z"))
        let records = try service.envelope().records

        XCTAssertEqual(records.events.first?.source.kind, "manual")
        XCTAssertEqual(records.events.first?.occurredAt, "2026-05-17")
        XCTAssertEqual(service.exportFilename(for: try makeDate("2026-05-17T18:30:00Z")), "life-ledger-export-2026-05-17-1430.json")
    }

    func testExportDataDecodesAndDoesNotContainAPIKey() throws {
        let context = makeInMemoryModelContext()
        let keyStore = InMemoryAPIKeyStore()
        try keyStore.saveOpenAIAPIKey("unit-test-secret-key")
        context.insert(ChatMessage(role: .user, text: "Changed oil.", createdAt: try makeDate("2026-05-17T13:42:10Z")))
        try context.save()

        let data = try makeService(context: context).jsonData()
        let decoded = try JSONDecoder().decode(LedgerExportEnvelope.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.records.chatMessages.first?.text, "Changed oil.")
        XCTAssertFalse(json.contains("unit-test-secret-key"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("authorization"))
    }

    func testRuleLifecycleExportIsPortableAndKeepsPrivateStateOut() throws {
        let context = makeInMemoryModelContext()
        let createdAt = try makeDate("2026-05-17T13:42:10Z")
        let completedAt = try makeDate("2026-05-18T14:00:00Z")
        let thing = Thing(
            name: "Rent",
            category: .finance,
            createdAt: createdAt,
            updatedAt: completedAt
        )
        let rule = LedgerRule(
            title: "Pay rent",
            reason: "Monthly payment",
            ruleType: .reminder,
            continuityBehavior: .dateBasedReminder,
            rawText: "Pay rent Monday.",
            startsAt: createdAt,
            createdAt: createdAt,
            updatedAt: completedAt,
            isActive: false,
            manuallyDeactivatedAt: completedAt,
            thing: thing
        )
        context.insert(thing)
        context.insert(rule)
        try context.save()

        let data = try makeService(context: context, exportedAt: completedAt).jsonData()
        let envelope = try JSONDecoder().decode(LedgerExportEnvelope.self, from: data)
        let json = String(decoding: data, as: UTF8.self)
        let exportedRule = try XCTUnwrap(envelope.records.rules.first)

        XCTAssertEqual(envelope.schemaVersion, 3)
        XCTAssertEqual(exportedRule.thingId, thing.id.uuidString)
        XCTAssertEqual(exportedRule.startsAt, "2026-05-17")
        XCTAssertEqual(exportedRule.updatedAt, "2026-05-18T14:00:00Z")
        XCTAssertEqual(exportedRule.lifecycleState, "deactivated")
        XCTAssertEqual(exportedRule.manuallyDeactivatedAt, "2026-05-18T14:00:00Z")
        XCTAssertEqual(exportedRule.source.kind, "manual")
        XCTAssertNil(exportedRule.source.chatMessageId)
        XCTAssertNil(exportedRule.source.extractionRunId)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("keychain"))
    }

    func testExportValidationRejectsBrokenEntityLinks() throws {
        let context = makeInMemoryModelContext()
        let now = try makeDate("2026-05-17T13:42:10Z")
        let message = ChatMessage(role: .user, text: "Changed oil.", createdAt: now)
        let link = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .thing,
            targetID: UUID(),
            relation: .mentionsThing,
            createdAt: now,
            createdBy: .system,
            sourceMessageID: message.id
        )
        context.insert(message)
        context.insert(link)
        try context.save()

        XCTAssertThrowsError(try makeService(context: context).jsonData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("entity link reference"))
        }
    }

    private func makeService(
        context: ModelContext,
        exportedAt: Date? = nil
    ) throws -> LocalJSONExportService {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return LocalJSONExportService(
            modelContext: context,
            now: { exportedAt ?? Date(timeIntervalSince1970: 1_779_043_800) },
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private func makeDate(_ string: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }
}
