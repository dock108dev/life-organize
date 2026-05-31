import Foundation
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    typealias SendAction = @MainActor (
        String,
        ModelContext,
        any DeviceTokenStore,
        UUID,
        @escaping (UUID) -> Bool,
        @escaping (ChatMessage) -> Void
    ) async throws -> Void

    @Published var draft = ""
    @Published private(set) var isCommittingSend = false
    @Published private(set) var activeOrganizationCount = 0
    @Published private(set) var sendError: String?
    private let sendAction: SendAction

    init(sendAction: SendAction? = nil) {
        self.sendAction = sendAction ?? { text, modelContext, deviceTokenStore, dataGeneration, isDataGenerationCurrent,
            onRawMessagePersisted in
            let service = ChatSendService(
                modelContext: modelContext,
                extractor: AppRuntimeConfiguration.current.messageExtractionClient(deviceTokenStore: deviceTokenStore),
                webRequestClient: AppRuntimeConfiguration.current.webRequestClient(deviceTokenStore: deviceTokenStore),
                dateProvider: AppRuntimeConfiguration.current.dateProvider,
                dataGeneration: dataGeneration,
                isDataGenerationCurrent: isDataGenerationCurrent
            )
            try await service.send(text, onRawMessagePersisted: onRawMessagePersisted)
        }
    }

    var isOrganizing: Bool {
        activeOrganizationCount > 0
    }

    func applySuggestion(_ suggestion: ChatSuggestion) {
        draft = suggestion.draftText
    }

    func inputPlaceholder(hasAIServiceCredential: Bool) -> String {
        hasAIServiceCredential ? "Add anything or ask what’s due" : "Capture something locally"
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
                try await sendAction(
                    trimmed,
                    modelContext,
                    deviceTokenStore,
                    dataGeneration,
                    isDataGenerationCurrent
                ) { [weak self] message in
                    guard let self else { return }
                    didPersistRawMessage = true
                    draft = ""
                    isCommittingSend = false
                    activeOrganizationCount += 1
                    onRawMessagePersisted(message.id)
                }
            } catch {
                sendError = Self.userFacingSendErrorMessage(for: error, didPersistRawMessage: didPersistRawMessage)
            }
            if didPersistRawMessage {
                activeOrganizationCount = max(0, activeOrganizationCount - 1)
            } else {
                isCommittingSend = false
            }
        }
    }

    static func userFacingSendErrorMessage(for error: Error, didPersistRawMessage: Bool) -> String {
        if didPersistRawMessage {
            if error is AppError {
                return "Saved on this device. The service is unavailable right now."
            }
            return "Saved on this device. Some details may need attention in Review."
        }

        if case AppError.missingServiceToken = error {
            return "The service is unavailable right now."
        }
        if case AppError.invalidServiceToken = error {
            return "The service rejected this device."
        }
        if error is AppError {
            return "Couldn't save that. Check your connection and try again."
        }
        return "Couldn't save that. Try again."
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
