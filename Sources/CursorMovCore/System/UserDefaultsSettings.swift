import Foundation

/// Preferences stored in UserDefaults.
public final class UserDefaultsSettings: SettingsStore {
    private static let nudgeEnabledKey = "nudgeEnabled"
    private static let batteryThresholdKey = "batteryThreshold"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.nudgeEnabledKey: true, Self.batteryThresholdKey: 20])
    }

    public var batteryThreshold: Int {
        get { defaults.integer(forKey: Self.batteryThresholdKey) }
        set { defaults.set(newValue, forKey: Self.batteryThresholdKey) }
    }

    public var nudgeEnabled: Bool {
        get { defaults.bool(forKey: Self.nudgeEnabledKey) }
        set { defaults.set(newValue, forKey: Self.nudgeEnabledKey) }
    }
}
