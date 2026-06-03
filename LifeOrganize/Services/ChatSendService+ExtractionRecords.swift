import Foundation

@MainActor
extension ChatSendService {
    func createEntities(
        from envelope: ExtractionEnvelope,
        sourceMessage: ChatMessage,
        attempt: ExtractionAttempt
    ) throws -> ChatConfirmationRecords {
        var createdRecords = ChatConfirmationRecords()
        var createdThingIDs = Set(attempt.createdThingIDs)
        var siblingEntities: [(EntityLinkType, UUID)] = []
        var resolvedThingsByKey: [String: Thing] = [:]
        let resolver = ThingResolver(modelContext: modelContext, now: { dateProvider.now })
        let linkWriter = EntityLinkWriter(modelContext: modelContext, now: { dateProvider.now })
        let derivedFields = DerivedFieldMaintenanceService(modelContext: modelContext, now: { dateProvider.now })

        func rememberResolvedThing(_ thing: Thing, values: [String]) {
            for value in [thing.name] + thing.aliases + values {
                let key = ThingNormalizer.normalizeKey(value)
                if !key.isEmpty {
                    resolvedThingsByKey[key] = thing
                }
            }
        }

        func knownResolvedThing(name: String, aliases: [String] = []) -> Thing? {
            ([name] + aliases).lazy
                .map(ThingNormalizer.normalizeKey)
                .compactMap { resolvedThingsByKey[$0] }
                .first
        }

        for extractedThing in envelope.things {
            let thing = try resolver.resolve(
                name: extractedThing.name,
                aliases: extractedThing.aliases,
                categoryHint: extractedThing.category,
                contextText: sourceMessage.text,
                sourceMessage: sourceMessage,
                attempt: attempt,
                modelConfidence: extractedThing.confidence
            )
            createdThingIDs.insert(thing.id)
            createdRecords.standaloneThings.append(thing)
            siblingEntities.append((.thing, thing.id))
            rememberResolvedThing(thing, values: [extractedThing.name] + extractedThing.aliases)
            try linkWriter.linkMessage(sourceMessage, mentions: thing)
        }

        for extractedEvent in envelope.events {
            let eventContextText = normalizationContextText(for: extractedEvent, sourceMessage: sourceMessage)
            if let existingEvent = try existingEvent(for: sourceMessage, clientID: extractedEvent.clientID) {
                guard appendUnique(existingEvent.id, to: &attempt.createdEventIDs) else {
                    continue
                }
                createdRecords.events.append(existingEvent)
                siblingEntities.append((.event, existingEvent.id))
                try linkWriter.linkExtracted(message: sourceMessage, event: existingEvent)
                if let thing = existingEvent.thing {
                    createdThingIDs.insert(thing.id)
                    try derivedFields.refreshThing(thing)
                    try linkWriter.linkMessage(sourceMessage, mentions: thing)
                    try linkWriter.linkPrimary(event: existingEvent, thing: thing, sourceMessage: sourceMessage)
                }
                continue
            }

            let thing = try extractedEvent.thingName.map {
                if let knownThing = knownResolvedThing(name: $0, aliases: [extractedEvent.title]) {
                    knownThing.registerAliases([extractedEvent.title], updatedAt: dateProvider.now)
                    rememberResolvedThing(knownThing, values: [$0, extractedEvent.title])
                    return knownThing
                }
                return try resolver.resolve(
                    name: $0,
                    aliases: [extractedEvent.title],
                    eventTypeHint: extractedEvent.eventType,
                    contextText: eventContextText,
                    sourceMessage: sourceMessage,
                    attempt: attempt
                )
            }
            if let thing, let thingName = extractedEvent.thingName {
                rememberResolvedThing(thing, values: [thingName, extractedEvent.title])
            }

            if let correctedEvent = try correctionTargetEvent(for: extractedEvent, thing: thing, sourceMessage: sourceMessage) {
                let previousThing = correctedEvent.thing
                correctedEvent.title = extractedEvent.title
                correctedEvent.occurredAt = resolvedExtractionDate(
                    extractedEvent.occurredAt,
                    sourceMessage: sourceMessage,
                    contextText: eventContextText
                ) ?? correctedEvent.occurredAt
                correctedEvent.rawText = extractedEvent.rawText?.nilIfEmpty ?? sourceMessage.text
                correctedEvent.note = extractedEvent.note
                correctedEvent.sourceClientID = extractedEvent.clientID
                correctedEvent.sourceExtractionRunID = attempt.id
                correctedEvent.eventType = LedgerEventType(rawValue: extractedEvent.eventType) ?? .other
                correctedEvent.metadataEntries = metadataEntries(from: extractedEvent.metadata)
                correctedEvent.updatedAt = dateProvider.now
                if correctedEvent.thing == nil, let thing {
                    try derivedFields.reassignEvent(correctedEvent, to: thing)
                } else {
                    try derivedFields.updateEvent(correctedEvent, previousThing: previousThing)
                }
                appendUnique(correctedEvent.id, to: &attempt.createdEventIDs)
                createdRecords.events.append(correctedEvent)
                siblingEntities.append((.event, correctedEvent.id))
                try linkWriter.linkExtracted(message: sourceMessage, event: correctedEvent)
                if let correctedThing = correctedEvent.thing {
                    createdThingIDs.insert(correctedThing.id)
                    correctedThing.updatedAt = dateProvider.now
                    siblingEntities.append((.thing, correctedThing.id))
                    try linkWriter.linkMessage(sourceMessage, mentions: correctedThing)
                    try linkWriter.linkPrimary(event: correctedEvent, thing: correctedThing, sourceMessage: sourceMessage)
                }
                continue
            }

            let event = LedgerEvent(
                title: extractedEvent.title,
                occurredAt: resolvedExtractionDate(
                    extractedEvent.occurredAt,
                    sourceMessage: sourceMessage,
                    contextText: eventContextText
                ) ?? sourceMessage.createdAt,
                rawText: extractedEvent.rawText?.nilIfEmpty ?? sourceMessage.text,
                createdAt: dateProvider.now,
                updatedAt: dateProvider.now,
                note: extractedEvent.note,
                sourceClientID: extractedEvent.clientID,
                sourceExtractionRunID: attempt.id,
                eventType: LedgerEventType(rawValue: extractedEvent.eventType) ?? .other,
                metadataEntries: metadataEntries(from: extractedEvent.metadata),
                thing: thing,
                sourceMessage: sourceMessage
            )
            try derivedFields.insertEvent(event)
            appendUnique(event.id, to: &attempt.createdEventIDs)
            createdRecords.events.append(event)
            siblingEntities.append((.event, event.id))
            try linkWriter.linkExtracted(message: sourceMessage, event: event)
            if let thing {
                createdThingIDs.insert(thing.id)
                thing.updatedAt = dateProvider.now
                siblingEntities.append((.thing, thing.id))
                try linkWriter.linkMessage(sourceMessage, mentions: thing)
                try linkWriter.linkPrimary(event: event, thing: thing, sourceMessage: sourceMessage)
            }
        }

        for extractedRule in envelope.rules {
            if let existingRule = try existingRule(for: sourceMessage, clientID: extractedRule.clientID) {
                guard appendUnique(existingRule.id, to: &attempt.createdRuleIDs) else {
                    continue
                }
                createdRecords.rules.append(existingRule)
                siblingEntities.append((.rule, existingRule.id))
                try linkWriter.linkExtracted(message: sourceMessage, rule: existingRule)
                if let thing = existingRule.thing {
                    createdThingIDs.insert(thing.id)
                    thing.updatedAt = dateProvider.now
                    try linkWriter.linkMessage(sourceMessage, mentions: thing)
                    try linkWriter.linkPrimary(rule: existingRule, thing: thing, sourceMessage: sourceMessage)
                }
                continue
            }

            let thing = try extractedRule.thingName.map {
                if let knownThing = knownResolvedThing(name: $0, aliases: [extractedRule.title]) {
                    knownThing.registerAliases([extractedRule.title], updatedAt: dateProvider.now)
                    rememberResolvedThing(knownThing, values: [$0, extractedRule.title])
                    return knownThing
                }
                return try resolver.resolve(
                    name: $0,
                    aliases: [extractedRule.title],
                    contextText: sourceMessage.text,
                    sourceMessage: sourceMessage,
                    attempt: attempt
                )
            }
            if let thing, let thingName = extractedRule.thingName {
                rememberResolvedThing(thing, values: [thingName, extractedRule.title])
            }

            let normalizedTitle = RuleTitleNormalizer.normalizedTitle(
                extractedTitle: extractedRule.title, sourceText: sourceMessage.text,
                ruleType: extractedRule.ruleType, thingName: extractedRule.thingName,
                startsAt: extractedRule.startsAt, expiresAt: extractedRule.expiresAt
            )
            let rule = LedgerRule(
                title: normalizedTitle,
                reason: extractedRule.reason,
                ruleType: extractedRule.ruleType,
                continuityBehavior: extractedRule.continuityBehavior,
                rawText: sourceMessage.text,
                startsAt: resolvedExtractionDate(
                    extractedRule.startsAt,
                    sourceMessage: sourceMessage,
                    contextText: sourceMessage.text
                ) ?? sourceMessage.createdAt,
                expiresAt: extractedRule.expiresAt.flatMap { ExtractionService.parseDate($0) },
                createdAt: dateProvider.now,
                updatedAt: dateProvider.now,
                sourceClientID: extractedRule.clientID,
                sourceExtractionRunID: attempt.id,
                thing: thing,
                sourceMessage: sourceMessage
            )
            try derivedFields.insertRule(rule)
            appendUnique(rule.id, to: &attempt.createdRuleIDs)
            createdRecords.rules.append(rule)
            siblingEntities.append((.rule, rule.id))
            try linkWriter.linkExtracted(message: sourceMessage, rule: rule)
            if let thing {
                createdThingIDs.insert(thing.id)
                thing.updatedAt = dateProvider.now
                siblingEntities.append((.thing, thing.id))
                try linkWriter.linkMessage(sourceMessage, mentions: thing)
                try linkWriter.linkPrimary(rule: rule, thing: thing, sourceMessage: sourceMessage)
            }
        }

        try createNotes(
            from: envelope.notes,
            sourceMessage: sourceMessage,
            attempt: attempt,
            createdRecords: &createdRecords,
            createdThingIDs: &createdThingIDs,
            siblingEntities: &siblingEntities,
            resolvedThingsByKey: &resolvedThingsByKey,
            resolver: resolver,
            linkWriter: linkWriter
        )

        try linkWriter.linkSiblings(siblingEntities, sourceMessage: sourceMessage)
        attempt.createdThingIDs = Array(createdThingIDs)
        let linkedThingIDs = Set(
            createdRecords.events.compactMap { $0.thing?.id }
                + createdRecords.rules.compactMap { $0.thing?.id }
                + createdRecords.notes.flatMap { $0.linkedThings.map(\.id) }
        )
        createdRecords.standaloneThings.removeAll { linkedThingIDs.contains($0.id) }
        return createdRecords
    }

    private func createNotes(
        from extractedNotes: [ExtractedNote],
        sourceMessage: ChatMessage,
        attempt: ExtractionAttempt,
        createdRecords: inout ChatConfirmationRecords,
        createdThingIDs: inout Set<UUID>,
        siblingEntities: inout [(EntityLinkType, UUID)],
        resolvedThingsByKey: inout [String: Thing],
        resolver: ThingResolver,
        linkWriter: EntityLinkWriter
    ) throws {
        func rememberResolvedThing(_ thing: Thing, values: [String]) {
            for value in [thing.name] + thing.aliases + values {
                let key = ThingNormalizer.normalizeKey(value)
                if !key.isEmpty {
                    resolvedThingsByKey[key] = thing
                }
            }
        }

        func knownResolvedThing(name: String) -> Thing? {
            ThingNormalizer.normalizeKey(name).nilIfEmpty.flatMap { resolvedThingsByKey[$0] }
        }

        for extractedNote in extractedNotes {
            if let existingNote = try existingNote(for: sourceMessage, clientID: extractedNote.clientID) {
                guard appendUnique(existingNote.id, to: &attempt.createdNoteIDs) else {
                    continue
                }
                createdRecords.notes.append(existingNote)
                siblingEntities.append((.note, existingNote.id))
                try linkWriter.linkExtracted(message: sourceMessage, note: existingNote)
                for thing in existingNote.linkedThings {
                    createdThingIDs.insert(thing.id)
                    thing.updatedAt = dateProvider.now
                    try linkWriter.linkMessage(sourceMessage, mentions: thing)
                    try linkWriter.linkAbout(note: existingNote, thing: thing, sourceMessage: sourceMessage)
                }
                continue
            }

            let things = try extractedNote.linkedThingNames.map {
                if let knownThing = knownResolvedThing(name: $0) {
                    return knownThing
                }
                return try resolver.resolve(
                    name: $0,
                    aliases: [],
                    contextText: sourceMessage.text,
                    sourceMessage: sourceMessage,
                    attempt: attempt
                )
            }
            zip(extractedNote.linkedThingNames, things).forEach { thingName, thing in
                rememberResolvedThing(thing, values: [thingName])
            }

            let note = LedgerNote(
                text: extractedNote.text,
                createdAt: dateProvider.now,
                updatedAt: dateProvider.now,
                sourceClientID: extractedNote.clientID,
                sourceExtractionRunID: attempt.id,
                sourceMessage: sourceMessage,
                linkedThings: things
            )
            modelContext.insert(note)
            appendUnique(note.id, to: &attempt.createdNoteIDs)
            createdRecords.notes.append(note)
            siblingEntities.append((.note, note.id))
            try linkWriter.linkExtracted(message: sourceMessage, note: note)
            things.forEach { thing in
                createdThingIDs.insert(thing.id)
                thing.updatedAt = dateProvider.now
                siblingEntities.append((.thing, thing.id))
            }
            for thing in things {
                try linkWriter.linkMessage(sourceMessage, mentions: thing)
                try linkWriter.linkAbout(note: note, thing: thing, sourceMessage: sourceMessage)
            }
        }
    }

    func recallAnswer(from envelope: ExtractionEnvelope) throws -> String? {
        guard let query = envelope.recallQueries.first else { return nil }
        let intent: ChatLedgerIntent
        switch query.queryType {
        case "last_time":
            intent = .lookupLastTime
        case "rule_check":
            intent = .lookupRule
        case "note_lookup":
            intent = .lookupPriorNotes
        case "search":
            intent = .localSearch
        default:
            intent = .unsupported
        }
        let targetText = query.thingName ?? query.rawText
        return try ChatRecallResponseService(modelContext: modelContext, now: dateProvider.now).answer(
            for: ChatIntentClassification(intent: intent, targetText: targetText)
        )
    }

    func persistAssistantMessage(_ text: String) {
        let message = ChatMessage(
            role: .assistant,
            text: text,
            createdAt: dateProvider.now,
            extractionStatus: .notRequired
        )
        modelContext.insert(message)
    }

    func canWriteResults(for generation: UUID?) -> Bool {
        guard let generation else { return true }
        return isDataGenerationCurrent(generation)
    }

    private func normalizationContextText(for event: ExtractedEvent, sourceMessage: ChatMessage) -> String {
        let metadataText = event.metadata.flatMap { entry in
            [
                entry.key,
                entry.stringValue,
                entry.unit,
                entry.sourceText
            ].compactMap(\.self)
        }
        return ([sourceMessage.text, event.title, event.rawText, event.note, event.eventType].compactMap(\.self) + metadataText)
            .joined(separator: " ")
    }

    private func resolvedExtractionDate(
        _ value: String,
        sourceMessage: ChatMessage,
        contextText: String
    ) -> Date? {
        guard let parsedDate = ExtractionService.parseDate(value) else { return nil }
        let calendar = Calendar.current
        guard !DateFormatting.containsExplicitTemporalCue(contextText) else {
            return parsedDate
        }
        guard calendar.startOfDay(for: parsedDate) != calendar.startOfDay(for: sourceMessage.createdAt) else {
            return parsedDate
        }
        return DateFormatting.normalizedDateOnly(sourceMessage.createdAt, calendar: calendar)
    }
}
