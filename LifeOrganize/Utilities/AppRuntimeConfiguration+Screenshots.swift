import Foundation

enum ScreenshotSeed: String {
    case empty
    case `default`
    case review
    case search
    case carryForward
    case heavy

    init?(argumentValue: String) {
        switch argumentValue.screenshotArgumentKey {
        case "empty":
            self = .empty
        case "default":
            self = .default
        case "review":
            self = .review
        case "search":
            self = .search
        case "carry-forward":
            self = .carryForward
        case "heavy":
            self = .heavy
        default:
            return nil
        }
    }

    var seedScenarioIDs: [String] {
        switch self {
        case .empty:
            ["first_launch_empty"]
        case .default, .carryForward:
            ["operational_home"]
        case .review:
            ["ambiguous_dog_grooming"]
        case .search:
            ["timeline_search"]
        case .heavy:
            ["heavy_history"]
        }
    }
}

enum ScreenshotStart: String {
    case timeline
    case things
    case carryForward
    case settings
    case search
    case review

    init?(argumentValue: String) {
        switch argumentValue.screenshotArgumentKey {
        case "timeline", "log":
            self = .timeline
        case "things":
            self = .things
        case "carry-forward", "rules":
            self = .carryForward
        case "settings":
            self = .settings
        case "search":
            self = .search
        case "review", "review-queue":
            self = .review
        default:
            return nil
        }
    }
}

enum ScreenshotAppearance: String {
    case light
    case dark

    init?(argumentValue: String) {
        self.init(rawValue: argumentValue.screenshotArgumentKey)
    }
}

private extension String {
    var screenshotArgumentKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
