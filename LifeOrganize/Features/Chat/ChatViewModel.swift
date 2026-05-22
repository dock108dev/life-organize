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

    func inputPlaceholder(hasAIServiceCredential: Bool) -> String {
        hasAIServiceCredential ? "Ask what is due or add a note" : "Capture something locally"
    }

    func sendDraft(
        modelContext: ModelContext,
        deviceTokenStore: any DeviceTokenStore,
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
                    extractor: AppRuntimeConfiguration.current.messageExtractionClient(deviceTokenStore: deviceTokenStore),
                    webRequestClient: AppRuntimeConfiguration.current.webRequestClient(deviceTokenStore: deviceTokenStore),
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
    case addNote
    case askToday
    case addReminder
    case logEvent

    var title: String {
        switch self {
        case .addNote:
            "Save note"
        case .askToday:
            "Ask today"
        case .addReminder:
            "Set reminder"
        case .logEvent:
            "Log something"
        }
    }

    var draftText: String {
        switch self {
        case .addNote:
            "Note: "
        case .askToday:
            "What do I have to do today?"
        case .addReminder:
            "Remind me to "
        case .logEvent:
            "I "
        }
    }
}
