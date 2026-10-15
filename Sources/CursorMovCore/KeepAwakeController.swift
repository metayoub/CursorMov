import Foundation

/// The app's core: switches keep-awake on and off and reports its status.
@MainActor public final class KeepAwakeController {
    public static let tickInterval: TimeInterval = 60
    public static let nudgeIdleThreshold: TimeInterval = 60

    public private(set) var isOn = false
    public private(set) var onSince: Date?
    /// Fired after `isOn` changes.
    public var onStateChange: ((Bool) -> Void)?

    public var nudgeEnabled: Bool {
        get { settings.nudgeEnabled }
        set {
            settings.nudgeEnabled = newValue
            if isOn { requestAccessIfNeeded() }
        }
    }

    private let assertion: KeepAwakeAssertion
    private let idle: IdleTimeSource
    private let nudger: MouseNudger
    private let accessibility: AccessibilityAuthority
    private let settings: SettingsStore
    private let now: () -> Date
    private var hasPromptedForAccess = false

    public init(assertion: KeepAwakeAssertion, idle: IdleTimeSource, nudger: MouseNudger,
                accessibility: AccessibilityAuthority, settings: SettingsStore,
                now: @escaping () -> Date = Date.init) {
        self.assertion = assertion
        self.idle = idle
        self.nudger = nudger
        self.accessibility = accessibility
        self.settings = settings
        self.now = now
    }

    public func toggle() {
        isOn ? turnOff() : turnOn()
    }

    public func turnOn() {
        guard !isOn, assertion.acquire() else { return }
        isOn = true
        onSince = now()
        requestAccessIfNeeded()
        onStateChange?(true)
    }

    public func turnOff() {
        guard isOn else { return }
        assertion.release()
        isOn = false
        onSince = nil
        onStateChange?(false)
    }

    /// Called every `tickInterval` seconds.
    public func tick() {
        guard isOn, nudgeEnabled, accessibility.isTrusted,
              idle.secondsSinceLastUserInput() >= Self.nudgeIdleThreshold else { return }
        nudger.nudge()
    }

    /// The nudge needs Accessibility; ask once per run, and only when it would be used.
    private func requestAccessIfNeeded() {
        guard nudgeEnabled, !accessibility.isTrusted, !hasPromptedForAccess else { return }
        hasPromptedForAccess = true
        accessibility.promptForAccess()
    }

    public func statusText() -> String {
        guard isOn, let onSince else { return "Off" }
        return "Keeping Mac awake · \(formatElapsed(now().timeIntervalSince(onSince)))"
    }
}
