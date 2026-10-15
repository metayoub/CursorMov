import Foundation
import Testing
@testable import CursorMovCore

// Clock starts at 1970-01-12 13:46:40 UTC.

@MainActor @Test func plainToggleHasNoEnd() {
    let h = Harness()
    let c = h.makeController()
    c.toggle()
    #expect(c.endsAt == nil)
}

@MainActor @Test func turnOnForDurationSetsEnd() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    #expect(c.isOn)
    #expect(c.endsAt == h.clock.now + 3600)
}

@MainActor @Test func turnOnForDurationWhileOnRestartsTimer() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn()
    h.clock.now += 600
    c.turnOn(for: 1800)
    #expect(c.endsAt == h.clock.now + 1800)
    #expect(h.assertion.acquireCount == 1)
}

@MainActor @Test func statusShowsTimeLeftAndEnd() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    h.clock.now += 35 * 60
    #expect(c.statusText() == "Keeping Mac awake · 25m left · until 14:46")
}

@MainActor @Test func timeLeftRoundsUp() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    h.clock.now += 35 * 60 + 30
    #expect(c.statusText() == "Keeping Mac awake · 25m left · until 14:46")
}

@MainActor @Test func timedSessionStaysOnBeforeEnd() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    h.clock.now += 3599
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func timedSessionTurnsOffWhenTimeIsUp() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    h.clock.now += 3600
    c.tick()
    #expect(c.isOn == false)
    #expect(c.endsAt == nil)
    #expect(h.assertion.releaseCount == 1)
    #expect(c.statusText() == "Off")
}

@MainActor @Test func turningOffClearsEnd() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    c.toggle()
    #expect(c.endsAt == nil)
}
