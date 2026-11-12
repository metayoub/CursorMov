import Foundation

/// Preferences stored in UserDefaults.
public final class UserDefaultsSettings: SettingsStore {
    private static let nudgeEnabledKey = "nudgeEnabled"
    private static let batteryThresholdKey = "batteryThreshold"
    private static let scheduleEnabledKey = "scheduleEnabled"
    private static let scheduleStartKey = "scheduleStartMinute"
    private static let scheduleEndKey = "scheduleEndMinute"
    private static let scheduleDaysKey = "scheduleWeekdays"
    private static let watchedAppsEnabledKey = "watchedAppsEnabled"
    private static let watchedAppsKey = "watchedAppBundleIDs"
    private static let turnOffAtKey = "turnOffAtMinute"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let standard = Schedule.standard
        defaults.register(defaults: [
            Self.nudgeEnabledKey: true, Self.batteryThresholdKey: 20,
            Self.scheduleEnabledKey: standard.isEnabled,
            Self.scheduleStartKey: standard.startMinute,
            Self.scheduleEndKey: standard.endMinute,
            Self.scheduleDaysKey: standard.weekdays.sorted(),
        ])
    }

    public var batteryThreshold: Int {
        get { defaults.integer(forKey: Self.batteryThresholdKey) }
        set { defaults.set(newValue, forKey: Self.batteryThresholdKey) }
    }

    public var nudgeEnabled: Bool {
        get { defaults.bool(forKey: Self.nudgeEnabledKey) }
        set { defaults.set(newValue, forKey: Self.nudgeEnabledKey) }
    }

    public var schedule: Schedule {
        get {
            let days = (defaults.array(forKey: Self.scheduleDaysKey) as? [Int]) ?? []
            return Schedule(isEnabled: defaults.bool(forKey: Self.scheduleEnabledKey),
                            startMinute: Self.clampMinute(defaults.integer(forKey: Self.scheduleStartKey)),
                            endMinute: Self.clampMinute(defaults.integer(forKey: Self.scheduleEndKey)),
                            weekdays: Set(days.filter { (1...7).contains($0) }))
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Self.scheduleEnabledKey)
            defaults.set(newValue.startMinute, forKey: Self.scheduleStartKey)
            defaults.set(newValue.endMinute, forKey: Self.scheduleEndKey)
            defaults.set(newValue.weekdays.sorted(), forKey: Self.scheduleDaysKey)
        }
    }

    public var watchedApps: WatchedApps {
        get {
            WatchedApps(isEnabled: defaults.bool(forKey: Self.watchedAppsEnabledKey),
                        bundleIDs: defaults.stringArray(forKey: Self.watchedAppsKey) ?? [])
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Self.watchedAppsEnabledKey)
            defaults.set(newValue.bundleIDs, forKey: Self.watchedAppsKey)
        }
    }

    public var turnOffAtMinute: Int? {
        get { (defaults.object(forKey: Self.turnOffAtKey) as? Int).map(Self.clampMinute) }
        set { defaults.set(newValue, forKey: Self.turnOffAtKey) }
    }

    private static func clampMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 1439)
    }
}
