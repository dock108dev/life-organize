enum SettingsTrustCopy {
    static let deviceTokenTitle = "AI service"
    static let deviceTokenBody = """
    Entries stay local. This device uses a private service token to connect new timeline details through the \
    LifeOrganize backend.
    """
    static let noTokenDetail = "Local-only mode is available if the service cannot be reached."
    static let savedTokenDetail = """
    This device token is stored in Keychain and is not included in local data exports. The shared cloud credential \
    stays on the backend.
    """
    static let exportTitle = "Local data copy"
    static let exportBody = "Export saved entries, links, and local history for backup or review."
    static let clearTitle = "Clear local data"
    static let clearBody = "Remove saved entries and related timeline history from this device. Your service token stays in Keychain."
    static let clearDeletes = """
    Deletes saved entries, Things, reminders, notes, links, review tasks, and timeline history from this device.
    """
    static let clearKeeps = "Keeps the service token so new entries can still connect later."
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
        title: "Keeps service token",
        detail: SettingsTrustCopy.clearKeeps,
        pillText: "Keeps",
        symbolName: "checkmark.circle",
        tone: .success
    )
}

enum SettingsFeedback: Equatable {
    case deviceTokenSaved
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
        case .deviceTokenSaved, .deviceTokenReplaced, .deviceTokenRemoved, .exportReady, .localDataCleared:
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
            "Service token is ready. New entries can connect across your timeline."
        case .deviceTokenReplaced:
            "Service token refreshed. Future timeline connections will use the new token."
        case .deviceTokenRemoved:
            "Service token removed. Timeline capture still works locally."
        case .exportReady:
            "Export ready. Choose where to save or share the local data copy."
        case .localDataCleared:
            "Local entries cleared from this device. Your service token stayed in place."
        case .deviceTokenReadFailed:
            "Could not read the service token. Reopen Settings and try again."
        case .deviceTokenEmpty:
            "Service token cannot be empty."
        case .deviceTokenSaveFailed:
            "Could not save the service token. Check device Keychain access and try again."
        case .deviceTokenRemoveFailed:
            "Could not remove the service token. Try again."
        case .exportFailed:
            "Could not create the export. Your local data was not changed. Try again."
        case .clearDataFailed:
            "Could not clear local data. Some entries may still be saved. Try again."
        }
    }
}
