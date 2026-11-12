import Foundation

/// The app's core: switches keep-awake on and off and reports its status.
@MainActor public final class KeepAwakeController {
    public static let tickInterval: TimeInterval = 15
    public static let nudgeIdleThreshold: TimeInterval = 60

    /// Why the controller last switched itself off.
    private enum AutoOffReason {
        case lowBattery(threshold: Int)
    }

    /// The ways CursorMov can switch itself off and on. Only one is active at a time.
    public enum Mode: Equatable, Sendable {
        case keepAwakeFor, turnOffAt, schedule, onlyWhile
    }

    /// Why the current session is on.
    private enum SessionKind {
        /// Left-click: until switched off.
        case manual
        /// "Keep awake for" or "Turn off at": until `endsAt`.
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

    /// The mode in charge, shown with a check mark in the menu; nil when none is.
    public var activeMode: Mode? {
        if kind == .timed { return timedByClock ? .turnOffAt : .keepAwakeFor }
        if schedule.isEnabled { return .schedule }
        if watchedApps.isEnabled { return .onlyWhile }
        return nil
    }

    /// Turns on by itself during the scheduled window. Changes apply right away.
    /// Switching it on switches "Only while" off and cancels a timer.
    public var schedule: Schedule {
        get { settings.schedule }
        set {
            let switchedOn = newValue.isEnabled && !settings.schedule.isEnabled
            settings.schedule = newValue
            if switchedOn {
                settings.watchedApps.isEnabled = false
                if kind == .timed || kind == .apps { stop() }
                // A fresh start: take over right away if inside the window.
                handledWindow = nil
            }
            if kind == .scheduled {
                // Follow the new window, or end if now falls outside it.
                if let window = newValue.window(containing: now(), calendar: calendar) {
                    endsAt = window.end
                } else {
                    stop()
                    // The schedule ended it, not the user: the new window may still start it.
                    handledWindow = nil
                }
            }
            refresh()
        }
    }

    /// Stays on while any of these apps is open. Changes apply right away.
    /// Switching it on switches the schedule off and cancels a timer.
    public var watchedApps: WatchedApps {
        get { settings.watchedApps }
        set {
            let switchedOn = newValue.isEnabled && !settings.watchedApps.isEnabled
            settings.watchedApps = newValue
            if switchedOn {
                settings.schedule.isEnabled = false
                if kind == .timed || kind == .scheduled { stop() }
                appsPaused = false
            }
            if kind == .apps && openWatchedApps().isEmpty { stop() }
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
    /// The running timer came from "Turn off at" rather than "Keep awake for".
    private var timedByClock = false
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
    /// Switches the schedule and "Only while" off.
    public func turnOn(for duration: TimeInterval) {
        startTimer(until: now().addingTimeInterval(duration), byClock: false)
    }

    /// Stays on until the next `minuteOfDay` (minutes after midnight): today if it's
    /// still ahead, otherwise tomorrow. Replaces any running timer.
    public func turnOn(untilMinuteOfDay minuteOfDay: Int) {
        settings.turnOffAtMinute = minuteOfDay
        startTimer(until: nextOccurrence(ofMinute: minuteOfDay), byClock: true)
    }

    /// The time "Turn off at" should offer: the last one picked, or the next full hour.
    public var suggestedTurnOffMinute: Int {
        if let last = settings.turnOffAtMinute { return last }
        let hour = calendar.component(.hour, from: now())
        return (hour + 1) % 24 * 60
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
        if isOn, let endsAt, now() >= endsAt { stop() }
        if kind == .apps && openWatchedApps().isEmpty { stop() }
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

    /// Timers replace the schedule and "Only while": only one mode is active at a time.
    private func startTimer(until end: Date, byClock: Bool) {
        settings.schedule.isEnabled = false
        settings.watchedApps.isEnabled = false
        appsPaused = false
        guard start(.timed, endsAt: end) else { return }
        timedByClock = byClock
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
        handledWindow = window
    }

    private func nextOccurrence(ofMinute minuteOfDay: Int) -> Date {
        let today = calendar.startOfDay(for: now())
        let candidate = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                                      second: 0, of: today) ?? now()
        guard candidate <= now() else { return candidate }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                             second: 0, of: tomorrow) ?? now()
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
