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
}
