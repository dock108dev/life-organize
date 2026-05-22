import Foundation
import SwiftUI

struct DebugAccessPolicy: Equatable {
    var isDeveloperModeAvailable: Bool
    var isDeveloperModeUnlocked: Bool

    static let unavailable = DebugAccessPolicy(
        isDeveloperModeAvailable: false,
        isDeveloperModeUnlocked: false
    )

    var allowsExtractionDebugScreens: Bool {
        isDeveloperModeAvailable && isDeveloperModeUnlocked
    }

    var allowsInternalQAScreens: Bool {
        isDeveloperModeAvailable && isDeveloperModeUnlocked
    }
}

@MainActor
final class DeveloperModeState: ObservableObject {
    private enum Keys {
        static let isUnlocked = AppDefaultsKeys.developerModeUnlocked
    }

    private let defaults: UserDefaults
    let isAvailable: Bool
    @Published private(set) var isUnlocked: Bool

    init(
        isAvailable: Bool = AppRuntimeConfiguration.current.isDeveloperModeAvailable,
        defaults: UserDefaults = .standard
    ) {
        self.isAvailable = isAvailable
        self.defaults = defaults
        self.isUnlocked = isAvailable && defaults.bool(forKey: Keys.isUnlocked)
    }

    var policy: DebugAccessPolicy {
        DebugAccessPolicy(
            isDeveloperModeAvailable: isAvailable,
            isDeveloperModeUnlocked: isUnlocked
        )
    }

    func unlock() {
        guard isAvailable else { return }
        isUnlocked = true
        defaults.set(true, forKey: Keys.isUnlocked)
    }

    func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Keys.isUnlocked)
    }
}

private struct DebugAccessPolicyKey: EnvironmentKey {
    static let defaultValue = DebugAccessPolicy.unavailable
}

extension EnvironmentValues {
    var debugAccessPolicy: DebugAccessPolicy {
        get { self[DebugAccessPolicyKey.self] }
        set { self[DebugAccessPolicyKey.self] = newValue }
    }
}
