import Foundation
import SwiftData

@MainActor
struct DerivedFieldMaintenanceService {
    let modelContext: ModelContext
    var now: () -> Date = Date.init
    private let ruleStatusService = RuleStatusService()

    func refreshThing(_ thing: Thing) throws {
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
            .filter { $0.thing?.id == thing.id }

        thing.eventCount = events.count
        thing.lastEventAt = events.map(\.occurredAt).max()
    }

    func refreshThings(_ things: [Thing]) throws {
        var refreshedIDs = Set<UUID>()
        for thing in things where refreshedIDs.insert(thing.id).inserted {
            try refreshThing(thing)
        }
    }

    func refreshEventMutation(previousThing: Thing?, currentThing: Thing?) throws {
        try refreshThings([previousThing, currentThing].compactMap { $0 })
    }

    func insertEvent(_ event: LedgerEvent) throws {
        modelContext.insert(event)
        try syncEventThingLink(event)
        try refreshEventMutation(previousThing: nil, currentThing: event.thing)
    }

    func updateEvent(_ event: LedgerEvent, previousThing: Thing?) throws {
        try syncEventThingLink(event)
        try refreshEventMutation(previousThing: previousThing, currentThing: event.thing)
    }

    func unlinkEventFromThing(_ event: LedgerEvent) throws {
        let previousThing = event.thing
        event.thing = nil
        event.updatedAt = now()
        try syncEventThingLink(event)
        try refreshEventMutation(previousThing: previousThing, currentThing: nil)
    }

    func reassignEvent(_ event: LedgerEvent, to thing: Thing?) throws {
        let previousThing = event.thing
        guard previousThing?.id != thing?.id else { return }
        event.thing = thing
        event.updatedAt = now()
        try syncEventThingLink(event)
        try refreshEventMutation(previousThing: previousThing, currentThing: thing)
    }

    func deleteEvent(_ event: LedgerEvent) throws {
        let previousThing = event.thing
        event.thing = nil
        try deleteLinks(touching: .event, id: event.id)
        try removeReviewReferences(to: .event, id: event.id)
        modelContext.delete(event)
        try refreshEventMutation(previousThing: previousThing, currentThing: nil)
    }

    func refreshRule(_ rule: LedgerRule) {
        rule.isActive = ruleStatusService.isActive(rule, at: now())
    }

    func refreshRules(_ rules: [LedgerRule]) {
        rules.forEach(refreshRule)
    }

    func insertRule(_ rule: LedgerRule) throws {
        refreshRule(rule)
        modelContext.insert(rule)
        rule.thing?.updatedAt = now()
        try syncRuleThingLink(rule)
    }

    func updateRule(_ rule: LedgerRule, previousThing: Thing? = nil) throws {
        refreshRule(rule)
        rule.thing?.updatedAt = now()
        if previousThing?.id != rule.thing?.id {
            previousThing?.updatedAt = now()
        }
        try syncRuleThingLink(rule)
    }

    func reassignRule(_ rule: LedgerRule, to thing: Thing?) throws {
        let previousThing = rule.thing
        guard previousThing?.id != thing?.id else { return }
        rule.thing = thing
        rule.updatedAt = now()
        try updateRule(rule, previousThing: previousThing)
    }

    func insertNote(_ note: LedgerNote) throws {
        modelContext.insert(note)
        try syncNoteThingLinks(note)
        touchThings(note.linkedThings)
    }

    func updateNote(_ note: LedgerNote, previousThings: [Thing] = []) throws {
        try syncNoteThingLinks(note)
        touchThings(previousThings + note.linkedThings)
    }

    func reassignNote(_ note: LedgerNote, to thing: Thing?) throws {
        let previousThings = note.linkedThings
        note.linkedThings = thing.map { [$0] } ?? []
        note.updatedAt = now()
        try updateNote(note, previousThings: previousThings)
    }

    func replaceThing(_ source: Thing, with target: Thing, in note: LedgerNote) throws {
        guard source.id != target.id, note.linkedThings.contains(where: { $0.id == source.id }) else { return }
        let previousThings = note.linkedThings
        note.linkedThings.removeAll { $0.id == source.id }
        if !note.linkedThings.contains(where: { $0.id == target.id }) {
            note.linkedThings.append(target)
        }
        note.updatedAt = now()
        try updateNote(note, previousThings: previousThings)
    }

    func deleteNote(_ note: LedgerNote) throws {
        let previousThings = note.linkedThings
        note.linkedThings = []
        try deleteLinks(touching: .note, id: note.id)
        try removeReviewReferences(to: .none, id: note.id)
        modelContext.delete(note)
        touchThings(previousThings)
    }

    func mergeThing(_ source: Thing, into target: Thing) throws {
        guard source.id != target.id else { return }
        let mergeDate = now()
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
            .filter { $0.thing?.id == source.id }
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
            .filter { $0.thing?.id == source.id }
        let notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())
            .filter { note in note.linkedThings.contains { $0.id == source.id } }

        for event in events {
            try reassignEvent(event, to: target)
        }
        for rule in rules {
            try reassignRule(rule, to: target)
        }
        for note in notes {
            try replaceThing(source, with: target, in: note)
        }

        target.registerAliases([source.name] + source.aliases, updatedAt: mergeDate)
        target.sourceMessageIDs = mergedIDs(target.sourceMessageIDs, source.sourceMessageIDs)
        target.sourceExtractionAttemptIDs = mergedIDs(target.sourceExtractionAttemptIDs, source.sourceExtractionAttemptIDs)
        if target.details.isEmpty {
            target.details = source.details
        } else if !source.details.isEmpty, !target.details.localizedCaseInsensitiveContains(source.details) {
            target.details = [target.details, source.details].joined(separator: "\n")
        }
        if target.category == nil || target.category == .other {
            target.category = source.category
        }
        target.updatedAt = mergeDate
        try retargetExtractionAttemptCreatedThingIDs(from: source.id, to: target.id)
        try retargetThingLinks(from: source, to: target)
        try retargetReviewReferences(to: .thing, from: source.id, to: target.id)
        modelContext.delete(source)
        try refreshThing(target)
    }

    func deactivateRule(_ rule: LedgerRule, at date: Date? = nil) {
        let deactivatedAt = date ?? now()
        rule.manuallyDeactivatedAt = deactivatedAt
        rule.lifecycleStateRawValue = LedgerRuleLifecycleState.deactivated.rawValue
        rule.updatedAt = deactivatedAt
        refreshRule(rule)
        rule.thing?.updatedAt = deactivatedAt
    }

    func deleteRule(_ rule: LedgerRule) throws {
        let previousThing = rule.thing
        rule.thing = nil
        try deleteLinks(touching: .rule, id: rule.id)
        try removeReviewReferences(to: .rule, id: rule.id)
        modelContext.delete(rule)
        previousThing?.updatedAt = now()
    }

    func deleteThing(_ thing: Thing, reassigningRecordsTo target: Thing? = nil) throws {
        guard target?.id != thing.id else { return }
        let events = try modelContext.fetch(FetchDescriptor<LedgerEvent>())
            .filter { $0.thing?.id == thing.id }
        let rules = try modelContext.fetch(FetchDescriptor<LedgerRule>())
            .filter { $0.thing?.id == thing.id }
        let notes = try modelContext.fetch(FetchDescriptor<LedgerNote>())
            .filter { note in note.linkedThings.contains { $0.id == thing.id } }

        for event in events {
            try reassignEvent(event, to: target)
        }
        for rule in rules {
            try reassignRule(rule, to: target)
        }
        for note in notes {
            if let target {
                try replaceThing(thing, with: target, in: note)
            } else {
                let previousThings = note.linkedThings
                note.linkedThings.removeAll { $0.id == thing.id }
                note.updatedAt = now()
                try updateNote(note, previousThings: previousThings)
            }
        }

        if let target {
            try retargetExtractionAttemptCreatedThingIDs(from: thing.id, to: target.id)
            try retargetThingLinks(from: thing, to: target)
            try retargetReviewReferences(to: .thing, from: thing.id, to: target.id)
            try refreshThing(target)
        } else {
            try retargetExtractionAttemptCreatedThingIDs(from: thing.id, to: nil)
            try deleteLinks(touching: .thing, id: thing.id)
            try removeReviewReferences(to: .thing, id: thing.id)
        }
        modelContext.delete(thing)
    }

    func repairAll() throws {
        try refreshThings(modelContext.fetch(FetchDescriptor<Thing>()))
        refreshRules(try modelContext.fetch(FetchDescriptor<LedgerRule>()))
        try modelContext.save()
    }

    static func normalizedAliases(_ aliases: [String], excludingName name: String) -> [String] {
        ThingAliasPolicy.cleanedAliases(aliases, excludingName: name)
    }

    static func updateThingFields(_ thing: Thing, aliases: [String], updatedAt: Date = Date()) {
        thing.normalizedKey = ThingNormalizer.normalizeKey(thing.name)
        thing.aliases = normalizedAliases(aliases, excludingName: thing.name)
        thing.updatedAt = updatedAt
    }

    private func mergedIDs(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return (lhs + rhs).filter { seen.insert($0).inserted }
    }

    private func touchThings(_ things: [Thing]) {
        var touchedIDs = Set<UUID>()
        for thing in things where touchedIDs.insert(thing.id).inserted {
            thing.updatedAt = now()
        }
    }

    private func syncEventThingLink(_ event: LedgerEvent) throws {
        try syncThingLink(
            sourceType: .event,
            sourceID: event.id,
            relation: .primaryThing,
            thing: event.thing,
            sourceMessageID: event.sourceMessageID
        )
    }

    private func syncRuleThingLink(_ rule: LedgerRule) throws {
        try syncThingLink(
            sourceType: .rule,
            sourceID: rule.id,
            relation: .primaryThing,
            thing: rule.thing,
            sourceMessageID: rule.sourceMessageID
        )
    }

    private func syncNoteThingLinks(_ note: LedgerNote) throws {
        let targetIDs = Set(note.linkedThings.map(\.id))
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        var keptTargetIDs = Set<UUID>()
        for link in links where link.sourceType == .note && link.sourceID == note.id && link.relation == .aboutThing && link.targetType == .thing {
            if targetIDs.contains(link.targetID), keptTargetIDs.insert(link.targetID).inserted {
                link.createdBy = .user
                link.sourceMessageID = link.sourceMessageID ?? note.sourceMessageID
            } else {
                modelContext.delete(link)
            }
        }
        for thing in note.linkedThings where !keptTargetIDs.contains(thing.id) {
            insertUserThingLink(
                sourceType: .note,
                sourceID: note.id,
                targetID: thing.id,
                relation: .aboutThing,
                sourceMessageID: note.sourceMessageID
            )
        }
    }

    private func syncThingLink(
        sourceType: EntityLinkType,
        sourceID: UUID,
        relation: EntityLinkRelation,
        thing: Thing?,
        sourceMessageID: UUID?
    ) throws {
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        var keptCurrent = false
        for link in links where link.sourceType == sourceType && link.sourceID == sourceID && link.relation == relation && link.targetType == .thing {
            if link.targetID == thing?.id, !keptCurrent {
                link.createdBy = .user
                link.sourceMessageID = link.sourceMessageID ?? sourceMessageID
                keptCurrent = true
            } else {
                modelContext.delete(link)
            }
        }
        if let thing, !keptCurrent {
            insertUserThingLink(
                sourceType: sourceType,
                sourceID: sourceID,
                targetID: thing.id,
                relation: relation,
                sourceMessageID: sourceMessageID
            )
        }
    }

    private func insertUserThingLink(
        sourceType: EntityLinkType,
        sourceID: UUID,
        targetID: UUID,
        relation: EntityLinkRelation,
        sourceMessageID: UUID?
    ) {
        modelContext.insert(
            EntityLink(
                sourceType: sourceType,
                sourceID: sourceID,
                targetType: .thing,
                targetID: targetID,
                relation: relation,
                createdAt: now(),
                createdBy: .user,
                sourceMessageID: sourceMessageID
            )
        )
    }

    private func retargetThingLinks(from source: Thing, to target: Thing) throws {
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        for link in links {
            if link.sourceType == .thing, link.sourceID == source.id {
                link.sourceID = target.id
            }
            if link.targetType == .thing, link.targetID == source.id {
                link.targetID = target.id
            }
            if link.sourceType == link.targetType, link.sourceID == link.targetID {
                modelContext.delete(link)
            }
        }
        try removeDuplicateLinks()
    }

    private func retargetExtractionAttemptCreatedThingIDs(from sourceID: UUID, to targetID: UUID?) throws {
        let attempts = try modelContext.fetch(FetchDescriptor<ExtractionAttempt>())
        for attempt in attempts where attempt.createdThingIDs.contains(sourceID) {
            var ids = attempt.createdThingIDs.filter { $0 != sourceID }
            if let targetID, !ids.contains(targetID) {
                ids.append(targetID)
            }
            attempt.createdThingIDs = ids
        }
    }

    private func deleteLinks(touching type: EntityLinkType, id: UUID) throws {
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        for link in links where (link.sourceType == type && link.sourceID == id) || (link.targetType == type && link.targetID == id) {
            modelContext.delete(link)
        }
    }

    private func removeDuplicateLinks() throws {
        let links = try modelContext.fetch(FetchDescriptor<EntityLink>())
        var keptKeys = Set<String>()
        for link in links.sorted(by: linkPrecedes) {
            let key = [
                link.sourceType.rawValue,
                link.sourceID.uuidString,
                link.targetType.rawValue,
                link.targetID.uuidString,
                link.relation.rawValue
            ].joined(separator: "|")
            if !keptKeys.insert(key).inserted {
                modelContext.delete(link)
            }
        }
    }

    private func linkPrecedes(_ lhs: EntityLink, _ rhs: EntityLink) -> Bool {
        if lhs.createdBy != rhs.createdBy {
            return lhs.createdBy == .user
        }
        return lhs.createdAt < rhs.createdAt
    }
}
