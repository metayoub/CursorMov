import CoreGraphics
import Foundation

/// Seconds since the last mouse, keyboard, or trackpad input in this session.
public struct SystemIdleTime: IdleTimeSource {
    public init() {}

    public func secondsSinceLastUserInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
