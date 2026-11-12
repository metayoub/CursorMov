import Foundation

/// Asks macOS to keep the Mac awake (no idle sleep, dimming, or lock).
public protocol KeepAwakeAssertion: AnyObject {
    /// Returns false if macOS refused the assertion.
    func acquire() -> Bool
    func release()
}

/// How long the user has gone without touching the mouse or keyboard.
public protocol IdleTimeSource {
    func secondsSinceLastUserInput() -> TimeInterval
}

/// Moves the pointer imperceptibly so macOS registers user activity.
public protocol MouseNudger {
    func nudge()
}

/// Whether the app may post synthetic input events.
public protocol AccessibilityAuthority {
    var isTrusted: Bool { get }
    func promptForAccess()
}

/// Persisted user preferences.
public protocol SettingsStore: AnyObject {
    var nudgeEnabled: Bool { get set }
    /// Turn off when on battery at or below this percentage; 0 means never.
    var batteryThreshold: Int { get set }
    var schedule: Schedule { get set }
    var watchedApps: WatchedApps { get set }
    /// The last time picked in "Turn off at", minutes after midnight; nil if never used.
    var turnOffAtMinute: Int? { get set }
}

/// An app that is running, as far as CursorMov cares.
public struct RunningApp: Equatable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The apps running right now.
public protocol RunningAppsSource {
    func runningApps() -> [RunningApp]
}

/// Battery state, or nil from `BatterySource` on Macs without a battery.
public struct BatteryStatus: Equatable, Sendable {
    public var isOnBattery: Bool
    public var percent: Int

    public init(isOnBattery: Bool, percent: Int) {
        self.isOnBattery = isOnBattery
        self.percent = percent
    }
}

public protocol BatterySource {
    func status() -> BatteryStatus?
}
