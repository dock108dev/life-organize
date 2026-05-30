import Foundation

enum LedgerReviewQueueLoadState: Equatable {
    case loaded([LedgerReviewQueueEntry])
    case failed(String)

    var entries: [LedgerReviewQueueEntry] {
        switch self {
        case .loaded(let entries):
            entries
        case .failed:
            []
        }
    }

    var errorMessage: String? {
        switch self {
        case .loaded:
            nil
        case .failed(let message):
            message
        }
    }

    static func load(_ action: () throws -> [LedgerReviewQueueEntry]) -> LedgerReviewQueueLoadState {
        do {
            return .loaded(try action())
        } catch {
            LocalDiagnosticEventStore().record(
                severity: .error,
                category: "review_queue",
                operation: "load_entries",
                error: error
            )
            return .failed("Review could not load. Reopen Review or try again after restarting the app.")
        }
    }
}
