import Foundation
import Testing
@testable import CursorMovCore

@MainActor @Test func startsOff() {
    let h = Harness()
    let c = h.makeController()
    #expect(c.isOn == false)
    #expect(c.onSince == nil)
    #expect(c.statusText() == "Off")
}

@MainActor @Test func toggleTurnsOnAndAcquires() {
    let h = Harness()
    let c = h.makeController()
    c.toggle()
    #expect(c.isOn)
    #expect(h.assertion.acquireCount == 1)
    #expect(c.onSince == h.clock.now)
}

@MainActor @Test func toggleTwiceReleases() {
    let h = Harness()
    let c = h.makeController()
    c.toggle()
    c.toggle()
    #expect(c.isOn == false)
    #expect(h.assertion.releaseCount == 1)
    #expect(c.onSince == nil)
}

@MainActor @Test func turnOnTwiceAcquiresOnce() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    c.turnOn()
    #expect(h.assertion.acquireCount == 1)
}

@MainActor @Test func turnOffWhenOffDoesNothing() {
    let h = Harness()
    let c = h.makeController()
    c.turnOff()
    #expect(h.assertion.releaseCount == 0)
}

@MainActor @Test func failedAcquireStaysOff() {
    let h = Harness()
    h.assertion.acquireResult = false
    let c = h.makeController()
    var changes: [Bool] = []
    c.onStateChange = { changes.append($0) }
    c.turnOn()
    #expect(c.isOn == false)
    #expect(changes.isEmpty)
}

@MainActor @Test func statusTextShowsElapsed() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    h.clock.now += 72 * 60
    #expect(c.statusText() == "Keeping Mac awake · 1h 12m")
}

@MainActor @Test func notifiesStateChanges() {
    let h = Harness()
    let c = h.makeController()
    var changes: [Bool] = []
    c.onStateChange = { changes.append($0) }
    c.toggle()
    c.toggle()
    #expect(changes == [true, false])
}

@MainActor @Test func nudgeEnabledForwardsToSettings() {
    let h = Harness()
    let c = h.makeController()
    c.nudgeEnabled = false
    #expect(h.settings.nudgeEnabled == false)
}
