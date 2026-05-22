import XCTest
@testable import LifeOrganize

@MainActor
final class RelationshipTraversalServiceTests: XCTestCase {
    func testMessageTraversalReturnsExtractedRecordsAndMentionedThingMetadata() {
        let message = ChatMessage(role: .user, text: "Changed oil and remember filters.", createdAt: Date(timeIntervalSince1970: 100))
        let thing = Thing(name: "Oil Change", createdAt: Date(timeIntervalSince1970: 110), updatedAt: Date(timeIntervalSince1970: 110))
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 400),
            rawText: message.text,
            createdAt: Date(timeIntervalSince1970: 120),
            thing: thing,
            sourceMessage: message
        )
        let rule = LedgerRule(
            title: "Replace filters",
            rawText: message.text,
            startsAt: Date(timeIntervalSince1970: 300),
            thing: thing,
            sourceMessage: message
        )
        let note = LedgerNote(
            text: "Use synthetic oil.",
            createdAt: Date(timeIntervalSince1970: 130),
            updatedAt: Date(timeIntervalSince1970: 200),
            sourceMessage: message,
            linkedThings: [thing]
        )
        let eventLink = EntityLink(
            sourceType: .chatMessage,
            sourceID: message.id,
            targetType: .event,
            targetID: event.id,
            relation: .extractedFrom,
            confidence: 0.91,
            createdBy: .extraction,
            sourceMessageID: message.id
        )
        let links = [
            eventLink,
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .rule,
                targetID: rule.id,
                relation: .extractedFrom,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .note,
                targetID: note.id,
                relation: .extractedFrom,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .thing,
                targetID: thing.id,
                relation: .mentionsThing,
                createdBy: .extraction,
                sourceMessageID: message.id
            )
        ]

        let results = RelationshipTraversalService().relatedRecords(
            for: .chatMessage(message.id),
            in: RelationshipTraversalRecords(
                messages: [message],
                things: [thing],
                events: [event],
                rules: [rule],
                notes: [note],
                entityLinks: links
            )
        )

        XCTAssertEqual(results.map(\.target), [.event(event.id), .rule(rule.id), .note(note.id), .thing(thing.id)])
        XCTAssertEqual(results.map(\.source), [.extractedRecord, .extractedRecord, .extractedRecord, .mentionedThing])
        XCTAssertEqual(results.first?.navigationTarget, .eventDetail(event.id))
        XCTAssertEqual(results.first?.sourceMessageID, message.id)
        XCTAssertEqual(results.first?.dedupeKey, "event:\(event.id.uuidString)")
        XCTAssertEqual(results.first?.confidence, 0.91)
        XCTAssertEqual(results.first?.createdBy, .extraction)
    }

    func testInverseDirectLinksSkipMissingTargets() {
        let message = ChatMessage(role: .user, text: "Changed oil.", createdAt: Date(timeIntervalSince1970: 100))
        let event = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 200),
            rawText: "Changed oil.",
            sourceMessage: message
        )
        let rule = LedgerRule(title: "Avoid oil changes twice", rawText: "Avoid oil changes twice.")
        let missingNoteID = UUID()
        let links = [
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .event,
                targetID: event.id,
                relation: .extractedFrom,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .rule,
                sourceID: rule.id,
                targetType: .event,
                targetID: event.id,
                relation: .extractedFrom,
                confidence: 0.7,
                createdBy: .system
            ),
            EntityLink(
                sourceType: .event,
                sourceID: event.id,
                targetType: .note,
                targetID: missingNoteID,
                relation: .sameMessage,
                createdBy: .system
            )
        ]

        let results = RelationshipTraversalService().relatedRecords(
            for: .event(event.id),
            in: RelationshipTraversalRecords(
                messages: [message],
                events: [event],
                rules: [rule],
                entityLinks: links
            )
        )

        XCTAssertEqual(results.map(\.target), [.rule(rule.id), .chatMessage(message.id)])
        XCTAssertEqual(results.map(\.source), [.directLink, .sourceMessage])
        XCTAssertFalse(results.contains { $0.target.id == missingNoteID })
        XCTAssertEqual(results.first?.confidence, 0.7)
        XCTAssertEqual(results.first?.createdBy, .system)
    }

    func testRuleTraversalOrdersDirectSameSourceThingAndTextMatchesWithDeduplication() {
        let message = ChatMessage(role: .user, text: "No buying domains. Bought hosting.", createdAt: Date(timeIntervalSince1970: 100))
        let domains = Thing(name: "Domains", aliases: ["domain names"])
        let rule = LedgerRule(
            title: "No buying domains",
            rawText: "No buying domains for 30 days.",
            startsAt: Date(timeIntervalSince1970: 100),
            thing: domains,
            sourceMessage: message
        )
        let directEvent = LedgerEvent(title: "Bought hosting", occurredAt: Date(timeIntervalSince1970: 500), rawText: "Bought hosting.")
        let sameMessageEvent = LedgerEvent(
            title: "Bought domain",
            occurredAt: Date(timeIntervalSince1970: 450),
            rawText: "Bought domain.",
            sourceMessage: message
        )
        let sharedSourceEvent = LedgerEvent(
            title: "Read hosting terms",
            occurredAt: Date(timeIntervalSince1970: 425),
            rawText: "Read hosting terms.",
            sourceMessage: message
        )
        let alphaSharedThingEvent = LedgerEvent(
            title: "Alpha domain renewal",
            occurredAt: Date(timeIntervalSince1970: 400),
            rawText: "Renewed alpha domain.",
            thing: domains
        )
        let zetaSharedThingEvent = LedgerEvent(
            title: "Zeta domain renewal",
            occurredAt: Date(timeIntervalSince1970: 400),
            rawText: "Renewed zeta domain.",
            thing: domains
        )
        let textOverlapEvent = LedgerEvent(
            title: "Reviewed domain ideas",
            occurredAt: Date(timeIntervalSince1970: 300),
            rawText: "Reviewed domain ideas."
        )
        let unrelatedEvent = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 600),
            rawText: "Changed oil."
        )
        let links = [
            EntityLink(
                sourceType: .event,
                sourceID: directEvent.id,
                targetType: .rule,
                targetID: rule.id,
                relation: .extractedFrom,
                createdBy: .system
            ),
            EntityLink(
                sourceType: .rule,
                sourceID: rule.id,
                targetType: .event,
                targetID: sameMessageEvent.id,
                relation: .sameMessage,
                createdBy: .system,
                sourceMessageID: message.id
            )
        ]

        let results = RelationshipTraversalService().relatedRecords(
            for: .rule(rule.id),
            in: RelationshipTraversalRecords(
                messages: [message],
                things: [domains],
                events: [
                    unrelatedEvent,
                    textOverlapEvent,
                    zetaSharedThingEvent,
                    alphaSharedThingEvent,
                    sharedSourceEvent,
                    sameMessageEvent,
                    directEvent
                ],
                rules: [rule],
                entityLinks: links
            ),
            allowedTargetTypes: [.event],
            includeTextOverlap: true
        )

        XCTAssertEqual(
            results.map(\.target),
            [
                .event(directEvent.id),
                .event(sameMessageEvent.id),
                .event(sharedSourceEvent.id),
                .event(alphaSharedThingEvent.id),
                .event(zetaSharedThingEvent.id),
                .event(textOverlapEvent.id)
            ]
        )
        XCTAssertEqual(
            results.map(\.source),
            [.directLink, .sameMessage, .sharedSourceMessage, .sharedThing, .sharedThing, .textOverlap]
        )
        XCTAssertEqual(results.map(\.sourceLabel), ["Direct link", "Same message", "Shared source", "Linked thing", "Linked thing", "Text overlap"])
        XCTAssertEqual(Set(results.map(\.dedupeKey)).count, results.count)
    }

    func testReminderTraversalSurfacesWorkSecurityContextFromSharedSource() {
        let message = ChatMessage(
            role: .user,
            text: "Prep monorepo migration with Aster Cloud Functions, SignalScan, and vulnerability cleanup.",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let monorepo = Thing(
            name: "Monorepo Migration",
            category: .work,
            sourceMessageIDs: [message.id]
        )
        let cloudFunctions = Thing(
            name: "Aster Cloud Functions",
            aliases: ["ACF"],
            category: .work,
            sourceMessageIDs: [message.id]
        )
        let scanner = Thing(
            name: "SignalScan",
            aliases: ["scanner"],
            category: .work,
            sourceMessageIDs: [message.id]
        )
        let vulnerabilities = Thing(
            name: "Vulnerabilities",
            category: .work,
            sourceMessageIDs: [message.id]
        )
        let rule = LedgerRule(
            title: "Prepare monorepo migration",
            rawText: message.text,
            startsAt: Date(timeIntervalSince1970: 200),
            thing: monorepo,
            sourceMessage: message
        )
        let note = LedgerNote(
            text: "SignalScan flagged Aster Cloud Functions vulnerability cleanup before the migration.",
            createdAt: Date(timeIntervalSince1970: 210),
            sourceMessage: message,
            linkedThings: [cloudFunctions, scanner, vulnerabilities]
        )
        let event = LedgerEvent(
            title: "Reviewed vulnerability backlog",
            occurredAt: Date(timeIntervalSince1970: 220),
            rawText: "Reviewed vulnerability backlog for the migration.",
            thing: vulnerabilities,
            sourceMessage: message
        )
        let links = [
            EntityLink(
                sourceType: .rule,
                sourceID: rule.id,
                targetType: .thing,
                targetID: monorepo.id,
                relation: .primaryThing,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .rule,
                sourceID: rule.id,
                targetType: .note,
                targetID: note.id,
                relation: .sameMessage,
                createdBy: .system,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .thing,
                targetID: cloudFunctions.id,
                relation: .mentionsThing,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .chatMessage,
                sourceID: message.id,
                targetType: .thing,
                targetID: scanner.id,
                relation: .mentionsThing,
                createdBy: .extraction,
                sourceMessageID: message.id
            ),
            EntityLink(
                sourceType: .event,
                sourceID: event.id,
                targetType: .thing,
                targetID: vulnerabilities.id,
                relation: .primaryThing,
                createdBy: .extraction,
                sourceMessageID: message.id
            )
        ]

        let results = RelationshipTraversalService().relatedRecords(
            for: .rule(rule.id),
            in: RelationshipTraversalRecords(
                messages: [message],
                things: [monorepo, cloudFunctions, scanner, vulnerabilities],
                events: [event],
                rules: [rule],
                notes: [note],
                entityLinks: links
            ),
            allowedTargetTypes: [.thing, .event, .note, .chatMessage]
        )

        XCTAssertTrue(results.contains { $0.target == .thing(monorepo.id) && $0.source == .linkedThing })
        XCTAssertTrue(results.contains { $0.target == .note(note.id) && $0.source == .sameMessage })
        XCTAssertTrue(results.contains { $0.target == .event(event.id) && $0.source == .sharedSourceMessage })
        XCTAssertTrue(results.contains { $0.target == .thing(cloudFunctions.id) && $0.source == .sharedSourceMessage })
        XCTAssertTrue(results.contains { $0.target == .thing(scanner.id) && $0.source == .sharedSourceMessage })
        XCTAssertTrue(results.contains { $0.target == .thing(vulnerabilities.id) && $0.source == .sharedSourceMessage })
    }

    func testNoRelatedContextReturnsEmptyResults() {
        let rule = LedgerRule(
            title: "Review budget",
            rawText: "Review budget.",
            startsAt: Date(timeIntervalSince1970: 100)
        )
        let unrelatedEvent = LedgerEvent(
            title: "Changed oil",
            occurredAt: Date(timeIntervalSince1970: 200),
            rawText: "Changed oil."
        )

        let results = RelationshipTraversalService().relatedRecords(
            for: .rule(rule.id),
            in: RelationshipTraversalRecords(events: [unrelatedEvent], rules: [rule]),
            allowedTargetTypes: [.event],
            includeTextOverlap: true
        )

        XCTAssertTrue(results.isEmpty)
    }
}
