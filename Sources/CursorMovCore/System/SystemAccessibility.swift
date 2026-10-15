import ApplicationServices
import Foundation

/// Accessibility permission, which macOS requires before an app may post mouse events.
public struct SystemAccessibility: AccessibilityAuthority {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that sends the user to Privacy & Security > Accessibility.
    public func promptForAccess() {
        // Same value as kAXTrustedCheckOptionPrompt, which Swift 6 flags as unsafe global state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
