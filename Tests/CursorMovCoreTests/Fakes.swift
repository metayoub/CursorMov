import Foundation
@testable import CursorMovCore

final class FakeAssertion: KeepAwakeAssertion {
    var acquireResult = true
    var acquireCount = 0
    var releaseCount = 0
    func acquire() -> Bool { acquireCount += 1; return acquireResult }
    func release() { releaseCount += 1 }
}

final class FakeIdle: IdleTimeSource {
    var seconds: TimeInterval = 0
    func secondsSinceLastUserInput() -> TimeInterval { seconds }
}

final class FakeNudger: MouseNudger {
    var nudgeCount = 0
    func nudge() { nudgeCount += 1 }
}

final class FakeAccessibility: AccessibilityAuthority {
    var isTrusted = true
    var promptCount = 0
    func promptForAccess() { promptCount += 1 }
}

final class FakeSettings: SettingsStore {
    var nudgeEnabled = true
    var batteryThreshold = 20
    var schedule = Schedule.standard
    var watchedApps = WatchedApps.standard
    var turnOffAtMinute: Int?
}

final class FakeRunningApps: RunningAppsSource {
    var apps: [RunningApp] = []
    func runningApps() -> [RunningApp] { apps }
}

final class FakeBattery: BatterySource {
    var current: BatteryStatus? = BatteryStatus(isOnBattery: false, percent: 100)
    func status() -> BatteryStatus? { current }
}

final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

struct Harness {
    let assertion = FakeAssertion()
    let idle = FakeIdle()
    let nudger = FakeNudger()
    let accessibility = FakeAccessibility()
    let settings = FakeSettings()
    let clock = FakeClock()
    let battery = FakeBattery()
    let runningApps = FakeRunningApps()

    @MainActor func makeController() -> KeepAwakeController {
        let clock = self.clock
        return KeepAwakeController(
            assertion: assertion, idle: idle, nudger: nudger,
            accessibility: accessibility, settings: settings, battery: battery,
            runningApps: runningApps,
            now: { clock.now }, timeZone: TimeZone(identifier: "UTC")!)
    }
}
