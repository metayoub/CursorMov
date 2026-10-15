import CoreGraphics
import Foundation

/// Posts a real mouse-moved event one pixel over and straight back, so macOS
/// counts it as user activity. Requires Accessibility permission.
public struct CGMouseNudger: MouseNudger {
    public init() {}

    public func nudge() {
        guard let start = CGEvent(source: nil)?.location else { return }
        let right = CGPoint(x: start.x + 1, y: start.y)
        let target = Self.isOnAnyDisplay(right) ? right : CGPoint(x: start.x - 1, y: start.y)
        Self.postMove(to: target)
        Self.postMove(to: start)
    }

    private static func isOnAnyDisplay(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        return CGGetDisplaysWithPoint(point, 0, nil, &count) == .success && count > 0
    }

    private static func postMove(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
