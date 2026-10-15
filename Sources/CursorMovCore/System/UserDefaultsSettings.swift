import Foundation

/// Preferences stored in UserDefaults.
public final class UserDefaultsSettings: SettingsStore {
    private static let nudgeEnabledKey = "nudgeEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.nudgeEnabledKey: true])
    }

    public var nudgeEnabled: Bool {
        get { defaults.bool(forKey: Self.nudgeEnabledKey) }
        set { defaults.set(newValue, forKey: Self.nudgeEnabledKey) }
    }
}
