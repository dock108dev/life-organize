import SwiftData
import XCTest
@testable import LifeOrganize

final class DerivedFieldMaintenanceTests: XCTestCase {
    @MainActor
    func testEventDateChangesRefreshThingLastEventFromOccurredAt() throws {
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Oil Change")
        let createdLater = Date(timeIntervalSince1970: 300)
        let occurredEarlier = Date(timeIntervalSince1970: 100)
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: occurredEarlier,
            rawText: "Changed oil last month.",
            createdAt: createdLater,
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context)

        context.insert(thing)
        try service.insertEvent(event)

        XCTAssertEqual(thing.eventCount, 1)
        XCTAssertEqual(thing.lastEventAt, occurredEarlier)

        event.occurredAt = Date(timeIntervalSince1970: 500)
        try service.updateEvent(event, previousThing: thing)

        XCTAssertEqual(thing.eventCount, 1)
        XCTAssertEqual(thing.lastEventAt, Date(timeIntervalSince1970: 500))
    }

    @MainActor
    func testEventDeletionRefreshesThingCountAndLastEvent() throws {
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Home Air Filters")
        let olderEvent = LedgerEvent(
            title: "Bought filters",
            occurredAt: Date(timeIntervalSince1970: 100),
            rawText: "Bought filters.",
            thing: thing
        )
        let newerEvent = LedgerEvent(
            title: "Replaced filters",
            occurredAt: Date(timeIntervalSince1970: 200),
            rawText: "Replaced filters.",
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context)

        context.insert(thing)
        try service.insertEvent(olderEvent)
        try service.insertEvent(newerEvent)
        try service.deleteEvent(newerEvent)

        XCTAssertEqual(thing.eventCount, 1)
        XCTAssertEqual(thing.lastEventAt, Date(timeIntervalSince1970: 100))
    }

    @MainActor
    func testEventThingReassignmentRefreshesOldAndNewThings() throws {
        let context = makeInMemoryModelContext()
        let oldThing = Thing(name: "Oil Change")
        let newThing = Thing(name: "Car Maintenance")
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 100),
            rawText: "Changed oil.",
            thing: oldThing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context)

        context.insert(oldThing)
        context.insert(newThing)
        try service.insertEvent(event)

        event.thing = newThing
        try service.updateEvent(event, previousThing: oldThing)

        XCTAssertEqual(oldThing.eventCount, 0)
        XCTAssertNil(oldThing.lastEventAt)
        XCTAssertEqual(newThing.eventCount, 1)
        XCTAssertEqual(newThing.lastEventAt, Date(timeIntervalSince1970: 100))
    }

    @MainActor
    func testEventThingUnlinkKeepsEventAndRefreshesThingCache() throws {
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Car")
        let event = LedgerEvent(
            title: "Logged mileage",
            occurredAt: Date(timeIntervalSince1970: 100),
            rawText: "Logged mileage.",
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context)

        context.insert(thing)
        try service.insertEvent(event)
        try service.unlinkEventFromThing(event)
        try context.save()

        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        XCTAssertEqual(events.map(\.id), [event.id])
        XCTAssertNil(events.first?.thing)
        XCTAssertEqual(thing.eventCount, 0)
        XCTAssertNil(thing.lastEventAt)
    }

    @MainActor
    func testRecordReassignmentUpdatesThingLinksAndDerivedFields() throws {
        let now = Date(timeIntervalSince1970: 500)
        let context = makeInMemoryModelContext()
        let source = Thing(name: "NWS")
        let target = Thing(name: "Nimbus Web Services")
        let message = ChatMessage(role: .user, text: "NWS deploy.", createdAt: now)
        let event = LedgerEvent(title: "Deploy", occurredAt: now, rawText: "Deploy", thing: source, sourceMessage: message)
        let rule = LedgerRule(title: "Check deploy", ruleType: .reminder, startsAt: now, thing: source, sourceMessage: message)
        let note = LedgerNote(text: "Deploy notes", sourceMessage: message, linkedThings: [source])
        let links = [
            EntityLink(sourceType: .event, sourceID: event.id, targetType: .thing, targetID: source.id, relation: .primaryThing, createdBy: .extraction, sourceMessageID: message.id),
            EntityLink(sourceType: .rule, sourceID: rule.id, targetType: .thing, targetID: source.id, relation: .primaryThing, createdBy: .extraction, sourceMessageID: message.id),
            EntityLink(sourceType: .note, sourceID: note.id, targetType: .thing, targetID: source.id, relation: .aboutThing, createdBy: .extraction, sourceMessageID: message.id)
        ]
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(source)
        context.insert(target)
        context.insert(message)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        links.forEach(context.insert)

        try service.reassignEvent(event, to: target)
        try service.reassignRule(rule, to: target)
        try service.reassignNote(note, to: target)
        try context.save()

        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(source.eventCount, 0)
        XCTAssertEqual(target.eventCount, 1)
        XCTAssertEqual(target.lastEventAt, now)
        let savedLinks = try context.fetch(FetchDescriptor<EntityLink>())
        XCTAssertFalse(savedLinks.contains { $0.targetID == source.id })
        XCTAssertTrue(savedLinks.contains { $0.sourceType == .event && $0.targetID == target.id && $0.createdBy == .user })
        XCTAssertTrue(savedLinks.contains { $0.sourceType == .rule && $0.targetID == target.id && $0.createdBy == .user })
        XCTAssertTrue(savedLinks.contains { $0.sourceType == .note && $0.targetID == target.id && $0.createdBy == .user })
    }

    @MainActor
    func testMergeThingPreservesEvidenceAndCleansStaleLinks() throws {
        let now = Date(timeIntervalSince1970: 600)
        let context = makeInMemoryModelContext()
        let targetMessageID = UUID()
        let sourceMessageID = UUID()
        let targetAttemptID = UUID()
        let sourceAttemptID = UUID()
        let target = Thing(
            name: "Nimbus Web Services",
            aliases: ["NWS"],
            category: .other,
            sourceMessageIDs: [targetMessageID],
            sourceExtractionAttemptIDs: [targetAttemptID]
        )
        let source = Thing(
            name: "NWS",
            details: "Production deploys",
            aliases: ["Nimbus"],
            category: .work,
            sourceMessageIDs: [sourceMessageID],
            sourceExtractionAttemptIDs: [sourceAttemptID]
        )
        let message = ChatMessage(role: .user, text: "NWS deploy completed.", createdAt: now)
        let event = LedgerEvent(title: "Deploy completed", occurredAt: now, rawText: "Deploy", thing: source, sourceMessage: message)
        let rule = LedgerRule(title: "Review deploy", ruleType: .reminder, startsAt: now, thing: source, sourceMessage: message)
        let note = LedgerNote(text: "Watch rollout", sourceMessage: message, linkedThings: [source])
        let links = [
            EntityLink(sourceType: .chatMessage, sourceID: message.id, targetType: .thing, targetID: source.id, relation: .mentionsThing, createdBy: .extraction, sourceMessageID: message.id),
            EntityLink(sourceType: .event, sourceID: event.id, targetType: .thing, targetID: source.id, relation: .primaryThing, createdBy: .extraction, sourceMessageID: message.id),
            EntityLink(sourceType: .rule, sourceID: rule.id, targetType: .thing, targetID: source.id, relation: .primaryThing, createdBy: .extraction, sourceMessageID: message.id),
            EntityLink(sourceType: .note, sourceID: note.id, targetType: .thing, targetID: source.id, relation: .aboutThing, createdBy: .extraction, sourceMessageID: message.id)
        ]
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(target)
        context.insert(source)
        context.insert(message)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        links.forEach(context.insert)

        try service.mergeThing(source, into: target)
        try context.save()

        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(target.aliases, ["NWS", "Nimbus"])
        XCTAssertEqual(target.category, .work)
        XCTAssertEqual(target.details, "Production deploys")
        XCTAssertEqual(Set(target.sourceMessageIDs), Set([targetMessageID, sourceMessageID]))
        XCTAssertEqual(Set(target.sourceExtractionAttemptIDs), Set([targetAttemptID, sourceAttemptID]))
        XCTAssertEqual(target.eventCount, 1)
        XCTAssertEqual(target.lastEventAt, now)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
        XCTAssertFalse(try context.fetch(FetchDescriptor<EntityLink>()).contains { $0.sourceID == source.id || $0.targetID == source.id })
    }

    @MainActor
    func testDeleteThingCanReassignRecordsAndRemoveStaleLinks() throws {
        let now = Date(timeIntervalSince1970: 700)
        let context = makeInMemoryModelContext()
        let source = Thing(name: "AWS")
        let target = Thing(name: "Cloud Infrastructure")
        let event = LedgerEvent(title: "Deployed service", occurredAt: now, rawText: "Deploy", thing: source)
        let rule = LedgerRule(title: "Review service", ruleType: .reminder, startsAt: now, thing: source)
        let note = LedgerNote(text: "Service details", linkedThings: [source])
        let mention = EntityLink(sourceType: .chatMessage, sourceID: UUID(), targetType: .thing, targetID: source.id, relation: .mentionsThing, createdBy: .extraction)
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(source)
        context.insert(target)
        context.insert(event)
        context.insert(rule)
        context.insert(note)
        context.insert(mention)

        try service.deleteThing(source, reassigningRecordsTo: target)
        try context.save()

        XCTAssertEqual(event.thing?.id, target.id)
        XCTAssertEqual(rule.thing?.id, target.id)
        XCTAssertEqual(note.linkedThingIDs, [target.id])
        XCTAssertEqual(target.eventCount, 1)
        XCTAssertEqual(target.lastEventAt, now)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Thing>()).contains { $0.id == source.id })
        XCTAssertFalse(try context.fetch(FetchDescriptor<EntityLink>()).contains { $0.sourceID == source.id || $0.targetID == source.id })
    }

    @MainActor
    func testRepairClearsNoEventThingCaches() throws {
        let context = makeInMemoryModelContext()
        let thing = Thing(
            name: "Domains",
            eventCount: 4,
            lastEventAt: Date(timeIntervalSince1970: 100)
        )
        let service = DerivedFieldMaintenanceService(modelContext: context)

        context.insert(thing)
        try service.repairAll()

        XCTAssertEqual(thing.eventCount, 0)
        XCTAssertNil(thing.lastEventAt)
    }

    @MainActor
    func testRuleRefreshHandlesNoExpirationExpiredAndManualDeactivation() throws {
        let now = Date(timeIntervalSince1970: 200)
        let context = makeInMemoryModelContext()
        let activeRule = LedgerRule(
            title: "No domains",
            startsAt: Date(timeIntervalSince1970: 100),
            expiresAt: nil,
            isActive: false
        )
        let expiredRule = LedgerRule(
            title: "No monitors",
            startsAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200),
            isActive: true
        )
        let deactivatedRule = LedgerRule(
            title: "No apps",
            startsAt: Date(timeIntervalSince1970: 100),
            expiresAt: nil,
            isActive: true,
            manuallyDeactivatedAt: Date(timeIntervalSince1970: 150)
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(activeRule)
        context.insert(expiredRule)
        context.insert(deactivatedRule)
        try service.repairAll()

        XCTAssertTrue(activeRule.isActive)
        XCTAssertEqual(activeRule.lifecycleState, .open)
        XCTAssertFalse(expiredRule.isActive)
        XCTAssertEqual(expiredRule.status, .expired)
        XCTAssertFalse(deactivatedRule.isActive)
        XCTAssertEqual(deactivatedRule.status, .inactive)
        XCTAssertEqual(deactivatedRule.lifecycleState, .deactivated)
    }

    @MainActor
    func testRuleExtensionRefreshesCachedActiveState() throws {
        let now = Date(timeIntervalSince1970: 200)
        let context = makeInMemoryModelContext()
        let rule = LedgerRule(
            title: "No domains",
            startsAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 150),
            isActive: true
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(rule)
        try service.updateRule(rule)
        XCTAssertFalse(rule.isActive)

        rule.expiresAt = Date(timeIntervalSince1970: 300)
        try service.updateRule(rule)
        XCTAssertTrue(rule.isActive)
    }

    @MainActor
    func testRuleDeletionUpdatesLinkedThingAndRemovesRule() throws {
        let now = Date(timeIntervalSince1970: 200)
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Domains", updatedAt: Date(timeIntervalSince1970: 50))
        let rule = LedgerRule(
            title: "No domains",
            startsAt: Date(timeIntervalSince1970: 100),
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(thing)
        try service.insertRule(rule)
        try service.deleteRule(rule)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        XCTAssertTrue(rules.isEmpty)
        XCTAssertEqual(thing.updatedAt, now)
    }

    @MainActor
    func testRuleDeactivationRecordsLifecycleAndUpdatesLinkedThing() throws {
        let now = Date(timeIntervalSince1970: 200)
        let context = makeInMemoryModelContext()
        let thing = Thing(name: "Rent", updatedAt: Date(timeIntervalSince1970: 50))
        let rule = LedgerRule(
            title: "Pay rent",
            ruleType: .reminder,
            startsAt: Date(timeIntervalSince1970: 100),
            thing: thing
        )
        let service = DerivedFieldMaintenanceService(modelContext: context, now: { now })

        context.insert(thing)
        try service.insertRule(rule)
        service.deactivateRule(rule, at: now)

        XCTAssertFalse(rule.isActive)
        XCTAssertEqual(rule.lifecycleState, .deactivated)
        XCTAssertEqual(rule.manuallyDeactivatedAt, now)
        XCTAssertEqual(rule.updatedAt, now)
        XCTAssertEqual(thing.updatedAt, now)
    }

    @MainActor
    func testThingAliasMaintenanceDeduplicatesAndUpdatesNormalizedKey() {
        let updatedAt = Date(timeIntervalSince1970: 400)
        let thing = Thing(name: "Air Filters", aliases: ["HVAC"])

        thing.name = "Hallway Filter"
        DerivedFieldMaintenanceService.updateThingFields(
            thing,
            aliases: ["air filter", " Air Filter ", "Hallway Filter", ""],
            updatedAt: updatedAt
        )

        XCTAssertEqual(thing.normalizedKey, "hallway filter")
        XCTAssertEqual(thing.aliases, ["air filter"])
        XCTAssertEqual(thing.updatedAt, updatedAt)
    }

    func testDateOnlyNormalizationUsesLocalNoon() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = Date(timeIntervalSince1970: 1_779_043_400)

        let normalized = DateFormatting.normalizedDateOnly(date, calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute, .second], from: normalized)

        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }
}
