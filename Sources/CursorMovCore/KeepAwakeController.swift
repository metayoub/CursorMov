import Foundation

/// The app's core: switches keep-awake on and off and reports its status.
@MainActor public final class KeepAwakeController {
    public static let tickInterval: TimeInterval = 15
    public static let nudgeIdleThreshold: TimeInterval = 60

    /// Why the controller last switched itself off.
    private enum AutoOffReason {
        case lowBattery(threshold: Int)
    }

    public private(set) var isOn = false
    public private(set) var onSince: Date?
    /// When a timed session ends; nil when it stays on until switched off.
    public private(set) var endsAt: Date?
    /// Fired after `isOn` changes.
    public var onStateChange: ((Bool) -> Void)?

    public var nudgeEnabled: Bool {
        get { settings.nudgeEnabled }
        set {
            settings.nudgeEnabled = newValue
            if isOn { requestAccessIfNeeded() }
        }
    }

    /// Turn off when on battery at or below this percentage; 0 means never.
    public var batteryThreshold: Int {
        get { settings.batteryThreshold }
        set {
            settings.batteryThreshold = newValue
            // A new setting isn't a drop: only switch off if it falls further.
            if isOn { wasBatteryLow = isBatteryLow() }
        }
    }

    /// The nudge is wanted but macOS hasn't granted Accessibility.
    public var needsAccessibility: Bool {
        nudgeEnabled && !accessibility.isTrusted
    }

    private let assertion: KeepAwakeAssertion
    private let idle: IdleTimeSource
    private let nudger: MouseNudger
    private let accessibility: AccessibilityAuthority
    private let settings: SettingsStore
    private let battery: BatterySource
    private let now: () -> Date
    private let clockFormatter: DateFormatter
    private var hasPromptedForAccess = false
    private var wasBatteryLow = false
    private var autoOffReason: AutoOffReason?

    public init(assertion: KeepAwakeAssertion, idle: IdleTimeSource, nudger: MouseNudger,
                accessibility: AccessibilityAuthority, settings: SettingsStore,
                battery: BatterySource, now: @escaping () -> Date = Date.init,
                timeZone: TimeZone = .autoupdatingCurrent) {
        self.assertion = assertion
        self.idle = idle
        self.nudger = nudger
        self.accessibility = accessibility
        self.settings = settings
        self.battery = battery
        self.now = now
        clockFormatter = DateFormatter()
        clockFormatter.locale = Locale(identifier: "en_US_POSIX")
        clockFormatter.dateFormat = "HH:mm"
        clockFormatter.timeZone = timeZone
    }

    public func toggle() {
        isOn ? turnOff() : turnOn()
    }

    /// Stays on until switched off.
    public func turnOn() {
        guard !isOn, assertion.acquire() else { return }
        isOn = true
        onSince = now()
        endsAt = nil
        autoOffReason = nil
        // Only a drop to the threshold during this session switches it off;
        // if it's already low, the user chose to turn it on anyway.
        wasBatteryLow = isBatteryLow()
        requestAccessIfNeeded()
        onStateChange?(true)
    }

    /// Stays on for `duration` seconds, restarting the timer if already on.
    public func turnOn(for duration: TimeInterval) {
        turnOn()
        guard isOn else { return }
        endsAt = now().addingTimeInterval(duration)
    }

    public func turnOff() {
        guard isOn else { return }
        assertion.release()
        isOn = false
        onSince = nil
        endsAt = nil
        onStateChange?(false)
    }

    /// Called every `tickInterval` seconds.
    public func tick() {
        guard isOn else { return }
        if let endsAt, now() >= endsAt {
            turnOff()
            return
        }
        let batteryLow = isBatteryLow()
        defer { wasBatteryLow = batteryLow }
        if batteryLow && !wasBatteryLow {
            turnOff()
            autoOffReason = .lowBattery(threshold: batteryThreshold)
            return
        }
        guard nudgeEnabled, accessibility.isTrusted,
              idle.secondsSinceLastUserInput() >= Self.nudgeIdleThreshold else { return }
        nudger.nudge()
    }

    public func statusText() -> String {
        guard isOn, let onSince else {
            if case .lowBattery(let threshold) = autoOffReason {
                return "Off · battery dropped to \(threshold)%"
            }
            return "Off"
        }
        guard let endsAt else {
            return "Keeping Mac awake · \(formatElapsed(now().timeIntervalSince(onSince)))"
        }
        let secondsLeft = (endsAt.timeIntervalSince(now()) / 60).rounded(.up) * 60
        // The next tick switches it off; until then don't claim "0m left".
        guard secondsLeft > 0 else { return "Keeping Mac awake · ending" }
        return "Keeping Mac awake · \(formatElapsed(secondsLeft)) left · until \(clockFormatter.string(from: endsAt))"
    }

    private func isBatteryLow() -> Bool {
        guard batteryThreshold > 0, let status = battery.status() else { return false }
        return status.isOnBattery && status.percent <= batteryThreshold
    }

    /// The nudge needs Accessibility; ask once per run, and only when it would be used.
    private func requestAccessIfNeeded() {
        guard needsAccessibility, !hasPromptedForAccess else { return }
        hasPromptedForAccess = true
        accessibility.promptForAccess()
    }
}
