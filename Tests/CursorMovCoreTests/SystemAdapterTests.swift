import Foundation
import IOKit.pwr_mgt
import Testing
@testable import CursorMovCore

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "CursorMovTests-\(UUID().uuidString)")!
}

/// Names of the power assertions this test process currently holds.
private func ourAssertionNames() -> [String] {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
          let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
          let ours = dict[NSNumber(value: getpid())] else { return [] }
    return ours.compactMap { $0[kIOPMAssertionNameKey] as? String }
}

@Test func settingsDefaultNudgeOn() {
    #expect(UserDefaultsSettings(defaults: freshDefaults()).nudgeEnabled == true)
}

@Test func settingsPersistNudge() {
    let defaults = freshDefaults()
    UserDefaultsSettings(defaults: defaults).nudgeEnabled = false
    #expect(UserDefaultsSettings(defaults: defaults).nudgeEnabled == false)
}

@Test func settingsDefaultBatteryThreshold20() {
    #expect(UserDefaultsSettings(defaults: freshDefaults()).batteryThreshold == 20)
}

@Test func settingsPersistBatteryThreshold() {
    let defaults = freshDefaults()
    UserDefaultsSettings(defaults: defaults).batteryThreshold = 0
    #expect(UserDefaultsSettings(defaults: defaults).batteryThreshold == 0)
}

@Test func systemBatteryReadsSanePercent() {
    if let status = SystemBattery().status() {
        #expect((0...100).contains(status.percent))
    }
}

@Test func powerAssertionAppearsAndClears() {
    let assertion = PowerAssertion()
    #expect(assertion.acquire())
    #expect(ourAssertionNames().contains(PowerAssertion.name))
    assertion.release()
    #expect(!ourAssertionNames().contains(PowerAssertion.name))
    assertion.release()
}

@Test func idleTimeIsNonNegative() {
    #expect(SystemIdleTime().secondsSinceLastUserInput() >= 0)
}
