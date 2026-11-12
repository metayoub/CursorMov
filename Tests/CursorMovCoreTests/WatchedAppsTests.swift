import Foundation
import Testing
@testable import CursorMovCore

// Clock starts on Monday 1970-01-12 13:46:40 UTC.

private let cursor = RunningApp(bundleID: "com.todesktop.cursor", name: "Cursor")
private let code = RunningApp(bundleID: "com.microsoft.VSCode", name: "Code")
private let vpn = RunningApp(bundleID: "com.cisco.secureclient", name: "Cisco Secure Client")
private let safari = RunningApp(bundleID: "com.apple.Safari", name: "Safari")

private func watching(_ apps: RunningApp...) -> WatchedApps {
    WatchedApps(isEnabled: true, bundleIDs: apps.map(\.bundleID))
}

@MainActor private func watched(_ h: Harness, _ apps: WatchedApps = watching(cursor, code))
    -> KeepAwakeController {
    let c = h.makeController()
    c.watchedApps = apps
    return c
}

// MARK: - WatchedApps

@Test func toggleAddsAndRemoves() {
    var apps = WatchedApps.standard
    apps.toggle(cursor.bundleID)
    apps.toggle(code.bundleID)
    #expect(apps.bundleIDs == [cursor.bundleID, code.bundleID])
    apps.toggle(cursor.bundleID)
    #expect(apps.bundleIDs == [code.bundleID])
}

@Test func runningKeepsChosenOrderAndNeedsEnabled() {
    var apps = watching(cursor, code)
    #expect(apps.running(in: [safari, code, cursor]) == [cursor, code])
    apps.isEnabled = false
    #expect(apps.running(in: [cursor]).isEmpty)
}

@Test func openPhrase() {
    #expect(WatchedApps.openPhrase([]) == nil)
    #expect(WatchedApps.openPhrase(["Cursor"]) == "Cursor is open")
    #expect(WatchedApps.openPhrase(["Cursor", "Code"]) == "Cursor and Code are open")
    #expect(WatchedApps.openPhrase(["Cursor", "Code", "VPN"]) == "Cursor and 2 more are open")
}

@Test func settingsStoreWatchedApps() {
    let defaults = UserDefaults(suiteName: "CursorMovTests-\(UUID().uuidString)")!
    #expect(UserDefaultsSettings(defaults: defaults).watchedApps == .standard)
    UserDefaultsSettings(defaults: defaults).watchedApps = watching(vpn, cursor)
    #expect(UserDefaultsSettings(defaults: defaults).watchedApps == watching(vpn, cursor))
}

// MARK: - Controller

@MainActor @Test func onWhileWatchedAppOpenOffWhenLastQuits() {
    let h = Harness()
    let c = watched(h)
    #expect(c.isOn == false)
    h.runningApps.apps = [safari, cursor]
    c.refresh()
    #expect(c.isOn)
    #expect(c.statusText() == "Keeping Mac awake · Cursor is open")
    h.runningApps.apps = [cursor, code]
    #expect(c.statusText() == "Keeping Mac awake · Cursor and Code are open")
    h.runningApps.apps = [code]
    c.refresh()
    #expect(c.isOn)
    h.runningApps.apps = [safari]
    c.refresh()
    #expect(c.isOn == false)
}

@MainActor @Test func enablingWhileAppOpenTurnsOnRightAway() {
    let h = Harness()
    h.runningApps.apps = [cursor]
    let c = watched(h)
    #expect(c.isOn)
}

@MainActor @Test func disabledOrUnwatchedAppsDoNothing() {
    let h = Harness()
    h.runningApps.apps = [cursor, safari]
    var apps = watching(code)
    let c = watched(h, apps)
    #expect(c.isOn == false)
    apps = watching(cursor)
    apps.isEnabled = false
    c.watchedApps = apps
    #expect(c.isOn == false)
}

@MainActor @Test func disablingEndsAppSession() {
    let h = Harness()
    h.runningApps.apps = [cursor]
    let c = watched(h)
    c.watchedApps.isEnabled = false
    #expect(c.isOn == false)
}

@MainActor @Test func manualOffStaysOffUntilTurnedOnByHand() {
    let h = Harness()
    h.runningApps.apps = [cursor]
    let c = watched(h)
    c.toggle()
    #expect(c.isOn == false)
    // Quitting and reopening the app doesn't bring it back.
    h.runningApps.apps = []
    c.tick()
    h.runningApps.apps = [cursor]
    c.tick()
    #expect(c.isOn == false)
    // Turning it on by hand resumes the rule: it ends when Cursor quits.
    c.toggle()
    #expect(c.statusText() == "Keeping Mac awake · Cursor is open")
    h.runningApps.apps = []
    c.refresh()
    #expect(c.isOn == false)
}

@MainActor @Test func manualOffWithNoWatchedAppOpenDoesNotPause() {
    let h = Harness()
    let c = watched(h)
    c.toggle()
    c.toggle()
    h.runningApps.apps = [cursor]
    c.refresh()
    #expect(c.isOn)
}

@MainActor @Test func manualSessionKeepsRunningAfterAppQuits() {
    let h = Harness()
    let c = watched(h)
    c.toggle()
    h.runningApps.apps = [cursor]
    c.refresh()
    h.runningApps.apps = []
    c.refresh()
    #expect(c.isOn)
}

@MainActor @Test func lowBatteryStopsAndWaitsForPower() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 50)
    h.runningApps.apps = [cursor]
    let c = watched(h)
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 20)
    c.tick()
    #expect(c.isOn == false)
    c.tick()
    #expect(c.isOn == false)
    h.battery.current = BatteryStatus(isOnBattery: false, percent: 20)
    c.tick()
    #expect(c.isOn)
}

// MARK: - One mode at a time

/// Monday 1970-01-12 at `hour`:00 UTC.
private func monday(_ hour: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval((11 * 24 + hour) * 3600))
}

private let workdays = Schedule(isEnabled: true, startMinute: 9 * 60, endMinute: 17 * 60,
                                weekdays: [2, 3, 4, 5, 6])

@MainActor @Test func activeModeFollowsTheLastChoice() {
    let h = Harness()
    let c = h.makeController()
    #expect(c.activeMode == nil)
    c.schedule = workdays
    #expect(c.activeMode == .schedule)
    c.watchedApps = watching(cursor)
    #expect(c.activeMode == .onlyWhile)
    #expect(c.schedule.isEnabled == false)
    c.turnOn(for: 600)
    #expect(c.activeMode == .keepAwakeFor)
    #expect(c.watchedApps.isEnabled == false)
    c.turnOn(untilMinuteOfDay: 15 * 60)
    #expect(c.activeMode == .turnOffAt)
}

@MainActor @Test func timerSwitchesRulesOffForGood() {
    let h = Harness()
    h.clock.now = monday(10)
    h.runningApps.apps = [cursor]
    let c = watched(h)
    c.turnOn(for: 600)
    #expect(c.schedule.isEnabled == false)
    #expect(c.watchedApps.isEnabled == false)
    h.clock.now += 600
    c.tick()
    #expect(c.isOn == false)
    // Cursor is still open, but "Only while" is off now.
    c.tick()
    #expect(c.isOn == false)
    #expect(c.activeMode == nil)
}

@MainActor @Test func switchingScheduleOnCancelsTimerAndTakesOver() {
    let h = Harness()
    h.clock.now = monday(10)
    let c = h.makeController()
    c.turnOn(for: 600)
    c.schedule = workdays
    #expect(c.isOn)
    #expect(c.endsAt == monday(17))
    #expect(c.activeMode == .schedule)
}

@MainActor @Test func switchingScheduleOnOutsideWindowCancelsTimer() {
    let h = Harness()
    h.clock.now = monday(20)
    let c = h.makeController()
    c.turnOn(for: 600)
    c.schedule = workdays
    #expect(c.isOn == false)
}

@MainActor @Test func switchingScheduleOnEndsAppSession() {
    let h = Harness()
    h.clock.now = monday(20)
    h.runningApps.apps = [cursor]
    let c = watched(h)
    #expect(c.isOn)
    c.schedule = workdays
    #expect(c.watchedApps.isEnabled == false)
    #expect(c.isOn == false)
}

@MainActor @Test func switchingAppsOnEndsScheduledSession() {
    let h = Harness()
    h.clock.now = monday(10)
    let c = h.makeController()
    c.schedule = workdays
    #expect(c.isOn)
    c.watchedApps = watching(cursor)
    #expect(c.schedule.isEnabled == false)
    #expect(c.isOn == false)
    h.runningApps.apps = [cursor]
    c.refresh()
    #expect(c.isOn)
    #expect(c.statusText() == "Keeping Mac awake · Cursor is open")
}

@MainActor @Test func scheduleCanRestartAfterTimerInterruptedIt() {
    let h = Harness()
    h.clock.now = monday(10)
    let c = h.makeController()
    c.schedule = workdays
    c.turnOn(for: 600)
    var schedule = c.schedule
    schedule.isEnabled = true
    c.schedule = schedule
    #expect(c.isOn)
    #expect(c.endsAt == monday(17))
}

@MainActor @Test func editingEnabledScheduleKeepsAppsOff() {
    let h = Harness()
    let c = h.makeController()
    c.schedule = workdays
    c.schedule.endMinute = 18 * 60
    #expect(c.activeMode == .schedule)
    #expect(c.watchedApps.isEnabled == false)
}
