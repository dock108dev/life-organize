import Foundation

struct RelationshipAuditReport: Codable, Equatable {
    let schemaVersion: Int
    let scenarioId: String
    let status: String
    let summary: RelationshipAuditSummary
    let checks: [RelationshipAuditCheckResult]
    let findings: [RelationshipAuditFinding]
}

struct RelationshipAuditSummary: Codable, Equatable {
    let recordsChecked: Int
    let relationshipsChecked: Int
    let failures: Int
    let warnings: Int
}

struct RelationshipAuditCheckResult: Codable, Equatable {
    let id: String
    let status: String
    let severity: String
    let checked: Int
    let failed: Int
}

struct RelationshipAuditFinding: Codable, Equatable {
    let severity: String
    let checkId: String
    let recordType: String
    let recordId: String?
    let field: String
    let referencedType: String?
    let referencedId: String?
    let message: String
}

struct ScenarioSemanticCheck: Codable, Equatable {
    let id: String
    let recordType: String
    let match: ScenarioSemanticMatch
    let minCount: Int
}

struct ScenarioSemanticMatch: Codable, Equatable {
    let nameContains: String?
    let nameEquals: String?
    let titleContains: String?
    let titleEquals: String?
    let textContains: String?
    let kindEquals: String?
    let stateEquals: String?
    let thingNameEquals: String?

    init(
        nameContains: String? = nil,
        nameEquals: String? = nil,
        titleContains: String? = nil,
        titleEquals: String? = nil,
        textContains: String? = nil,
        kindEquals: String? = nil,
        stateEquals: String? = nil,
        thingNameEquals: String? = nil
    ) {
        self.nameContains = nameContains
        self.nameEquals = nameEquals
        self.titleContains = titleContains
        self.titleEquals = titleEquals
        self.textContains = textContains
        self.kindEquals = kindEquals
        self.stateEquals = stateEquals
        self.thingNameEquals = thingNameEquals
    }
}

struct RelationshipAuditService {
    func audit(
        _ envelope: LedgerExportEnvelope,
        scenarioId: String,
        semanticChecks: [ScenarioSemanticCheck] = []
    ) -> RelationshipAuditReport {
        let records = envelope.records
        let index = RelationshipAuditIndex(records: records)
        var checks: [RelationshipAuditCheckResult] = []
        var findings: [RelationshipAuditFinding] = []
        var relationshipsChecked = 0

        appendCheck("event-thing-references-exist", checked: records.events.count, checks: &checks, findings: &findings) {
            records.events.compactMap { record in
                missing(record.thingId, in: index.things, check: "event-thing-references-exist", type: "event", id: record.id, field: "thingId", referencedType: "thing")
            }
        }
        appendCheck("rule-thing-references-exist", checked: records.rules.count, checks: &checks, findings: &findings) {
            records.rules.compactMap { record in
                missing(record.thingId, in: index.things, check: "rule-thing-references-exist", type: "rule", id: record.id, field: "thingId", referencedType: "thing")
            }
        }
        appendCheck("note-linked-things-exist", checked: records.notes.reduce(0) { $0 + $1.linkedThingIds.count }, checks: &checks, findings: &findings) {
            records.notes.flatMap { note in
                note.linkedThingIds.compactMap {
                    missing($0, in: index.things, check: "note-linked-things-exist", type: "note", id: note.id, field: "linkedThingIds", referencedType: "thing")
                }
            }
        }
        appendCheck("chat-linked-entities-exist", checked: records.chatMessages.reduce(0) { $0 + $1.linkedEntityIds.count }, checks: &checks, findings: &findings) {
            records.chatMessages.flatMap { message in
                message.linkedEntityIds.compactMap {
                    missing($0, in: index.allEntities, check: "chat-linked-entities-exist", type: "chatMessage", id: message.id, field: "linkedEntityIds", referencedType: "entity")
                }
            }
        }
        appendCheck("review-target-exists", checked: records.ledgerReviewItems.filter { $0.targetId != nil }.count, checks: &checks, findings: &findings) {
            records.ledgerReviewItems.compactMap { item in
                guard let targetId = item.targetId else { return nil }
                return missing(targetId, in: index.reviewIDs(for: item.targetType), check: "review-target-exists", type: "ledgerReviewItem", id: item.id, field: "targetId", referencedType: item.targetType)
            }
        }
        appendCheck("review-evidence-exists", checked: records.ledgerReviewItems.reduce(0) { $0 + $1.evidence.count }, checks: &checks, findings: &findings) {
            records.ledgerReviewItems.flatMap { item in
                item.evidence.compactMap {
                    missing($0.sourceId, in: index.reviewIDs(for: $0.sourceType), check: "review-evidence-exists", type: "ledgerReviewItem", id: item.id, field: "evidence.sourceId", referencedType: $0.sourceType)
                }
            }
        }
        appendEndpointCheck("entity-link-source-exists", links: records.entityLinks, source: true, index: index, checks: &checks, findings: &findings)
        appendEndpointCheck("entity-link-target-exists", links: records.entityLinks, source: false, index: index, checks: &checks, findings: &findings)
        appendExtractionChecks(records, index: index, checks: &checks, findings: &findings)
        appendSourceChecks(records, index: index, checks: &checks, findings: &findings)
        appendSemanticChecks(semanticChecks, records: records, index: index, checks: &checks, findings: &findings)

        relationshipsChecked = checks.reduce(0) { $0 + $1.checked }
        let failures = findings.filter { $0.severity == "error" }.count
        let warnings = findings.filter { $0.severity == "warning" }.count
        return RelationshipAuditReport(
            schemaVersion: 1,
            scenarioId: scenarioId,
            status: failures == 0 ? "passed" : "failed",
            summary: RelationshipAuditSummary(
                recordsChecked: index.recordCount,
                relationshipsChecked: relationshipsChecked,
                failures: failures,
                warnings: warnings
            ),
            checks: checks,
            findings: findings
        )
    }

    func markdown(for report: RelationshipAuditReport) -> String {
        var lines = [
            "# Relationship Audit: \(report.scenarioId)",
            "",
            "Status: \(report.status)",
            "",
            "## Summary",
            "",
            "- Records checked: \(report.summary.recordsChecked)",
            "- Relationships checked: \(report.summary.relationshipsChecked)",
            "- Failures: \(report.summary.failures)",
            "- Warnings: \(report.summary.warnings)",
            "",
            "## Checks",
        ]
        for check in report.checks {
            lines.append("- \(check.id): \(check.status), \(check.checked) checked, \(check.failed) failed")
        }
        if !report.findings.isEmpty {
            lines.append("")
            lines.append("## Findings")
            for finding in report.findings {
                lines.append("- [\(finding.severity)] \(finding.checkId): \(finding.message)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func appendCheck(
        _ id: String,
        checked: Int,
        checks: inout [RelationshipAuditCheckResult],
        findings: inout [RelationshipAuditFinding],
        buildFindings: () -> [RelationshipAuditFinding]
    ) {
        let newFindings = buildFindings()
        findings.append(contentsOf: newFindings)
        checks.append(RelationshipAuditCheckResult(
            id: id,
            status: newFindings.contains { $0.severity == "error" } ? "failed" : "passed",
            severity: "error",
            checked: checked,
            failed: newFindings.filter { $0.severity == "error" }.count
        ))
    }

    private func appendEndpointCheck(
        _ id: String,
        links: [EntityLinkExport],
        source: Bool,
        index: RelationshipAuditIndex,
        checks: inout [RelationshipAuditCheckResult],
        findings: inout [RelationshipAuditFinding]
    ) {
        appendCheck(id, checked: links.count, checks: &checks, findings: &findings) {
            links.compactMap { link in
                let type = source ? link.fromEntityType : link.toEntityType
                let targetID = source ? link.fromEntityId : link.toEntityId
                return missing(targetID, in: index.entityIDs(for: type), check: id, type: "entityLink", id: link.id, field: source ? "fromEntityId" : "toEntityId", referencedType: type)
            }
        }
    }

    private func appendExtractionChecks(_ records: ExportRecords, index: RelationshipAuditIndex, checks: inout [RelationshipAuditCheckResult], findings: inout [RelationshipAuditFinding]) {
        appendCheck("extraction-run-chat-message-exists", checked: records.extractionRuns.filter { $0.chatMessageId != nil }.count, checks: &checks, findings: &findings) {
            records.extractionRuns.compactMap { run in
                missing(run.chatMessageId, in: index.chatMessages, check: "extraction-run-chat-message-exists", type: "extractionRun", id: run.id, field: "chatMessageId", referencedType: "chatMessage")
            }
        }
        appendCheck("created-entity-ids-exist", checked: records.extractionRuns.reduce(0) { $0 + $1.createdEntityIds.count }, checks: &checks, findings: &findings) {
            records.extractionRuns.flatMap { run in
                createdEntityFindings(run, index: index)
            }
        }
        appendCheck("chat-extraction-run-ids-exist", checked: records.chatMessages.reduce(0) { $0 + $1.extractionRunIds.count + $1.successfulExtractionRunIds.count + ($1.latestExtractionRunId == nil ? 0 : 1) }, checks: &checks, findings: &findings) {
            records.chatMessages.flatMap { message in
                (message.extractionRunIds + message.successfulExtractionRunIds + [message.latestExtractionRunId].compactMap { $0 }).compactMap {
                    missing($0, in: index.extractionRuns, check: "chat-extraction-run-ids-exist", type: "chatMessage", id: message.id, field: "extractionRunIds", referencedType: "extractionRun")
                }
            }
        }
    }

    private func appendSourceChecks(_ records: ExportRecords, index: RelationshipAuditIndex, checks: inout [RelationshipAuditCheckResult], findings: inout [RelationshipAuditFinding]) {
        let sources = index.sources(records)
        appendCheck("extracted-source-chat-message-exists", checked: sources.filter { $0.source.kind == "extracted" && $0.source.chatMessageId != nil }.count, checks: &checks, findings: &findings) {
            sources.compactMap { record in
                guard record.source.kind == "extracted" else { return nil }
                return missing(record.source.chatMessageId, in: index.chatMessages, check: "extracted-source-chat-message-exists", type: record.type, id: record.id, field: "source.chatMessageId", referencedType: "chatMessage")
            }
        }
        appendCheck("extracted-source-run-exists", checked: sources.filter { $0.source.kind == "extracted" && $0.source.extractionRunId != nil }.count, checks: &checks, findings: &findings) {
            sources.compactMap { record in
                guard record.source.kind == "extracted" else { return nil }
                return missing(record.source.extractionRunId, in: index.extractionRuns, check: "extracted-source-run-exists", type: record.type, id: record.id, field: "source.extractionRunId", referencedType: "extractionRun")
            }
        }
        appendCheck("manual-source-has-no-run", checked: sources.filter { $0.source.kind == "manual" }.count, checks: &checks, findings: &findings) {
            sources.compactMap { record in
                guard record.source.kind == "manual", record.source.extractionRunId != nil else { return nil }
                return finding("manual-source-has-no-run", type: record.type, id: record.id, field: "source.extractionRunId", referencedType: "extractionRun", referencedId: record.source.extractionRunId, message: "Manual source includes an extraction run.")
            }
        }
    }

    private func appendSemanticChecks(_ semanticChecks: [ScenarioSemanticCheck], records: ExportRecords, index: RelationshipAuditIndex, checks: inout [RelationshipAuditCheckResult], findings: inout [RelationshipAuditFinding]) {
        for semanticCheck in semanticChecks {
            let count = semanticMatchCount(semanticCheck, records: records, index: index)
            let failed = count < semanticCheck.minCount
            if failed {
                findings.append(finding(semanticCheck.id, type: semanticCheck.recordType, id: nil, field: "semanticChecks", referencedType: nil, referencedId: nil, message: "Expected at least \(semanticCheck.minCount) matching \(semanticCheck.recordType) records, found \(count)."))
            }
            checks.append(RelationshipAuditCheckResult(id: semanticCheck.id, status: failed ? "failed" : "passed", severity: "error", checked: count, failed: failed ? 1 : 0))
        }
    }

    private func createdEntityFindings(_ run: ExtractionRunExport, index: RelationshipAuditIndex) -> [RelationshipAuditFinding] {
        let typedIDs: [(String, [String], Set<String>)] = [
            ("thing", run.createdEntities.things, index.things),
            ("event", run.createdEntities.events, index.events),
            ("rule", run.createdEntities.rules, index.rules),
            ("note", run.createdEntities.notes, index.notes),
        ]
        var findings: [RelationshipAuditFinding] = typedIDs.flatMap { type, ids, knownIDs in
            ids.compactMap {
                missing($0, in: knownIDs, check: "created-entity-ids-exist", type: "extractionRun", id: run.id, field: "createdEntities.\(type)", referencedType: type)
            }
        }
        let typedUnion = Set(typedIDs.flatMap(\.1))
        for id in run.createdEntityIds where !typedUnion.contains(id) || !index.allEntities.contains(id) {
            findings.append(finding("created-entity-ids-exist", type: "extractionRun", id: run.id, field: "createdEntityIds", referencedType: "entity", referencedId: id, message: "Extraction run references a missing created entity."))
        }
        return findings
    }

    private func semanticMatchCount(_ check: ScenarioSemanticCheck, records: ExportRecords, index: RelationshipAuditIndex) -> Int {
        switch check.recordType {
        case "thing":
            records.things.filter { matches(text: $0.name, contains: check.match.nameContains, equals: check.match.nameEquals) }.count
        case "event":
            records.events.filter {
                matches(text: $0.title, contains: check.match.titleContains, equals: check.match.titleEquals)
                    && matchesThingName($0.thingId, expected: check.match.thingNameEquals, index: index)
            }.count
        case "rule":
            records.rules.filter { matches(text: $0.title, contains: check.match.titleContains, equals: check.match.titleEquals) }.count
        case "note":
            records.notes.filter { matches(text: $0.text, contains: check.match.textContains, equals: nil) }.count
        case "ledgerReviewItem":
            records.ledgerReviewItems.filter {
                matches(text: $0.kind, contains: nil, equals: check.match.kindEquals)
                    && matches(text: $0.state, contains: nil, equals: check.match.stateEquals)
            }.count
        default:
            0
        }
    }

    private func matchesThingName(_ thingID: String?, expected: String?, index: RelationshipAuditIndex) -> Bool {
        guard let expected else { return true }
        guard let thingID, let thing = index.thingsByID[thingID] else { return false }
        return thing.name.caseInsensitiveCompare(expected) == .orderedSame
    }

    private func matches(text: String, contains: String?, equals: String?) -> Bool {
        if let equals, text.caseInsensitiveCompare(equals) != .orderedSame { return false }
        if let contains, text.range(of: contains, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        return true
    }

    private func missing(_ id: String?, in ids: Set<String>, check: String, type: String, id recordID: String, field: String, referencedType: String) -> RelationshipAuditFinding? {
        guard let id, !ids.contains(id) else { return nil }
        return finding(check, type: type, id: recordID, field: field, referencedType: referencedType, referencedId: id, message: "\(type) references a missing \(referencedType).")
    }

    private func finding(_ check: String, type: String, id: String?, field: String, referencedType: String?, referencedId: String?, message: String) -> RelationshipAuditFinding {
        RelationshipAuditFinding(severity: "error", checkId: check, recordType: type, recordId: id, field: field, referencedType: referencedType, referencedId: referencedId, message: message)
    }
}

private struct RelationshipAuditIndex {
    let chatMessages: Set<String>
    let extractionRuns: Set<String>
    let things: Set<String>
    let events: Set<String>
    let rules: Set<String>
    let notes: Set<String>
    let thingsByID: [String: ThingExport]
    let allEntities: Set<String>
    let recordCount: Int

    init(records: ExportRecords) {
        chatMessages = Set(records.chatMessages.map(\.id))
        extractionRuns = Set(records.extractionRuns.map(\.id))
        things = Set(records.things.map(\.id))
        events = Set(records.events.map(\.id))
        rules = Set(records.rules.map(\.id))
        notes = Set(records.notes.map(\.id))
        thingsByID = Dictionary(uniqueKeysWithValues: records.things.map { ($0.id, $0) })
        allEntities = chatMessages.union(extractionRuns).union(things).union(events).union(rules).union(notes)
        recordCount = chatMessages.count + extractionRuns.count + things.count + events.count + rules.count + notes.count + records.ledgerReviewItems.count + records.entityLinks.count
    }

    func entityIDs(for type: String) -> Set<String> {
        switch type {
        case "chatMessage": chatMessages
        case "extractionRun": extractionRuns
        case "thing": things
        case "event": events
        case "rule": rules
        case "note": notes
        default: []
        }
    }

    func reviewIDs(for type: String) -> Set<String> {
        switch type {
        case "chat_message": chatMessages
        case "thing": things
        case "event": events
        case "rule": rules
        default: []
        }
    }

    func sources(_ records: ExportRecords) -> [(type: String, id: String, source: ExportSource)] {
        records.things.map { ("thing", $0.id, $0.source) }
            + records.events.map { ("event", $0.id, $0.source) }
            + records.rules.map { ("rule", $0.id, $0.source) }
            + records.notes.map { ("note", $0.id, $0.source) }
            + records.entityLinks.map { ("entityLink", $0.id, $0.source) }
    }
}
