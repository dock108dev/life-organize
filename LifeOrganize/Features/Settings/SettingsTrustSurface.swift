enum SettingsTrustCopy {
    static let exportTitle = "Export local data"
    static let exportBody = "Export saved entries, links, and local history for backup or review."
    static let clearTitle = "Clear local data"
    static let clearBody = "Remove saved entries and related timeline history from this device."
    static let clearDeletes = """
    Deletes saved entries, Things, reminders, notes, links, review tasks, and timeline history from this device.
    """
    static let clearKeeps = "Keeps the app connection so new entries can still organize later."
    static let clearPhrase = "CLEAR MY DATA"
}

struct SettingsSafetyRowContent: Equatable {
    let title: String
    let detail: String
    let pillText: String
    let symbolName: String
    let tone: LedgerTone

    static let clearsLocalRecords = SettingsSafetyRowContent(
        title: "Clears local entries",
        detail: SettingsTrustCopy.clearDeletes,
        pillText: "Clears",
        symbolName: "minus.circle",
        tone: .danger
    )

    static let keepsSavedToken = SettingsSafetyRowContent(
        title: "Keeps app connection",
        detail: SettingsTrustCopy.clearKeeps,
        pillText: "Keeps",
        symbolName: "checkmark.circle",
        tone: .success
    )
}

enum SettingsFeedback: Equatable {
    case deviceTokenSaved
    case deviceTokenSavedRetryDeferred
    case deviceTokenReplaced
    case deviceTokenRemoved
    case exportReady
    case localDataCleared
    case deviceTokenReadFailed
    case deviceTokenEmpty
    case deviceTokenSaveFailed
    case deviceTokenRemoveFailed
    case exportFailed
    case clearDataFailed

    var isError: Bool {
        switch self {
        case .deviceTokenSaved,
             .deviceTokenSavedRetryDeferred,
             .deviceTokenReplaced,
             .deviceTokenRemoved,
             .exportReady,
             .localDataCleared:
            false
        case .deviceTokenReadFailed,
             .deviceTokenEmpty,
             .deviceTokenSaveFailed,
             .deviceTokenRemoveFailed,
             .exportFailed,
             .clearDataFailed:
            true
        }
    }

    var icon: String {
        isError ? "exclamationmark.triangle" : "checkmark.circle"
    }

    var message: String {
        switch self {
        case .deviceTokenSaved:
            "App connection is ready. New entries can organize across your timeline."
        case .deviceTokenSavedRetryDeferred:
            "App connection is ready. Some saved entries will retry later."
        case .deviceTokenReplaced:
            "App connection reset. New entries will reconnect automatically."
        case .deviceTokenRemoved:
            "App connection reset. Timeline capture still works locally."
        case .exportReady:
            "Export ready. Choose where to save or share the local data copy."
        case .localDataCleared:
            "Local entries cleared from this device."
        case .deviceTokenReadFailed:
            "Could not read the app connection. Reopen Settings and try again."
        case .deviceTokenEmpty:
            "App connection could not be prepared."
        case .deviceTokenSaveFailed:
            "Could not save the app connection. Check device Keychain access and try again."
        case .deviceTokenRemoveFailed:
            "Could not reset the app connection. Try again."
        case .exportFailed:
            "Could not create the export. Your local data was not changed. Try again."
        case .clearDataFailed:
            "Could not clear local data. Some entries may still be saved. Try again."
        }
    }
}
