enum V1ScopeContract {
    static let activeRootTabs: [AppTab] = [.log, .things, .rules]
    static let allowedRootTabs: [AppTab] = activeRootTabs

    static let activeSettingsRows: [SettingsRow] = [
        .openAIAPIKey,
        .clearLocalData,
        .exportLocalJSON,
    ]

    static let allowedSettingsRows: [SettingsRow] = [
        .openAIAPIKey,
        .extractionDebug,
        .clearLocalData,
        .exportLocalJSON,
    ]

    static let activePersistenceModels: [PersistenceModel] = [
        .chatMessage,
        .extractionAttempt,
        .entityLink,
        .thing,
        .event,
        .rule,
        .note,
        .reviewItem,
    ]

    static let allowedPersistenceModels: [PersistenceModel] = activePersistenceModels + [
        .reminder,
    ]

    static let allowedOpenAIUses: [OpenAIUse] = [
        .extraction,
        .normalization,
        .dateParsing,
        .recallFormatting,
        .webLookup,
        .webImport,
    ]

    static let allowedSearchModes: [SearchMode] = [.localSubstring, .webSearch]

    static let allowedLedgerNativeCapabilities: [LedgerNativeCapability] = [
        .deterministicLocalProjection,
        .reviewCandidate,
        .actionCandidate,
        .patternInference,
        .timelineSlice,
        .searchFirstAffordance,
    ]

    static let allowedLedgerRouteNameFragments: Set<String> = [
        "action",
        "candidate",
        "debug",
        "feed",
        "logfeed",
        "ledgerfeed",
        "overview",
        "pattern",
        "projection",
        "reminder",
        "review",
        "retry",
        "search",
        "summary",
        "timeline",
    ]

    static let bannedRouteNameFragments: Set<String> = [
        "account",
        "advice",
        "advise",
        "agent",
        "analytics",
        "calendar",
        "coach",
        "copilot",
        "dashboard",
        "embedding",
        "goal",
        "habit",
        "insight",
        "notification",
        "profile",
        "recommend",
        "streak",
        "sync",
        "vector",
        "voice",
    ]

    static let bannedProductSurfaceNameFragments: Set<String> = [
        "advice",
        "advise",
        "agent",
        "assistant",
        "chatbot",
        "coach",
        "copilot",
        "recommend",
    ]

    static let internalProviderNameFragments: Set<String> = [
        "API",
        "HTTP",
        "OpenAI",
        "Keychain",
    ]

    static let bannedPersistenceModelNames: Set<String> = [
        "Account",
        "Advice",
        "Agent",
        "Analytics",
        "Assistant",
        "Badge",
        "Calendar",
        "Embedding",
        "Goal",
        "Habit",
        "Insight",
        "Mood",
        "Recommendation",
        "Streak",
        "Sync",
        "User",
        "Vector",
        "VoiceTranscript",
    ]

    static let bannedFrameworkImports: Set<String> = [
        "AuthenticationServices",
        "CloudKit",
        "EventKit",
        "Firebase",
        "FirebaseAuth",
        "FirebaseFirestore",
        "Mixpanel",
        "PostHog",
        "Segment",
        "Speech",
        "Supabase",
        "UserNotifications",
        "WatchConnectivity",
        "WidgetKit",
    ]

    static let bannedDependencyTerms: Set<String> = [
        "Amplitude",
        "AuthenticationServices",
        "CloudKit",
        "EventKit",
        "Firebase",
        "Mixpanel",
        "PostHog",
        "RevenueCat",
        "Segment",
        "Speech",
        "Supabase",
        "WatchConnectivity",
        "WidgetKit",
    ]

    static let bannedOpenAIInterfaceMethodFragments: Set<String> = [
        "advice",
        "advise",
        "agent",
        "assistant",
        "chat",
        "coach",
        "goal",
        "habit",
        "insight",
        "mood",
        "recommend",
    ]

    static let bannedNotificationCopyFragments: Set<String> = [
        "daily check-in",
        "daily prompt",
        "build the habit",
        "come back today",
        "complete your daily log",
        "don't forget to log",
        "keep the habit going",
        "keep your streak",
        "maintain your progress",
        "notification permission",
        "stay consistent",
        "streak",
        "you haven't checked in",
    ]

    enum SettingsRow: String, CaseIterable {
        case openAIAPIKey = "OpenAI API Key"
        case extractionDebug = "Extraction Debug"
        case clearLocalData = "Clear Local Data"
        case exportLocalJSON = "Export Local JSON"

        var title: String {
            rawValue
        }
    }

    enum PersistenceModel: String, CaseIterable {
        case chatMessage = "ChatMessage"
        case extractionAttempt = "ExtractionAttempt"
        case entityLink = "EntityLink"
        case thing = "Thing"
        case event = "LedgerEvent"
        case rule = "LedgerRule"
        case note = "LedgerNote"
        case reviewItem = "LedgerReviewItem"
        case reminder = "LedgerReminder"
    }

    enum OpenAIUse: String, CaseIterable {
        case extraction
        case normalization
        case dateParsing
        case recallFormatting
        case webLookup
        case webImport
    }

    enum SearchMode: String, CaseIterable {
        case localSubstring
        case webSearch
    }

    enum LedgerNativeCapability: String, CaseIterable {
        case deterministicLocalProjection
        case reviewCandidate
        case actionCandidate
        case patternInference
        case timelineSlice
        case searchFirstAffordance
    }
}
