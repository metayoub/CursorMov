import CoreGraphics
import Testing
@testable import CursorMovCore

private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func nudgeMovesRightInTheMiddle() {
    #expect(CGMouseNudger.target(from: CGPoint(x: 500, y: 400), displays: [main]) == CGPoint(x: 501, y: 400))
}

@Test func nudgeMovesLeftAtRightEdge() {
    #expect(CGMouseNudger.target(from: CGPoint(x: 1511, y: 400), displays: [main]) == CGPoint(x: 1510, y: 400))
}

/// Moving back into a corner can re-trigger a Hot Corner such as Lock Screen.
@Test func noNudgeInAnyCorner() {
    for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 1511, y: 0), CGPoint(x: 0, y: 981), CGPoint(x: 1511, y: 981.5)] {
        #expect(CGMouseNudger.target(from: corner, displays: [main]) == nil)
    }
}

@Test func nudgeAtTopEdgeButNotCorner() {
    #expect(CGMouseNudger.target(from: CGPoint(x: 700, y: 0), displays: [main]) == CGPoint(x: 701, y: 0))
}

@Test func nudgeUsesTheDisplayUnderThePointer() {
    let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    // Right edge of the built-in display continues onto the external one.
    #expect(CGMouseNudger.target(from: CGPoint(x: 1511, y: 500), displays: [main, external]) == CGPoint(x: 1512, y: 500))
    // Bottom-right corner of the external display.
    #expect(CGMouseNudger.target(from: CGPoint(x: 3431, y: 1079), displays: [main, external]) == nil)
}
