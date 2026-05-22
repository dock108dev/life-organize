import SwiftData
import XCTest
@testable import LifeOrganize

@MainActor
final class WorkContinuityScenarioTests: XCTestCase {
    func testWorkContinuitySecurityMigrationAliasesTraversalCorrectionRecallAndExportStayLocal() throws {
        let container = ModelContainerFactory.make(configuration: .inMemory)
        try SeedScenarioLoader.load(["work_continuity"], into: container, isAutomationRuntime: true)

        let context = ModelContext(container)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        let events = try context.fetch(FetchDescriptor<LedgerEvent>())
        let rules = try context.fetch(FetchDescriptor<LedgerRule>())
        let notes = try context.fetch(FetchDescriptor<LedgerNote>())
        let links = try context.fetch(FetchDescriptor<EntityLink>())

        let message = try XCTUnwrap(messages.first)
        let canonical = try thing(named: "Nimbus Web Services", in: things)
        let shorthand = try thing(named: "NWS", in: things)
        let cloudFunctions = try thing(named: "Aster Cloud Functions", in: things)
        let migration = try thing(named: "Monorepo Migration", in: things)
        let scanner = try thing(named: "SignalScan", in: things)
        let vulnerabilities = try thing(named: "Vulnerabilities", in: things)
        let migrationRule = try rule(titled: "Prepare monorepo migration", in: rules)
        let scannerNote = try note(containing: "quality gate", in: notes)
        let securityEvent = try event(titled: "Security review", in: events)
        let vulnerabilityEvent = try event(titled: "Reviewed vulnerability backlog", in: events)

        XCTAssertEqual(cloudFunctions.aliases, ["ACF", "cloud functions", "functions runtime"])
        XCTAssertEqual(scanner.aliases, ["scanner", "static scan", "quality gate"])
        XCTAssertEqual(vulnerabilities.aliases, ["security issues", "findings"])
        XCTAssertEqual(migration.aliases, ["migration", "repo move"])
        XCTAssertEqual(shorthand.sourceMessageIDs, [message.id])

        assertNormalizationPolicy(
            message: message,
            canonical: canonical,
            cloudFunctions: cloudFunctions,
            scanner: scanner,
            vulnerabilities: vulnerabilities
        )

        let records = RelationshipTraversalRecords(
            messages: messages,
            things: things,
            events: events,
            rules: rules,
            notes: notes,
            entityLinks: links
        )
        let results = RelationshipTraversalService().relatedRecords(
            for: .rule(migrationRule.id),
            in: records,
            allowedTargetTypes: [.thing, .event, .note]
        )
        let orderedTargets = results
            .filter {
                [
                    RelationshipNode.thing(migration.id),
                    .note(scannerNote.id),
                    .event(vulnerabilityEvent.id),
                    .thing(cloudFunctions.id),
                    .thing(scanner.id),
                    .thing(vulnerabilities.id),
                ].contains($0.target)
            }
            .map { "\($0.source.rawValue):\(records.title(for: $0.target))" }
        XCTAssertEqual(orderedTargets, [
            "linkedThing:Monorepo Migration",
            "sameMessage:SignalScan quality gate flagged Aster Cloud Functions findings before the monorepo move.",
            "sharedSourceMessage:Reviewed vulnerability backlog",
            "sharedSourceMessage:Vulnerabilities",
            "sharedSourceMessage:Aster Cloud Functions",
            "sharedSourceMessage:SignalScan",
        ])

        let relationshipAudit = auditLines(for: results, records: records)
        XCTAssertTrue(relationshipAudit.contains("linkedThing|thing|Monorepo Migration|\(message.id.uuidString)"))
        XCTAssertTrue(relationshipAudit.contains("sameMessage|note|SignalScan quality gate flagged Aster Cloud Functions findings before the monorepo move.|\(message.id.uuidString)"))
        XCTAssertTrue(relationshipAudit.contains("sharedSourceMessage|event|Reviewed vulnerability backlog|\(message.id.uuidString)"))
        XCTAssertTrue(relationshipAudit.contains("sharedSourceMessage|thing|Aster Cloud Functions|\(message.id.uuidString)"))
        XCTAssertTrue(relationshipAudit.contains("sharedSourceMessage|thing|SignalScan|\(message.id.uuidString)"))
        XCTAssertTrue(relationshipAudit.contains("sharedSourceMessage|thing|Vulnerabilities|\(message.id.uuidString)"))

        let exportBeforeCorrection = try export(context: context).records
        XCTAssertEqual(exportBeforeCorrection.chatMessages.first?.linkedEntityIds.contains(migrationRule.id.uuidString), true)
        XCTAssertEqual(exportBeforeCorrection.events.first { $0.id == vulnerabilityEvent.id.uuidString }?.thingId, vulnerabilities.id.uuidString)
        XCTAssertEqual(exportBeforeCorrection.rules.first { $0.id == migrationRule.id.uuidString }?.thingId, migration.id.uuidString)
        XCTAssertEqual(
            exportBeforeCorrection.notes.first { $0.id == scannerNote.id.uuidString }?.linkedThingIds,
            [cloudFunctions.id.uuidString, migration.id.uuidString, scanner.id.uuidString, vulnerabilities.id.uuidString].sorted()
        )
        XCTAssertTrue(exportBeforeCorrection.entityLinks.contains {
            $0.fromEntityId == migrationRule.id.uuidString
                && $0.toEntityId == scannerNote.id.uuidString
                && $0.source.chatMessageId == message.id.uuidString
        })
        XCTAssertTrue(exportBeforeCorrection.ledgerReviewItems.contains {
            $0.targetId == shorthand.id.uuidString
                && $0.evidence.contains { $0.sourceId == canonical.id.uuidString }
                && $0.evidence.contains { $0.sourceId == shorthand.id.uuidString }
        })

        let reviewItem = try XCTUnwrap(try context.fetch(FetchDescriptor<LedgerReviewItem>()).first)
        let queue = LedgerReviewQueueService(
            modelContext: context,
            apiKeyStore: InMemoryAPIKeyStore(key: "test-key"),
            dateProvider: TestDateProvider(now: fixedTestNow)
        )
        let entry = try queue.entry(for: reviewItem)
        XCTAssertEqual(entry.correctionClass, .reassignRecordsToThing)
        XCTAssertEqual(entry.primaryActionTitle, "Review Thing")
        try queue.reassignRecords(from: reviewItem, to: canonical.id)

        XCTAssertEqual(securityEvent.thing?.id, canonical.id)
        XCTAssertEqual(try rule(titled: "Review NWS auth notes", in: context.fetch(FetchDescriptor<LedgerRule>())).thing?.id, canonical.id)
        XCTAssertEqual(try note(containing: "Nimbus Web Services", in: context.fetch(FetchDescriptor<LedgerNote>())).linkedThingIDs, [canonical.id])
        XCTAssertEqual(reviewItem.state, .accepted)

        let correctedRecords = SearchService().records(
            things: try context.fetch(FetchDescriptor<Thing>()),
            events: try context.fetch(FetchDescriptor<LedgerEvent>()),
            rules: try context.fetch(FetchDescriptor<LedgerRule>()),
            notes: try context.fetch(FetchDescriptor<LedgerNote>()),
            messages: messages
        )
        XCTAssertTrue(SearchService().search("security", in: correctedRecords).contains {
            $0.navigationTarget == .eventDetail(securityEvent.id) && $0.linkedThingName == "Nimbus Web Services"
        })
        let recallAnswer = try ChatRecallResponseService(modelContext: context, now: fixedTestNow).answer(
            for: ChatIntentClassification(intent: .localSearch, targetText: "security")
        )
        XCTAssertTrue(recallAnswer.contains("Local results:"))
        XCTAssertTrue(recallAnswer.contains("Security review"))
        XCTAssertTrue(recallAnswer.contains("Nimbus Web Services"))
        assertNoLeakedPrimarySurfaceTerms([entry.title, entry.detail, recallAnswer] + relationshipAudit)

        let exportAfterCorrection = try export(context: context).records
        XCTAssertEqual(exportAfterCorrection.events.first { $0.id == securityEvent.id.uuidString }?.thingId, canonical.id.uuidString)
        XCTAssertEqual(exportAfterCorrection.rules.first { $0.title == "Review NWS auth notes" }?.thingId, canonical.id.uuidString)
        XCTAssertEqual(exportAfterCorrection.notes.first { $0.text.contains("Nimbus Web Services") }?.linkedThingIds, [canonical.id.uuidString])
    }

    private func assertNormalizationPolicy(
        message: ChatMessage,
        canonical: Thing,
        cloudFunctions: Thing,
        scanner: Thing,
        vulnerabilities: Thing
    ) {
        let acronymCandidate = ThingNormalizer.candidates(
            for: "NWS",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [canonical],
            modelConfidence: 0.86
        ).first
        XCTAssertEqual(acronymCandidate?.targetThingID, canonical.id)
        XCTAssertEqual(acronymCandidate?.matchReason, .acronymVariant)
        XCTAssertEqual(acronymCandidate?.sourceEvidence.first?.categoryEvidence?.primaryCategory, .work)
        XCTAssertEqual(acronymCandidate?.allowsAutomaticMerge, false)

        let abbreviationCandidate = ThingNormalizer.candidates(
            for: "vulns",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [vulnerabilities],
            modelConfidence: 0.7
        ).first
        XCTAssertEqual(abbreviationCandidate?.targetThingID, vulnerabilities.id)
        XCTAssertEqual(abbreviationCandidate?.matchReason, .abbreviationVariant)
        XCTAssertEqual(abbreviationCandidate?.allowsAutomaticMerge, false)

        let scannerAliasCandidate = ThingNormalizer.candidates(
            for: "quality gate",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [scanner],
            modelConfidence: 0.78
        ).first
        XCTAssertEqual(scannerAliasCandidate?.targetThingID, scanner.id)
        XCTAssertEqual(scannerAliasCandidate?.matchReason, .learnedAlias)
        XCTAssertEqual(scannerAliasCandidate?.allowsAutomaticMerge, true)

        let cloudAliasCandidate = ThingNormalizer.candidates(
            for: "cloud functions",
            categoryHint: "work",
            contextText: message.text,
            existingThings: [cloudFunctions],
            modelConfidence: 0.82
        ).first
        XCTAssertEqual(cloudAliasCandidate?.targetThingID, cloudFunctions.id)
        XCTAssertEqual(cloudAliasCandidate?.matchReason, .learnedAlias)
        XCTAssertEqual(cloudAliasCandidate?.allowsAutomaticMerge, true)
    }

    private func thing(named name: String, in things: [Thing]) throws -> Thing {
        try XCTUnwrap(things.first { $0.name == name })
    }

    private func event(titled title: String, in events: [LedgerEvent]) throws -> LedgerEvent {
        try XCTUnwrap(events.first { $0.title == title })
    }

    private func rule(titled title: String, in rules: [LedgerRule]) throws -> LedgerRule {
        try XCTUnwrap(rules.first { $0.title == title })
    }

    private func note(containing text: String, in notes: [LedgerNote]) throws -> LedgerNote {
        try XCTUnwrap(notes.first { $0.text.contains(text) })
    }

    private func auditLines(
        for results: [RelationshipTraversalResult],
        records: RelationshipTraversalRecords
    ) -> [String] {
        results.map {
            "\($0.source.rawValue)|\($0.target.type.rawValue)|\(records.title(for: $0.target))|\($0.sourceMessageID?.uuidString ?? "")"
        }
    }

    private func export(context: ModelContext) throws -> LedgerExportEnvelope {
        try LocalJSONExportService(
            modelContext: context,
            now: { fixedTestNow },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "America/New_York")!
        ).envelope()
    }

    private func assertNoLeakedPrimarySurfaceTerms(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        let combined = values.joined(separator: "\n").lowercased()
        for term in ["dashboard", "chart", "ai-powered", "advice", "coaching", "internal extraction", "confidence"] {
            XCTAssertFalse(combined.contains(term), "Leaked term: \(term)\n\(combined)", file: file, line: line)
        }
    }
}
