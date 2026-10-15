import Foundation
import Testing
@testable import CursorMovCore

@MainActor @Test func lowBatteryTurnsOff() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 25)
    let c = h.makeController()
    c.turnOn()
    c.tick()
    #expect(c.isOn)
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 20)
    c.tick()
    #expect(c.isOn == false)
    #expect(h.assertion.releaseCount == 1)
    #expect(c.statusText() == "Off · battery dropped to 20%")
}

@MainActor @Test func unpluggingWhileLowTurnsOff() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: false, percent: 15)
    let c = h.makeController()
    c.turnOn()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 15)
    c.tick()
    #expect(c.isOn == false)
}

@MainActor @Test func noAutoOffOnCharger() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: false, percent: 5)
    let c = h.makeController()
    c.turnOn()
    c.tick()
    #expect(c.isOn)
}

/// The user chose to turn it on while already low, so respect that.
@MainActor @Test func alreadyLowWhenTurnedOnStaysOn() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 15)
    let c = h.makeController()
    c.turnOn()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 12)
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func neverThresholdDoesNothing() {
    let h = Harness()
    h.settings.batteryThreshold = 0
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 50)
    let c = h.makeController()
    c.turnOn()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 1)
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func noBatteryDoesNothing() {
    let h = Harness()
    h.battery.current = nil
    let c = h.makeController()
    c.turnOn()
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func turningOnClearsBatteryReason() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 25)
    let c = h.makeController()
    c.turnOn()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 20)
    c.tick()
    c.turnOn()
    #expect(c.statusText().hasPrefix("Keeping Mac awake"))
    c.turnOff()
    #expect(c.statusText() == "Off")
}

@MainActor @Test func batteryThresholdForwardsToSettings() {
    let h = Harness()
    let c = h.makeController()
    c.batteryThreshold = 30
    #expect(h.settings.batteryThreshold == 30)
}

@MainActor @Test func needsAccessibilityWhenNudgeOnAndUntrusted() {
    let h = Harness()
    h.accessibility.isTrusted = false
    let c = h.makeController()
    #expect(c.needsAccessibility)
    c.nudgeEnabled = false
    #expect(c.needsAccessibility == false)
}

@MainActor @Test func noAccessibilityNeededWhenTrusted() {
    let h = Harness()
    let c = h.makeController()
    #expect(c.needsAccessibility == false)
}

/// Raising the threshold above the current level is a setting change, not a drop.
@MainActor @Test func raisingThresholdMidSessionStaysOn() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 25)
    let c = h.makeController()
    c.turnOn()
    c.batteryThreshold = 30
    c.tick()
    #expect(c.isOn)
}
