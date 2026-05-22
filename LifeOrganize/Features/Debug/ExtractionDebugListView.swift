import SwiftData
import SwiftUI

struct ExtractionDebugListView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case failed
        case pending
        case succeeded
        case partial
        case superseded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .failed:
                return "Failed"
            case .pending:
                return "Pending"
            case .succeeded:
                return "Succeeded"
            case .partial:
                return "Partial"
            case .superseded:
                return "Superseded"
            }
        }
    }

    @Query(sort: \ExtractionAttempt.startedAt, order: .reverse) private var attempts: [ExtractionAttempt]
    @State private var filter: Filter
    @State private var searchText = ""

    let apiKeyStore: any APIKeyStore

    init(apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(), initialFilter: Filter = .all) {
        self.apiKeyStore = apiKeyStore
        self._filter = State(initialValue: initialFilter)
    }

    var body: some View {
        Group {
            switch Self.accessPresentation(for: debugAccessPolicy) {
            case .attemptsList:
                List {
                    Section {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        ForEach(filteredAttempts) { attempt in
                            NavigationLink {
                                ExtractionAttemptDebugView(attempt: attempt, apiKeyStore: apiKeyStore)
                            } label: {
                                ExtractionAttemptRow(attempt: attempt)
                            }
                        }
                    }
                }
                .searchable(text: $searchText)
            case .requiredGate(let content):
                DeveloperModeRequiredView(content: content)
            }
        }
        .navigationTitle("Extraction Attempts")
    }

    static func accessPresentation(for policy: DebugAccessPolicy) -> ExtractionDebugAccessPresentation {
        if policy.allowsExtractionDebugScreens {
            return .attemptsList
        }
        return .requiredGate(.extractionDebug)
    }

    private var filteredAttempts: [ExtractionAttempt] {
        attempts.filter(matchesFilter).filter(matchesSearch)
    }

    private func matchesFilter(_ attempt: ExtractionAttempt) -> Bool {
        switch filter {
        case .all:
            return true
        case .failed:
            return attempt.status == .failed
        case .pending:
            return attempt.status == .pending
        case .succeeded:
            return attempt.status == .succeeded
        case .partial:
            return attempt.status == .partiallySucceeded
        case .superseded:
            return attempt.status == .superseded
        }
    }

    private func matchesSearch(_ attempt: ExtractionAttempt) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields = [
            attempt.id.uuidString,
            attempt.sourceMessage?.id.uuidString,
            attempt.sourceMessage?.text,
            attempt.modelName,
            attempt.promptVersion,
            attempt.errorCode?.rawValue,
            attempt.errorMessage,
            attempt.rawResponseText,
            attempt.normalizedJSONText,
        ]
        return fields.compactMap(\.self).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct ExtractionAttemptRow: View {
    let attempt: ExtractionAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ExtractionAttemptStatusChip(status: attempt.status)
                if let error = attempt.errorCode?.rawValue {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text(attempt.sourceMessage?.text.nilIfEmpty ?? "No source message")
                .font(.subheadline)
                .lineLimit(2)

            Text(metadata)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entityCounts)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var metadata: String {
        [
            attempt.modelName ?? "Unknown model",
            ExtractionDebugFormatting.dateTime.string(from: attempt.startedAt),
            ExtractionDebugFormatting.duration(start: attempt.startedAt, end: attempt.completedAt),
        ].joined(separator: " · ")
    }

    private var entityCounts: String {
        "\(attempt.createdThingIDs.count) things · \(attempt.createdEventIDs.count) events · \(attempt.createdRuleIDs.count) reminders · \(attempt.createdNoteIDs.count) notes"
    }
}
