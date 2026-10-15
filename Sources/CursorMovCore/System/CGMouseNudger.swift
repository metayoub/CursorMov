import CoreGraphics
import Foundation

/// Posts a real mouse-moved event one pixel over and straight back, so macOS
/// counts it as user activity. Requires Accessibility permission.
public struct CGMouseNudger: MouseNudger {
    public init() {}

    public func nudge() {
        guard let start = CGEvent(source: nil)?.location,
              let target = Self.target(from: start, displays: Self.activeDisplayBounds()) else { return }
        Self.postMove(to: target)
        Self.postMove(to: start)
    }

    /// Where to move the pointer before moving it back, or nil to skip the nudge.
    /// Corners are skipped: moving back into one can re-trigger a Hot Corner
    /// such as Lock Screen. The power assertion still keeps the Mac awake.
    static func target(from start: CGPoint, displays: [CGRect]) -> CGPoint? {
        if let display = displays.first(where: { $0.contains(start) }) {
            let nearHorizontalEdge = start.x - display.minX < 1 || display.maxX - start.x <= 1
            let nearVerticalEdge = start.y - display.minY < 1 || display.maxY - start.y <= 1
            if nearHorizontalEdge && nearVerticalEdge { return nil }
        }
        let right = CGPoint(x: start.x + 1, y: start.y)
        return displays.contains(where: { $0.contains(right) }) ? right : CGPoint(x: start.x - 1, y: start.y)
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func postMove(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
