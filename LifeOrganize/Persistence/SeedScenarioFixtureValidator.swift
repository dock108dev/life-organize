import Foundation

struct SeedScenarioFixtureValidator {
    func validate(_ fixture: SeedScenarioFixture, expectedID: String? = nil) throws {
        try require(
            fixture.fixtureSchemaVersion == SeedScenarioFixture.supportedFixtureSchemaVersion,
            "Unsupported fixtureSchemaVersion \(fixture.fixtureSchemaVersion)."
        )
        try require(
            fixture.ledgerSchemaVersion == SeedScenarioFixture.supportedLedgerSchemaVersion,
            "Unsupported ledgerSchemaVersion \(fixture.ledgerSchemaVersion)."
        )
        if let expectedID {
            try require(fixture.id == expectedID, "Fixture id \(fixture.id) does not match requested scenario \(expectedID).")
        }
        try require(!fixture.id.isEmpty, "Fixture id is required.")
        try require(!fixture.title.isEmpty, "Fixture title is required.")
        try require(!fixture.description.isEmpty, "Fixture description is required.")

        let calendar = try validateClock(fixture.clock)
        let ids = SeedScenarioRecordIDs(records: fixture.records)
        try ids.validateDuplicates()
        try validateRecords(fixture.records, ids: ids, calendar: calendar)
    }

    private func validateClock(_ clock: SeedScenarioClock) throws -> Calendar {
        _ = try SeedScenarioDateParser.timestamp(clock.now, field: "clock.now")
        guard clock.calendar == "gregorian" else {
            throw SeedScenarioLoaderError.invalidFixture("clock.calendar has invalid value \(clock.calendar).")
        }
        guard let timeZone = TimeZone(identifier: clock.timeZone) else {
            throw SeedScenarioLoaderError.invalidFixture("clock.timeZone has invalid value \(clock.timeZone).")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func validateRecords(_ records: ExportRecords, ids: SeedScenarioRecordIDs, calendar: Calendar) throws {
        try validateChatMessages(records.chatMessages, records: records, ids: ids)
        try validateExtractionRuns(records.extractionRuns, ids: ids)
        try validateThings(records.things, records: records, ids: ids, calendar: calendar)
        try validateEvents(records.events, ids: ids, calendar: calendar)
        try validateRules(records.rules, ids: ids, calendar: calendar)
        try validateNotes(records.notes, ids: ids)
        try validateEntityLinks(records.entityLinks, ids: ids)
        try validateReviewItems(records.ledgerReviewItems, ids: ids)
    }

    private func validateChatMessages(
        _ messages: [ChatMessageExport],
        records: ExportRecords,
        ids: SeedScenarioRecordIDs
    ) throws {
        for message in messages {
            try validateUUID(message.id, field: "chatMessages.id")
            try validateEnum(message.role, allowed: ChatRole.allCases.map(\.rawValue), field: "chatMessages.role")
            _ = try SeedScenarioDateParser.timestamp(message.createdAt, field: "chatMessages.createdAt")
            try validateOptionalReference(message.extractionRunId, in: ids.extractionRuns, field: "chatMessages.extractionRunId")
            try validateOptionalReference(message.latestExtractionRunId, in: ids.extractionRuns, field: "chatMessages.latestExtractionRunId")
            for runID in message.extractionRunIds + message.successfulExtractionRunIds {
                try validateReference(runID, in: ids.extractionRuns, field: "chatMessages.extractionRunIds")
            }
            if let state = message.extractionState {
                try validateEnum(state.status, allowed: ExtractionStatus.allCases.map(\.rawValue), field: "chatMessages.extractionState.status")
                try validateOptionalEnum(state.errorCode, allowed: ExtractionErrorCode.allCases.map(\.rawValue), field: "chatMessages.extractionState.errorCode")
                try validateOptionalEnum(
                    state.latestAttemptStatus,
                    allowed: ExtractionAttemptStatus.allCases.map(\.rawValue),
                    field: "chatMessages.extractionState.latestAttemptStatus"
                )
                try validateOptionalEnum(
                    state.latestAttemptErrorCode,
                    allowed: ExtractionErrorCode.allCases.map(\.rawValue),
                    field: "chatMessages.extractionState.latestAttemptErrorCode"
                )
                if let lastAttemptAt = state.lastAttemptAt {
                    _ = try SeedScenarioDateParser.timestamp(lastAttemptAt, field: "chatMessages.extractionState.lastAttemptAt")
                }
                if let nextRetryAt = state.nextRetryAt {
                    _ = try SeedScenarioDateParser.timestamp(nextRetryAt, field: "chatMessages.extractionState.nextRetryAt")
                }
            }

            let linkedSourceIDs = records.things.filter { $0.source.chatMessageId == message.id }.map(\.id)
                + records.events.filter { $0.source.chatMessageId == message.id }.map(\.id)
                + records.rules.filter { $0.source.chatMessageId == message.id }.map(\.id)
                + records.notes.filter { $0.source.chatMessageId == message.id }.map(\.id)
            for id in linkedSourceIDs {
                try require(
                    message.linkedEntityIds.contains(id),
                    "Chat message \(message.id) linkedEntityIds must include source-linked record \(id)."
                )
            }
        }
    }

    private func validateExtractionRuns(_ runs: [ExtractionRunExport], ids: SeedScenarioRecordIDs) throws {
        for run in runs {
            try validateUUID(run.id, field: "extractionRuns.id")
            try validateOptionalReference(run.chatMessageId, in: ids.chatMessages, field: "extractionRuns.chatMessageId")
            try validateEnum(run.status, allowed: ExtractionAttemptStatus.allCases.map(\.rawValue), field: "extractionRuns.status")
            let requestedAt = try SeedScenarioDateParser.timestamp(run.requestedAt, field: "extractionRuns.requestedAt")
            if let completedAt = run.completedAt {
                try require(
                    try SeedScenarioDateParser.timestamp(completedAt, field: "extractionRuns.completedAt") >= requestedAt,
                    "Extraction run \(run.id) completedAt must be on or after requestedAt."
                )
            }
            try validateOptionalEnum(run.error?.kind, allowed: ExtractionErrorCode.allCases.map(\.rawValue), field: "extractionRuns.error.kind")
            let createdIDs = run.createdEntities.things + run.createdEntities.events + run.createdEntities.rules + run.createdEntities.notes
            try require(Set(run.createdEntityIds) == Set(createdIDs), "Extraction run \(run.id) createdEntityIds must match createdEntities.")
            for id in run.createdEntities.things {
                try validateReference(id, in: ids.things, field: "extractionRuns.createdEntities.things")
            }
            for id in run.createdEntities.events {
                try validateReference(id, in: ids.events, field: "extractionRuns.createdEntities.events")
            }
            for id in run.createdEntities.rules {
                try validateReference(id, in: ids.rules, field: "extractionRuns.createdEntities.rules")
            }
            for id in run.createdEntities.notes {
                try validateReference(id, in: ids.notes, field: "extractionRuns.createdEntities.notes")
            }
        }
    }

    private func validateThings(
        _ things: [ThingExport],
        records: ExportRecords,
        ids: SeedScenarioRecordIDs,
        calendar: Calendar
    ) throws {
        for thing in things {
            try validateUUID(thing.id, field: "things.id")
            try validateOptionalEnum(thing.category, allowed: ThingCategory.allCases.map(\.rawValue), field: "things.category")
            let createdAt = try SeedScenarioDateParser.timestamp(thing.createdAt, field: "things.createdAt")
            let updatedAt = try SeedScenarioDateParser.timestamp(thing.updatedAt, field: "things.updatedAt")
            try require(updatedAt >= createdAt, "Thing \(thing.id) updatedAt must be on or after createdAt.")
            let linkedEvents = records.events.filter { $0.thingId == thing.id }
            try require(thing.eventCount == linkedEvents.count, "Thing \(thing.id) eventCount must match linked events.")
            let latestEventDate = try linkedEvents
                .map { try SeedScenarioDateParser.dateOnly($0.occurredAt, calendar: calendar, field: "events.occurredAt") }
                .max()
            let expectedLastEventAt = try thing.lastEventAt.map {
                try SeedScenarioDateParser.dateOnly($0, calendar: calendar, field: "things.lastEventAt")
            }
            try require(expectedLastEventAt == latestEventDate, "Thing \(thing.id) lastEventAt must match linked events.")
            try validateSource(thing.source, ids: ids, field: "things.source")
        }
    }

    private func validateEvents(_ events: [EventExport], ids: SeedScenarioRecordIDs, calendar: Calendar) throws {
        for event in events {
            try validateUUID(event.id, field: "events.id")
            try validateOptionalReference(event.thingId, in: ids.things, field: "events.thingId")
            try validateEnum(event.eventType, allowed: LedgerEventType.allCases.map(\.rawValue), field: "events.eventType")
            _ = try SeedScenarioDateParser.dateOnly(event.occurredAt, calendar: calendar, field: "events.occurredAt")
            let createdAt = try SeedScenarioDateParser.timestamp(event.createdAt, field: "events.createdAt")
            let updatedAt = try SeedScenarioDateParser.timestamp(event.updatedAt, field: "events.updatedAt")
            try require(updatedAt >= createdAt, "Event \(event.id) updatedAt must be on or after createdAt.")
            for metadata in event.metadata {
                try validateMetadata(metadata, eventID: event.id, calendar: calendar)
            }
            try validateSource(event.source, ids: ids, field: "events.source")
        }
    }

    private func validateRules(_ rules: [RuleExport], ids: SeedScenarioRecordIDs, calendar: Calendar) throws {
        for rule in rules {
            try validateUUID(rule.id, field: "rules.id")
            try validateOptionalReference(rule.thingId, in: ids.things, field: "rules.thingId")
            try validateEnum(rule.ruleType, allowed: LedgerRuleType.allCases.map(\.rawValue), field: "rules.ruleType")
            try validateEnum(
                rule.continuityBehavior,
                allowed: LedgerContinuityBehavior.allCases.map(\.rawValue),
                field: "rules.continuityBehavior"
            )
            try validateEnum(rule.lifecycleState, allowed: LedgerRuleLifecycleState.allCases.map(\.rawValue), field: "rules.lifecycleState")
            _ = try SeedScenarioDateParser.dateOnly(rule.startsAt, calendar: calendar, field: "rules.startsAt")
            if let expiresAt = rule.expiresAt {
                _ = try SeedScenarioDateParser.dateOnly(expiresAt, calendar: calendar, field: "rules.expiresAt")
            }
            let createdAt = try SeedScenarioDateParser.timestamp(rule.createdAt, field: "rules.createdAt")
            let updatedAt = try SeedScenarioDateParser.timestamp(rule.updatedAt, field: "rules.updatedAt")
            try require(updatedAt >= createdAt, "Rule \(rule.id) updatedAt must be on or after createdAt.")
            if let deactivatedAt = rule.manuallyDeactivatedAt {
                _ = try SeedScenarioDateParser.timestamp(deactivatedAt, field: "rules.manuallyDeactivatedAt")
            }
            try validateSource(rule.source, ids: ids, field: "rules.source")
        }
    }

    private func validateNotes(_ notes: [NoteExport], ids: SeedScenarioRecordIDs) throws {
        for note in notes {
            try validateUUID(note.id, field: "notes.id")
            let createdAt = try SeedScenarioDateParser.timestamp(note.createdAt, field: "notes.createdAt")
            let updatedAt = try SeedScenarioDateParser.timestamp(note.updatedAt, field: "notes.updatedAt")
            try require(updatedAt >= createdAt, "Note \(note.id) updatedAt must be on or after createdAt.")
            for thingID in note.linkedThingIds {
                try validateReference(thingID, in: ids.things, field: "notes.linkedThingIds")
            }
            try validateSource(note.source, ids: ids, field: "notes.source")
        }
    }

    private func validateEntityLinks(_ links: [EntityLinkExport], ids: SeedScenarioRecordIDs) throws {
        for link in links {
            try validateUUID(link.id, field: "entityLinks.id")
            try validateEntityReference(type: link.fromEntityType, id: link.fromEntityId, ids: ids, field: "entityLinks.from")
            try validateEntityReference(type: link.toEntityType, id: link.toEntityId, ids: ids, field: "entityLinks.to")
            try validateEnum(link.relationship, allowed: ["created_from", "mentions", "linked_to", "related_to"], field: "entityLinks.relationship")
            _ = try SeedScenarioDateParser.timestamp(link.createdAt, field: "entityLinks.createdAt")
            try validateSource(link.source, ids: ids, field: "entityLinks.source")
        }
    }

    private func validateReviewItems(_ items: [LedgerReviewItemExport], ids: SeedScenarioRecordIDs) throws {
        for item in items {
            try validateUUID(item.id, field: "ledgerReviewItems.id")
            try validateEnum(item.kind, allowed: LedgerReviewItemKind.allCases.map(\.rawValue), field: "ledgerReviewItems.kind")
            try validateEnum(item.state, allowed: LedgerReviewItemState.allCases.map(\.rawValue), field: "ledgerReviewItems.state")
            try validateEnum(item.targetType, allowed: LedgerReviewItemTargetType.allCases.map(\.rawValue), field: "ledgerReviewItems.targetType")
            try validateReviewReference(item.targetId, type: item.targetType, ids: ids, field: "ledgerReviewItems.targetId")
            let createdAt = try SeedScenarioDateParser.timestamp(item.createdAt, field: "ledgerReviewItems.createdAt")
            let updatedAt = try SeedScenarioDateParser.timestamp(item.updatedAt, field: "ledgerReviewItems.updatedAt")
            try require(updatedAt >= createdAt, "Review item \(item.id) updatedAt must be on or after createdAt.")
            try require((0...1).contains(item.confidence), "Review item \(item.id) confidence must be between 0 and 1.")
            for evidence in item.evidence {
                try validateReviewReference(evidence.sourceId, type: evidence.sourceType, ids: ids, field: "ledgerReviewItems.evidence.sourceId")
            }
        }
    }

    private func validateMetadata(_ metadata: EventMetadataExport, eventID: String, calendar: Calendar) throws {
        try validateEnum(metadata.key, allowed: LedgerEventMetadataKey.allCases.map(\.rawValue), field: "events.metadata.key")
        try validateEnum(metadata.valueKind, allowed: LedgerEventMetadataValueKind.allCases.map(\.rawValue), field: "events.metadata.valueKind")
        if let dateValue = metadata.dateValue {
            _ = try SeedScenarioDateParser.dateOnly(dateValue, calendar: calendar, field: "events.metadata.dateValue")
        }
        let valueCount = [
            metadata.stringValue != nil,
            metadata.numberValue != nil,
            metadata.dateValue != nil,
            metadata.boolValue != nil,
        ].filter { $0 }.count
        try require(valueCount == 1, "Event \(eventID) metadata \(metadata.key) must set exactly one value field.")
    }

    private func validateSource(_ source: ExportSource, ids: SeedScenarioRecordIDs, field: String) throws {
        try validateEnum(source.kind, allowed: ["manual", "extracted", "system"], field: "\(field).kind")
        try validateOptionalReference(source.chatMessageId, in: ids.chatMessages, field: "\(field).chatMessageId")
        try validateOptionalReference(source.extractionRunId, in: ids.extractionRuns, field: "\(field).extractionRunId")
        if source.kind == "manual" {
            try require(source.chatMessageId == nil && source.extractionRunId == nil, "\(field) manual source must not include provenance.")
        }
        if source.kind == "extracted" {
            try require(
                source.chatMessageId != nil || source.extractionRunId != nil || source.sourceClientId != nil,
                "\(field) extracted source must include provenance."
            )
        }
    }

    private func validateReviewReference(_ id: String?, type: String, ids: SeedScenarioRecordIDs, field: String) throws {
        guard let id else {
            try require(type == LedgerReviewItemTargetType.none.rawValue, "\(field) requires an id unless target type is none.")
            return
        }
        try validateReference(id, in: ids.reviewItemEntityIDs(for: type), field: field)
    }

    private func validateEntityReference(type: String, id: String, ids: SeedScenarioRecordIDs, field: String) throws {
        try validateReference(id, in: ids.entityIDs(for: type), field: field)
    }

    private func validateOptionalReference(_ id: String?, in ids: Set<String>, field: String) throws {
        guard let id else { return }
        try validateReference(id, in: ids, field: field)
    }

    private func validateReference(_ id: String, in ids: Set<String>, field: String) throws {
        try validateUUID(id, field: field)
        if !ids.contains(id) {
            throw SeedScenarioLoaderError.invalidFixture("\(field) references missing record \(id).")
        }
    }

    private func validateUUID(_ text: String, field: String) throws {
        if UUID(uuidString: text) == nil {
            throw SeedScenarioLoaderError.invalidFixture("\(field) must be a UUID string: \(text).")
        }
    }

    private func validateOptionalEnum(_ value: String?, allowed: [String], field: String) throws {
        guard let value else { return }
        try validateEnum(value, allowed: allowed, field: field)
    }

    private func validateEnum(_ value: String, allowed: [String], field: String) throws {
        if !allowed.contains(value) {
            throw SeedScenarioLoaderError.invalidFixture("\(field) has invalid value \(value).")
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SeedScenarioLoaderError.invalidFixture(message)
        }
    }
}

