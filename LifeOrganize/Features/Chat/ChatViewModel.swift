import Foundation
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var isCommittingSend = false
    @Published private(set) var activeOrganizationCount = 0
    @Published private(set) var sendError: String?

    var isOrganizing: Bool {
        activeOrganizationCount > 0
    }

    func applySuggestion(_ suggestion: ChatSuggestion) {
        draft = suggestion.draftText
    }

    func inputPlaceholder(hasOpenAIAPIKey: Bool) -> String {
        hasOpenAIAPIKey ? "Ask what is due or add a note" : "Capture something locally"
    }

    func sendDraft(
        modelContext: ModelContext,
        apiKeyStore: any APIKeyStore,
        dataGeneration: UUID,
        isDataGenerationCurrent: @escaping (UUID) -> Bool,
        onRawMessagePersisted: @escaping (UUID) -> Void = { _ in }
    ) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCommittingSend else { return }

        isCommittingSend = true
        sendError = nil

        Task {
            var didPersistRawMessage = false
            do {
                let service = ChatSendService(
                    modelContext: modelContext,
                    extractor: AppRuntimeConfiguration.current.messageExtractionClient(apiKeyStore: apiKeyStore),
                    webRequestClient: AppRuntimeConfiguration.current.webRequestClient(apiKeyStore: apiKeyStore),
                    dateProvider: AppRuntimeConfiguration.current.dateProvider,
                    dataGeneration: dataGeneration,
                    isDataGenerationCurrent: isDataGenerationCurrent
                )
                try await service.send(trimmed) { [weak self] message in
                    guard let self else { return }
                    didPersistRawMessage = true
                    draft = ""
                    isCommittingSend = false
                    activeOrganizationCount += 1
                    onRawMessagePersisted(message.id)
                }
            } catch {
                sendError = error.localizedDescription
            }
            if didPersistRawMessage {
                activeOrganizationCount = max(0, activeOrganizationCount - 1)
            } else {
                isCommittingSend = false
            }
        }
    }
}

enum ChatSuggestion: CaseIterable, Equatable, Hashable {
    case logEvent
    case logPurchase
    case addReminder
    case addNote

    var title: String {
        switch self {
        case .logEvent:
            "Log something"
        case .logPurchase:
            "Due today"
        case .addReminder:
            "Check later"
        case .addNote:
            "Save note"
        }
    }

    var draftText: String {
        switch self {
        case .logEvent:
            "I "
        case .logPurchase:
            "What do I have to do today?"
        case .addReminder:
            "I want to check this in a month: "
        case .addNote:
            "Note: "
        }
    }
}
