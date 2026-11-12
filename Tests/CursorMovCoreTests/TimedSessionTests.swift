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

/// Between the end time and the next tick, don't claim "0m left".
@MainActor @Test func statusSaysEndingOncePastEnd() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    h.clock.now += 3605
    #expect(c.statusText() == "Keeping Mac awake · ending")
}

// MARK: - Turn off at

@MainActor @Test func turnOffAtLaterTodayEndsToday() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(untilMinuteOfDay: 15 * 60 + 10) // now is 13:46:40
    #expect(c.isOn)
    #expect(c.endsAt == Date(timeIntervalSince1970: TimeInterval((11 * 24 + 15) * 3600 + 600)))
    #expect(c.statusText() == "Keeping Mac awake · 1h 24m left · until 15:10")
}

@MainActor @Test func turnOffAtPastTimeMeansTomorrow() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(untilMinuteOfDay: 13 * 60 + 10)
    #expect(c.endsAt == Date(timeIntervalSince1970: TimeInterval((12 * 24 + 13) * 3600 + 600)))
}

@MainActor @Test func turnOffAtReplacesTimerAndViceVersa() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(for: 3600)
    c.turnOn(untilMinuteOfDay: 14 * 60)
    #expect(c.statusText() == "Keeping Mac awake · 14m left · until 14:00")
    c.turnOn(for: 1800)
    #expect(c.endsAt == h.clock.now + 1800)
    #expect(h.assertion.acquireCount == 1)
}

@MainActor @Test func turnOffAtTurnsOffWhenReached() {
    let h = Harness()
    let c = h.makeController()
    c.turnOn(untilMinuteOfDay: 14 * 60)
    h.clock.now = Date(timeIntervalSince1970: TimeInterval((11 * 24 + 14) * 3600))
    c.tick()
    #expect(c.isOn == false)
}

@MainActor @Test func suggestedTurnOffMinuteIsNextHourThenLastUsed() {
    let h = Harness()
    let c = h.makeController()
    #expect(c.suggestedTurnOffMinute == 14 * 60)
    c.turnOn(untilMinuteOfDay: 13 * 60 + 10)
    #expect(c.suggestedTurnOffMinute == 13 * 60 + 10)
}

@Test func settingsStoreTurnOffAt() {
    let defaults = UserDefaults(suiteName: "CursorMovTests-\(UUID().uuidString)")!
    #expect(UserDefaultsSettings(defaults: defaults).turnOffAtMinute == nil)
    UserDefaultsSettings(defaults: defaults).turnOffAtMinute = 790
    #expect(UserDefaultsSettings(defaults: defaults).turnOffAtMinute == 790)
}
