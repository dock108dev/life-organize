enum SettingsTrustCopy {
    static let apiKeyTitle = "AI service"
    static let apiKeyBody = "Entries stay local. This device uses a private service token to connect new timeline details through the LifeOrganize backend."
    static let noKeyDetail = "Local-only mode is available if the service cannot be reached."
    static let savedKeyDetail = "This device token is stored in Keychain and is not included in local data exports. The shared cloud credential stays on the backend."
    static let exportTitle = "Local data copy"
    static let exportBody = "Export saved entries, links, and local history for backup or review."
    static let clearTitle = "Reset this device"
    static let clearBody = "Clear local records for a fresh start. Your service token stays in Keychain."
    static let clearDeletes = "Deletes timeline history, Things, events, reminders, notes, links, review items, and continuity records."
    static let clearKeeps = "Keeps the service token."
    static let clearPhrase = "DELETE MY LEDGER"
}

struct SettingsSafetyRowContent: Equatable {
    let title: String
    let detail: String
    let pillText: String
    let symbolName: String
    let tone: LedgerTone

    static let clearsLocalRecords = SettingsSafetyRowContent(
        title: "Clears local records",
        detail: SettingsTrustCopy.clearDeletes,
        pillText: "Clears",
        symbolName: "minus.circle",
        tone: .danger
    )

    static let keepsSavedKey = SettingsSafetyRowContent(
        title: "Keeps service token",
        detail: SettingsTrustCopy.clearKeeps,
        pillText: "Keeps",
        symbolName: "checkmark.circle",
        tone: .success
    )
}

enum SettingsFeedback: Equatable {
    case apiKeySaved
    case apiKeyReplaced
    case apiKeyRemoved
    case exportReady
    case localDataCleared
    case apiKeyReadFailed
    case apiKeyEmpty
    case apiKeySaveFailed
    case apiKeyRemoveFailed
    case exportFailed
    case clearDataFailed

    var isError: Bool {
        switch self {
        case .apiKeySaved, .apiKeyReplaced, .apiKeyRemoved, .exportReady, .localDataCleared:
            false
        case .apiKeyReadFailed, .apiKeyEmpty, .apiKeySaveFailed, .apiKeyRemoveFailed, .exportFailed, .clearDataFailed:
            true
        }
    }

    var icon: String {
        isError ? "exclamationmark.triangle" : "checkmark.circle"
    }

    var message: String {
        switch self {
        case .apiKeySaved:
            "Service token is ready. New entries can connect across your timeline."
        case .apiKeyReplaced:
            "Service token refreshed. Future timeline connections will use the new token."
        case .apiKeyRemoved:
            "Service token removed. Timeline capture still works locally."
        case .exportReady:
            "Export ready. Choose where to save or share the local data copy."
        case .localDataCleared:
            "Local record cleared from this device. Your service token stayed in place."
        case .apiKeyReadFailed:
            "Could not read the service token. Reopen Settings and try again."
        case .apiKeyEmpty:
            "Service token cannot be empty."
        case .apiKeySaveFailed:
            "Could not save the service token. Check device Keychain access and try again."
        case .apiKeyRemoveFailed:
            "Could not remove the service token. Try again."
        case .exportFailed:
            "Could not create the export. Your local data was not changed. Try again."
        case .clearDataFailed:
            "Could not clear local data. Some records may still be saved. Try again."
        }
    }
}
