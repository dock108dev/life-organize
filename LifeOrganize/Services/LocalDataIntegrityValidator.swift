import Foundation
import SwiftData

struct LocalDataIntegrityFinding: Equatable {
    enum Severity: String {
        case warning
        case error
    }

    let severity: Severity
    let recordType: String
    let recordID: UUID
    let field: String
    let errorKind: String
}

@MainActor
struct LocalDataIntegrityValidator {
    let modelContext: ModelContext
    var diagnostics: LocalDiagnosticEventStore = LocalDiagnosticEventStore()

    func validate() throws -> [LocalDataIntegrityFinding] {
        var findings: [LocalDataIntegrityFinding] = []
        try findings.append(contentsOf: validateEventMetadata())
        try findings.append(contentsOf: validateReviewEvidence())
        try findings.append(contentsOf: validateExtractionEnvelopes())
        return findings
    }

    @discardableResult
    func validateAndRecordDiagnostics() throws -> [LocalDataIntegrityFinding] {
        let findings = try validate()
        for finding in findings {
            diagnostics.record(
                severity: finding.severity == .error ? .error : .warning,
                category: "data_integrity",
                operation: "validate_\(finding.recordType).\(finding.field)",
                errorKind: finding.errorKind,
                affectedRecordID: finding.recordID
            )
        }
        return findings
    }

    private func validateEventMetadata() throws -> [LocalDataIntegrityFinding] {
        try modelContext.fetch(FetchDescriptor<LedgerEvent>()).compactMap { event in
            decode([LedgerEventMetadataEntry].self, from: event.metadataJSONText).map { errorKind in
                LocalDataIntegrityFinding(
                    severity: .error,
                    recordType: "LedgerEvent",
                    recordID: event.id,
                    field: "metadataJSONText",
                    errorKind: errorKind
                )
            }
        }
    }

    private func validateReviewEvidence() throws -> [LocalDataIntegrityFinding] {
        try modelContext.fetch(FetchDescriptor<LedgerReviewItem>()).compactMap { item in
            decode([LedgerReviewItemEvidence].self, from: item.evidenceJSONText).map { errorKind in
                LocalDataIntegrityFinding(
                    severity: .error,
                    recordType: "LedgerReviewItem",
                    recordID: item.id,
                    field: "evidenceJSONText",
                    errorKind: errorKind
                )
            }
        }
    }

    private func validateExtractionEnvelopes() throws -> [LocalDataIntegrityFinding] {
        try modelContext.fetch(FetchDescriptor<ExtractionAttempt>()).compactMap { attempt in
            decode(ExtractionEnvelope.self, from: attempt.normalizedJSONText).map { errorKind in
                LocalDataIntegrityFinding(
                    severity: .error,
                    recordType: "ExtractionAttempt",
                    recordID: attempt.id,
                    field: "normalizedJSONText",
                    errorKind: errorKind
                )
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) -> String? {
        guard let data = text.data(using: .utf8) else {
            return "invalid_utf8"
        }
        do {
            _ = try JSONDecoder().decode(type, from: data)
            return nil
        } catch {
            return String(describing: Swift.type(of: error))
        }
    }
}
