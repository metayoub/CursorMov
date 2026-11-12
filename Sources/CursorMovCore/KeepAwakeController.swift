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

    /// Turns on by itself during the scheduled window. Changes apply right away.
    public var schedule: Schedule {
        get { settings.schedule }
        set {
            settings.schedule = newValue
            if isScheduledSession {
                // Follow the new window, or stop if now falls outside it.
                if let window = newValue.window(containing: now(), calendar: calendar) {
                    endsAt = window.end
                } else {
                    turnOff()
                    // The schedule stopped it, not the user: the new window may still start it.
                    handledWindow = nil
                }
            }
            applySchedule()
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
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    private var hasPromptedForAccess = false
    private var wasBatteryLow = false
    private var autoOffReason: AutoOffReason?
    /// The current session was started by the schedule.
    private var isScheduledSession = false
    /// The last window the schedule acted on. Each window is used once, so stopping
    /// during it keeps the Mac off until the next one, even if the times are edited.
    private var handledWindow: Schedule.Window?

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
        dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "EEE"
        dayFormatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func toggle() {
        isOn ? turnOff() : turnOn()
    }

    /// Stays on until switched off.
    public func turnOn() {
        isScheduledSession = false
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
        isScheduledSession = false
        onStateChange?(false)
    }

    /// Called every `tickInterval` seconds.
    public func tick() {
        if let endsAt, isOn, now() >= endsAt {
            turnOff()
        }
        applySchedule()
        guard isOn else { return }
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
            if let start = schedule.nextStart(after: now(), calendar: calendar) {
                return "Off · starts \(dayName(start)) \(clockFormatter.string(from: start))"
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

    /// Turns on at the start of a scheduled window, once per window.
    private func applySchedule() {
        guard let window = schedule.window(containing: now(), calendar: calendar) else { return }
        if let handledWindow, handledWindow.start < window.end, window.start < handledWindow.end {
            return
        }
        // A session the user started already covers it; leave it in their hands.
        if isOn {
            handledWindow = window
            return
        }
        // Wait for power rather than start on a low battery; try again next tick.
        guard !isBatteryLow() else { return }
        turnOn()
        guard isOn else { return }
        handledWindow = window
        endsAt = window.end
        isScheduledSession = true
    }

    private func dayName(_ date: Date) -> String {
        let today = calendar.startOfDay(for: now())
        let day = calendar.startOfDay(for: date)
        switch calendar.dateComponents([.day], from: today, to: day).day {
        case 0: return "today"
        case 1: return "tomorrow"
        default: return dayFormatter.string(from: date)
        }
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
