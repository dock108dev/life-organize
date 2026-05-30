import Foundation
import SwiftData

enum LaunchMaintenanceOperation: String, CaseIterable, Equatable {
    case extractionRecovery = "extraction_recovery"
    case derivedFields = "derived_fields"
    case reviewItems = "review_items"
    case dataIntegrity = "data_integrity"
}

struct LaunchMaintenanceFailure: Equatable {
    let operation: LaunchMaintenanceOperation
    let errorKind: String
}

@MainActor
struct LaunchMaintenanceService {
    var repairInterruptedEntries: () throws -> Void
    var repairDerivedFields: () throws -> Void
    var refreshReviewItems: () throws -> Void
    var validateDataIntegrity: () throws -> Void
    var diagnostics: LocalDiagnosticEventStore

    init(
        modelContext: ModelContext,
        diagnostics: LocalDiagnosticEventStore = LocalDiagnosticEventStore()
    ) {
        self.repairInterruptedEntries = {
            try ExtractionRecoveryMaintenanceService(modelContext: modelContext).repairInterruptedEntries()
        }
        self.repairDerivedFields = {
            try DerivedFieldMaintenanceService(modelContext: modelContext).repairAll()
        }
        self.refreshReviewItems = {
            try LedgerReviewItemGenerationService(modelContext: modelContext).refresh()
        }
        self.validateDataIntegrity = {
            try LocalDataIntegrityValidator(
                modelContext: modelContext,
                diagnostics: diagnostics
            ).validateAndRecordDiagnostics()
        }
        self.diagnostics = diagnostics
    }

    init(
        diagnostics: LocalDiagnosticEventStore = LocalDiagnosticEventStore(),
        repairInterruptedEntries: @escaping () throws -> Void,
        repairDerivedFields: @escaping () throws -> Void,
        refreshReviewItems: @escaping () throws -> Void,
        validateDataIntegrity: @escaping () throws -> Void = {}
    ) {
        self.repairInterruptedEntries = repairInterruptedEntries
        self.repairDerivedFields = repairDerivedFields
        self.refreshReviewItems = refreshReviewItems
        self.validateDataIntegrity = validateDataIntegrity
        self.diagnostics = diagnostics
    }

    @discardableResult
    func repair() -> [LaunchMaintenanceFailure] {
        [
            run(.extractionRecovery, repairInterruptedEntries),
            run(.derivedFields, repairDerivedFields),
            run(.reviewItems, refreshReviewItems),
            run(.dataIntegrity, validateDataIntegrity)
        ].compactMap { $0 }
    }

    private func run(
        _ operation: LaunchMaintenanceOperation,
        _ action: () throws -> Void
    ) -> LaunchMaintenanceFailure? {
        do {
            try action()
            return nil
        } catch {
            diagnostics.record(
                severity: .error,
                category: "launch_maintenance",
                operation: operation.rawValue,
                error: error
            )
            return LaunchMaintenanceFailure(
                operation: operation,
                errorKind: String(describing: type(of: error))
            )
        }
    }
}
