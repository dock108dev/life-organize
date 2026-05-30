import SwiftUI

enum SettingsDeveloperDestination: Identifiable, CaseIterable {
    case extractionAttempts
    case failedExtractions
    case internalQALab

    var id: Self { self }

    var title: String {
        switch self {
        case .extractionAttempts:
            return "Extraction Attempts"
        case .failedExtractions:
            return "Failed Extractions"
        case .internalQALab:
            return "Internal QA Lab"
        }
    }

    var detail: String {
        switch self {
        case .extractionAttempts:
            return "Review recent extraction runs."
        case .failedExtractions:
            return "Inspect entries that need retry or repair."
        case .internalQALab:
            return "Open local QA tools."
        }
    }

    var systemImage: String {
        switch self {
        case .extractionAttempts:
            return "list.bullet.rectangle"
        case .failedExtractions:
            return "exclamationmark.triangle"
        case .internalQALab:
            return "testtube.2"
        }
    }

    var tone: LedgerTone {
        switch self {
        case .extractionAttempts:
            return .info
        case .failedExtractions:
            return .attention
        case .internalQALab:
            return .note
        }
    }
}

extension SettingsView {
    @ViewBuilder
    func developerDestinationView(for destination: SettingsDeveloperDestination) -> some View {
        switch destination {
        case .extractionAttempts:
            ExtractionDebugListView(deviceTokenStore: deviceTokenStore)
        case .failedExtractions:
            ExtractionDebugListView(deviceTokenStore: deviceTokenStore, initialFilter: .failed)
        case .internalQALab:
            InternalQALabView(deviceTokenStore: deviceTokenStore)
        }
    }
}
