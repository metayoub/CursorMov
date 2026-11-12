import Foundation

/// The app's core: switches keep-awake on and off and reports its status.
@MainActor public final class KeepAwakeController {
    public static let tickInterval: TimeInterval = 15
    public static let nudgeIdleThreshold: TimeInterval = 60

    /// Why the controller last switched itself off.
    private enum AutoOffReason {
        case lowBattery(threshold: Int)
    }

    /// Why the current session is on.
    private enum SessionKind {
        /// Left-click: until switched off.
        case manual
        /// "Keep awake for": until `endsAt`.
        case timed
        /// The schedule: until the window's end, `endsAt`.
        case scheduled
        /// A watched app is open: until the last one quits.
        case apps
    }

    public private(set) var isOn = false
    public private(set) var onSince: Date?
    /// When a timed or scheduled session ends; nil otherwise.
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
            if kind == .scheduled {
                // Follow the new window, or end if now falls outside it.
                if let window = newValue.window(containing: now(), calendar: calendar) {
                    endsAt = window.end
                } else {
                    endSession()
                    // The schedule ended it, not the user: the new window may still start it.
                    handledWindow = nil
                }
            }
            refresh()
        }
    }

    /// Stays on while any of these apps is open. Changes apply right away.
    public var watchedApps: WatchedApps {
        get { settings.watchedApps }
        set {
            settings.watchedApps = newValue
            if kind == .apps && openWatchedApps().isEmpty { endSession() }
            refresh()
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
    private let runningApps: RunningAppsSource
    private let now: () -> Date
    private let clockFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    private var hasPromptedForAccess = false
    private var wasBatteryLow = false
    private var autoOffReason: AutoOffReason?
    private var kind: SessionKind?
    /// The last window the schedule acted on. Each window is used once, so stopping
    /// during it keeps the Mac off until the next one, even if the times are edited.
    private var handledWindow: Schedule.Window?
    /// A window the user (or low battery) switched off during; the schedule won't
    /// take over a session in it.
    private var stoppedWindow: Schedule.Window?
    /// Switched off by hand while a watched app was open: apps can't turn it on
    /// again until the user does.
    private var appsPaused = false

    public init(assertion: KeepAwakeAssertion, idle: IdleTimeSource, nudger: MouseNudger,
                accessibility: AccessibilityAuthority, settings: SettingsStore,
                battery: BatterySource, runningApps: RunningAppsSource, now: @escaping () -> Date = Date.init,
                timeZone: TimeZone = .autoupdatingCurrent) {
        self.assertion = assertion
        self.idle = idle
        self.nudger = nudger
        self.accessibility = accessibility
        self.settings = settings
        self.battery = battery
        self.runningApps = runningApps
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

    /// Stays on until switched off, or, if a watched app is open, until the last one quits.
    public func turnOn() {
        appsPaused = false
        guard !isOn else { return }
        start(openWatchedApps().isEmpty ? .manual : .apps, endsAt: nil)
    }

    /// Stays on for `duration` seconds, restarting the timer if already on.
    public func turnOn(for duration: TimeInterval) {
        appsPaused = false
        start(.timed, endsAt: now().addingTimeInterval(duration))
    }

    /// Switched off by the user: it stays off until they turn it on again
    /// (for watched apps) or until the next scheduled window.
    public func turnOff() {
        guard isOn else { return }
        if !openWatchedApps().isEmpty { appsPaused = true }
        markScheduleStopped()
        stop()
    }

    /// Re-checks the schedule and watched apps, e.g. when an app launches or quits.
    public func refresh() {
        if isOn, let endsAt, now() >= endsAt { endSession() }
        if kind == .apps && openWatchedApps().isEmpty { endSession() }
        applySchedule()
        applyWatchedApps()
    }

    /// Called every `tickInterval` seconds.
    public func tick() {
        refresh()
        guard isOn else { return }
        let batteryLow = isBatteryLow()
        defer { wasBatteryLow = batteryLow }
        if batteryLow && !wasBatteryLow {
            markScheduleStopped()
            stop()
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
        if kind == .apps, let open = WatchedApps.openPhrase(openWatchedApps().map(\.name)) {
            return "Keeping Mac awake · \(open)"
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
        guard !isBatteryLow(), start(.scheduled, endsAt: window.end) else { return }
        handledWindow = window
    }

    /// Turns on while a watched app is open, unless the user switched it off.
    private func applyWatchedApps() {
        guard !isOn, !appsPaused, !openWatchedApps().isEmpty, !isBatteryLow() else { return }
        start(.apps, endsAt: nil)
    }

    /// The reason that ended has gone; stay on if another one holds ("on wins").
    private func endSession() {
        if !appsPaused && !openWatchedApps().isEmpty {
            kind = .apps
            endsAt = nil
        } else if let window = schedule.window(containing: now(), calendar: calendar),
                  !overlaps(window, stoppedWindow) {
            kind = .scheduled
            endsAt = window.end
            handledWindow = window
        } else {
            stop()
        }
    }

    /// Starts a session, or switches the running one to `kind`. False if macOS refused.
    @discardableResult
    private func start(_ kind: SessionKind, endsAt: Date?) -> Bool {
        if !isOn {
            guard assertion.acquire() else { return false }
            isOn = true
            onSince = now()
            autoOffReason = nil
            // Only a drop to the threshold during this session switches it off;
            // if it's already low, the user chose to turn it on anyway.
            wasBatteryLow = isBatteryLow()
            requestAccessIfNeeded()
            onStateChange?(true)
        }
        self.kind = kind
        self.endsAt = endsAt
        return true
    }

    private func stop() {
        guard isOn else { return }
        assertion.release()
        isOn = false
        onSince = nil
        endsAt = nil
        kind = nil
        onStateChange?(false)
    }

    /// Stopping during a window keeps the schedule off for the rest of it.
    private func markScheduleStopped() {
        guard let window = schedule.window(containing: now(), calendar: calendar) else { return }
        stoppedWindow = window
        handledWindow = window
    }

    private func overlaps(_ a: Schedule.Window, _ b: Schedule.Window?) -> Bool {
        guard let b else { return false }
        return a.start < b.end && b.start < a.end
    }

    private func openWatchedApps() -> [RunningApp] {
        watchedApps.running(in: runningApps.runningApps())
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
