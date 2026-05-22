import Foundation
@testable import LifeOrganize

struct ScenarioFixtureValidator {
    func validate(_ fixture: ScenarioFixture) throws {
        try validateSupportedVersions(fixture)
        try validateClock(fixture.clock)
        let ids = FixtureRecordIDs(records: fixture.records)
        try ids.validateDuplicates()
        try validateRecordFields(fixture.records, ids: ids, clock: fixture.clock)
        try validateExpectations(fixture.expectations, ids: ids)
    }

    private func validateSupportedVersions(_ fixture: ScenarioFixture) throws {
        try require(
            fixture.fixtureSchemaVersion == ScenarioFixture.supportedFixtureSchemaVersion,
            "Unsupported fixtureSchemaVersion \(fixture.fixtureSchemaVersion)."
        )
        try require(
            fixture.ledgerSchemaVersion == ScenarioFixture.supportedLedgerSchemaVersion,
            "Unsupported ledgerSchemaVersion \(fixture.ledgerSchemaVersion)."
        )
        try require(!fixture.id.isEmpty, "Fixture id is required.")
        try require(!fixture.title.isEmpty, "Fixture title is required.")
        try require(!fixture.description.isEmpty, "Fixture description is required.")
    }

    private func validateClock(_ clock: ScenarioFixtureClock) throws {
        _ = try parseTimestamp(clock.now, field: "clock.now")
        try require(clock.calendar == "gregorian", "Unsupported clock.calendar \(clock.calendar).")
        try require(TimeZone(identifier: clock.timeZone) != nil, "Invalid clock.timeZone \(clock.timeZone).")
    }

    private func validateRecordFields(
        _ records: ExportRecords,
        ids: FixtureRecordIDs,
        clock: ScenarioFixtureClock
    ) throws {
        try validateChatMessages(records.chatMessages, records: records, ids: ids)
        try validateExtractionRuns(records.extractionRuns, records: records, ids: ids, clock: clock)
        try validateEvents(records.events, ids: ids)
        try validateThings(records.things, records: records, ids: ids)
        try validateRules(records.rules, ids: ids)
        try validateNotes(records.notes, ids: ids)
        try validateReviewItems(records.ledgerReviewItems, ids: ids)
        try validateEntityLinks(records.entityLinks, ids: ids)
    }

    private func validateChatMessages(
        _ messages: [ChatMessageExport],
        records: ExportRecords,
        ids: FixtureRecordIDs
    ) throws {
        let runsByMessage = Dictionary(grouping: records.extractionRuns, by: \.chatMessageId)
        for message in messages {
            try validateUUID(message.id, field: "chatMessages.id")
            try validateEnum(message.role, allowed: ChatRole.allCases.map(\.rawValue), field: "chatMessages.role")
            _ = try parseTimestamp(message.createdAt, field: "chatMessages.createdAt")
            try validateOptionalReference(message.extractionRunId, in: ids.extractionRuns, field: "chatMessages.extractionRunId")
            try validateOptionalReference(
                message.latestExtractionRunId,
                in: ids.extractionRuns,
                field: "chatMessages.latestExtractionRunId"
            )
            for id in message.extractionRunIds + message.successfulExtractionRunIds + message.linkedEntityIds {
                try validateUUID(id, field: "chatMessages linked id")
            }
            if let state = message.extractionState {
                try validateExtractionState(state)
            }

            let chronologicalRuns = (runsByMessage[message.id] ?? []).sorted { $0.requestedAt < $1.requestedAt }
            try require(
                chronologicalRuns.map(\.id) == message.extractionRunIds,
                "Chat message \(message.id) extractionRunIds must match its runs by requestedAt."
            )
            try require(
                message.latestExtractionRunId == chronologicalRuns.last?.id,
                "Chat message \(message.id) latestExtractionRunId must be the latest requested run."
            )
            let successfulRunIDs = chronologicalRuns
                .filter { $0.status == ExtractionAttemptStatus.succeeded.rawValue || $0.status == ExtractionAttemptStatus.partiallySucceeded.rawValue }
                .map(\.id)
            try require(
                message.successfulExtractionRunIds == successfulRunIDs,
                "Chat message \(message.id) successfulExtractionRunIds must match succeeded runs."
            )
            try validateSourceBacklinks(for: message, records: records)
        }
    }

    private func validateExtractionState(_ state: ChatMessageExtractionStateExport) throws {
        try validateEnum(state.status, allowed: ExtractionStatus.allCases.map(\.rawValue), field: "extractionState.status")
        if let errorCode = state.errorCode {
            try validateEnum(errorCode, allowed: ExtractionErrorCode.allCases.map(\.rawValue), field: "extractionState.errorCode")
        }
        if let lastAttemptAt = state.lastAttemptAt {
            _ = try parseTimestamp(lastAttemptAt, field: "extractionState.lastAttemptAt")
        }
        if let nextRetryAt = state.nextRetryAt {
            _ = try parseTimestamp(nextRetryAt, field: "extractionState.nextRetryAt")
        }
        if let latestAttemptStatus = state.latestAttemptStatus {
            try validateEnum(
                latestAttemptStatus,
                allowed: ExtractionAttemptStatus.allCases.map(\.rawValue),
                field: "extractionState.latestAttemptStatus"
            )
        }
        if let latestAttemptErrorCode = state.latestAttemptErrorCode {
            try validateEnum(
                latestAttemptErrorCode,
                allowed: ExtractionErrorCode.allCases.map(\.rawValue),
                field: "extractionState.latestAttemptErrorCode"
            )
        }
    }

    private func validateExtractionRuns(
        _ runs: [ExtractionRunExport],
        records: ExportRecords,
        ids: FixtureRecordIDs,
        clock: ScenarioFixtureClock
    ) throws {
        let messagesByID = Dictionary(uniqueKeysWithValues: records.chatMessages.map { ($0.id, $0) })
        for run in runs {
            try validateUUID(run.id, field: "extractionRuns.id")
            try validateOptionalReference(run.chatMessageId, in: ids.chatMessages, field: "extractionRuns.chatMessageId")
            try validateEnum(run.status, allowed: ExtractionAttemptStatus.allCases.map(\.rawValue), field: "extractionRuns.status")
            let requestedAt = try parseTimestamp(run.requestedAt, field: "extractionRuns.requestedAt")
            if let completedAtText = run.completedAt {
                let completedAt = try parseTimestamp(completedAtText, field: "extractionRuns.completedAt")
                try require(completedAt >= requestedAt, "Extraction run \(run.id) completedAt must be on or after requestedAt.")
            }
            if let input = run.input {
                _ = try parseTimestamp(input.referenceNow, field: "extractionRuns.input.referenceNow")
                try require(input.timeZone == clock.timeZone, "Extraction run \(run.id) input.timeZone must match fixture clock.")
                if let messageID = run.chatMessageId, let message = messagesByID[messageID] {
                    try require(input.userText == message.text, "Extraction run \(run.id) input.userText must match its source message.")
                    try require(
                        input.referenceNow == message.createdAt,
                        "Extraction run \(run.id) input.referenceNow must match its source message createdAt."
                    )
                }
            }
            let createdEntityIDs = Set(run.createdEntities.things + run.createdEntities.events + run.createdEntities.rules + run.createdEntities.notes)
            try require(
                Set(run.createdEntityIds) == createdEntityIDs,
                "Extraction run \(run.id) createdEntityIds must match createdEntities."
            )
            for thingID in run.createdEntities.things {
                try validateReference(thingID, in: ids.things, field: "extractionRuns.createdEntities.things")
            }
            for eventID in run.createdEntities.events {
                try validateReference(eventID, in: ids.events, field: "extractionRuns.createdEntities.events")
            }
            for ruleID in run.createdEntities.rules {
                try validateReference(ruleID, in: ids.rules, field: "extractionRuns.createdEntities.rules")
            }
            for noteID in run.createdEntities.notes {
                try validateReference(noteID, in: ids.notes, field: "extractionRuns.createdEntities.notes")
            }
            if let error = run.error {
                try validateEnum(error.kind, allowed: ExtractionErrorCode.allCases.map(\.rawValue), field: "extractionRuns.error.kind")
                try require(!error.message.isEmpty, "Extraction run \(run.id) error.message is required when error exists.")
            }
        }
    }

    private func validateThings(_ things: [ThingExport], records: ExportRecords, ids: FixtureRecordIDs) throws {
        let eventsByThingID = Dictionary(grouping: records.events.compactMap { event -> (String, EventExport)? in
            guard let thingID = event.thingId else { return nil }
            return (thingID, event)
        }, by: \.0)
        for thing in things {
            try validateUUID(thing.id, field: "things.id")
            if let category = thing.category {
                try validateEnum(category, allowed: ThingCategory.allCases.map(\.rawValue), field: "things.category")
            }
            let createdAt = try parseTimestamp(thing.createdAt, field: "things.createdAt")
            let updatedAt = try parseTimestamp(thing.updatedAt, field: "things.updatedAt")
            try require(updatedAt >= createdAt, "Thing \(thing.id) updatedAt must be on or after createdAt.")
            try validateSource(thing.source, ids: ids, field: "things.source")
            let linkedEvents = (eventsByThingID[thing.id] ?? []).map(\.1)
            try require(thing.eventCount == linkedEvents.count, "Thing \(thing.id) eventCount must match linked events.")
            let expectedLastEventAt = linkedEvents.map(\.occurredAt).max()
            try require(thing.lastEventAt == expectedLastEventAt, "Thing \(thing.id) lastEventAt must match latest event.")
            if let lastEventAt = thing.lastEventAt {
                _ = try parseDateOnly(lastEventAt, field: "things.lastEventAt")
            }
        }
    }

    private func validateEvents(_ events: [EventExport], ids: FixtureRecordIDs) throws {
        for event in events {
            try validateUUID(event.id, field: "events.id")
            try validateOptionalReference(event.thingId, in: ids.things, field: "events.thingId")
            try validateEnum(event.eventType, allowed: LedgerEventType.allCases.map(\.rawValue), field: "events.eventType")
            _ = try parseDateOnly(event.occurredAt, field: "events.occurredAt")
            let createdAt = try parseTimestamp(event.createdAt, field: "events.createdAt")
            let updatedAt = try parseTimestamp(event.updatedAt, field: "events.updatedAt")
            try require(updatedAt >= createdAt, "Event \(event.id) updatedAt must be on or after createdAt.")
            try validateSource(event.source, ids: ids, field: "events.source")
            for metadata in event.metadata {
                try validateMetadata(metadata, eventID: event.id)
            }
        }
    }
}
