import SwiftData
import SwiftUI

struct ManualExtractionRetryButton: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState

    let message: ChatMessage?
    let deviceTokenStore: any DeviceTokenStore

    @State private var isRetrying = false
    @State private var statusText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(buttonTitle) {
                retry()
            }
            .buttonStyle(.bordered)
            .disabled(disabledReason != nil)

            if let text = statusText ?? disabledReason {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buttonTitle: String {
        isRetrying ? "Retrying..." : "Retry"
    }

    private var disabledReason: String? {
        if isRetrying {
            return "Retry is already running."
        }
        guard let message else {
            return "No source message is available."
        }
        do {
            let service = ManualExtractionRetryService(modelContext: modelContext, deviceTokenStore: deviceTokenStore)
            return try service.canRetry(message)?.message
        } catch {
            return "Retry availability could not be checked."
        }
    }

    private func retry() {
        guard let message, disabledReason == nil else { return }
        isRetrying = true
        statusText = nil

        Task {
            defer {
                isRetrying = false
            }

            do {
                let service = ManualExtractionRetryService(
                    modelContext: modelContext,
                    deviceTokenStore: deviceTokenStore,
                    dataGeneration: sessionState.dataGeneration,
                    isDataGenerationCurrent: sessionState.isCurrentDataGeneration
                )
                try await service.retry(message)
                statusText = "Retry finished."
            } catch let error as ManualExtractionRetryError {
                statusText = error.localizedDescription
            } catch {
                statusText = "Still could not organize this entry."
            }
        }
    }
}
