import Foundation
import Testing
@testable import CursorMovCore

@MainActor @Test func tickNudgesWhenIdle() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    h.idle.seconds = 60
    c.tick()
    #expect(h.nudger.nudgeCount == 1)
}

@MainActor @Test func tickDoesNotNudgeWhenUserRecentlyActive() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    h.idle.seconds = 59
    c.tick()
    #expect(h.nudger.nudgeCount == 0)
}

@MainActor @Test func tickDoesNothingWhenOff() {
    let h = Harness()
    let c = h.makeController()
    h.idle.seconds = 600
    c.tick()
    #expect(h.nudger.nudgeCount == 0)
}

@MainActor @Test func disablingNudgeStopsNudging() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    h.idle.seconds = 600
    c.tick()
    c.nudgeEnabled = false
    c.tick()
    #expect(h.nudger.nudgeCount == 1)
}

@MainActor @Test func untrustedSkipsNudgeButStaysOn() {
    let h = Harness()
    h.accessibility.isTrusted = false
    let c = h.makeController()
    c.turnOn()
    h.idle.seconds = 600
    c.tick()
    #expect(h.nudger.nudgeCount == 0)
    #expect(c.isOn)
}

@MainActor @Test func promptsForAccessAtMostOnce() {
    let h = Harness()
    h.accessibility.isTrusted = false
    let c = h.makeController()
    c.turnOn()
    c.turnOff()
    c.turnOn()
    c.nudgeEnabled = false
    c.nudgeEnabled = true
    #expect(h.accessibility.promptCount == 1)
}

@MainActor @Test func promptsWhenEnablingNudgeWhileOn() {
    let h = Harness()
    h.accessibility.isTrusted = false
    h.settings.nudgeEnabled = false
    let c = h.makeController()
    c.turnOn()
    c.nudgeEnabled = true
    #expect(h.accessibility.promptCount == 1)
}

@MainActor @Test func noPromptWhenNudgeDisabled() {
    let h = Harness()
    h.accessibility.isTrusted = false
    h.settings.nudgeEnabled = false
    let c = h.makeController()
    c.turnOn()
    #expect(h.accessibility.promptCount == 0)
}

@MainActor @Test func noPromptWhenTrusted() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    #expect(h.accessibility.promptCount == 0)
}

/// Ticks must be frequent enough that an idle user is nudged roughly once a
/// minute, not every other tick when tick and threshold line up.
@Test @MainActor func idleUserIsNudgedWithinSeventyFiveSeconds() {
    let worstCase = KeepAwakeController.nudgeIdleThreshold + KeepAwakeController.tickInterval
    #expect(worstCase <= 75)
}
