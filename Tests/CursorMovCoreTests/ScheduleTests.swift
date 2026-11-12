import Foundation
import Testing
@testable import CursorMovCore

// Clock starts on Monday 1970-01-12 13:46:40 UTC.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Monday 1970-01-12 at `hour`:`minute` UTC, plus `days`.
private func monday(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 1970, month: 1, day: 12 + days, hour: hour, minute: minute))!
}

private func workdays(_ start: Int = 9 * 60, _ end: Int = 17 * 60) -> Schedule {
    Schedule(isEnabled: true, startMinute: start, endMinute: end, weekdays: [2, 3, 4, 5, 6])
}

// MARK: - Schedule

@Test func windowCoversChosenDayBetweenTimes() {
    let window = workdays().window(containing: monday(10), calendar: utc)
    #expect(window == Schedule.Window(start: monday(9), end: monday(17)))
}

@Test func windowExcludesEndTimeAndOtherDays() {
    #expect(workdays().window(containing: monday(17), calendar: utc) == nil)
    #expect(workdays().window(containing: monday(8, 59), calendar: utc) == nil)
    #expect(workdays().window(containing: monday(10, days: 5), calendar: utc) == nil) // Saturday
}

@Test func disabledScheduleHasNoWindow() {
    var schedule = workdays()
    schedule.isEnabled = false
    #expect(schedule.window(containing: monday(10), calendar: utc) == nil)
    #expect(schedule.nextStart(after: monday(8), calendar: utc) == nil)
}

@Test func overnightWindowRunsPastMidnight() {
    let schedule = workdays(22 * 60, 6 * 60)
    let fromMonday = Schedule.Window(start: monday(22), end: monday(6, days: 1))
    #expect(schedule.window(containing: monday(23), calendar: utc) == fromMonday)
    #expect(schedule.window(containing: monday(5, days: 1), calendar: utc) == fromMonday)
    // Friday night's window carries into Saturday morning.
    #expect(schedule.window(containing: monday(5, days: 5), calendar: utc) != nil)
    // Sunday isn't chosen, so Monday morning is free.
    #expect(schedule.window(containing: monday(5), calendar: utc) == nil)
}

@Test func sameStartAndEndIsEmpty() {
    let schedule = workdays(9 * 60, 9 * 60)
    #expect(schedule.window(containing: monday(9), calendar: utc) == nil)
    #expect(schedule.nextStart(after: monday(8), calendar: utc) == nil)
}

@Test func nextStartSkipsToNextChosenDay() {
    #expect(workdays().nextStart(after: monday(8), calendar: utc) == monday(9))
    #expect(workdays().nextStart(after: monday(9), calendar: utc) == monday(9, days: 1))
    // Friday evening → next Monday.
    #expect(workdays().nextStart(after: monday(18, days: 4), calendar: utc) == monday(9, days: 7))
}

@Test func noDaysMeansNoStart() {
    let schedule = Schedule(isEnabled: true, startMinute: 540, endMinute: 1020, weekdays: [])
    #expect(schedule.nextStart(after: monday(8), calendar: utc) == nil)
}

@Test func summaryGroupsDays() {
    #expect(workdays().summary == "Mon–Fri 09:00–17:00")
    #expect(Schedule(isEnabled: true, startMinute: 30, endMinute: 1410, weekdays: [2, 4, 6]).summary
        == "Mon, Wed, Fri 00:30–23:30")
    #expect(Schedule(isEnabled: true, startMinute: 0, endMinute: 60, weekdays: [7, 1]).summary
        == "Sat, Sun 00:00–01:00")
    #expect(Schedule(isEnabled: true, startMinute: 0, endMinute: 60, weekdays: Set(1...7)).summary
        == "Every day 00:00–01:00")
    #expect(Schedule.standard.summary == "Off")
}

@Test func settingsStoreSchedule() {
    let defaults = UserDefaults(suiteName: "CursorMovTests-\(UUID().uuidString)")!
    #expect(UserDefaultsSettings(defaults: defaults).schedule == .standard)
    let custom = Schedule(isEnabled: true, startMinute: 22 * 60, endMinute: 30, weekdays: [1, 7])
    UserDefaultsSettings(defaults: defaults).schedule = custom
    #expect(UserDefaultsSettings(defaults: defaults).schedule == custom)
}

// MARK: - Controller

@MainActor private func scheduled(_ h: Harness, _ schedule: Schedule = workdays()) -> KeepAwakeController {
    h.clock.now = monday(8, 59)
    let c = h.makeController()
    c.schedule = schedule
    return c
}

@MainActor @Test func turnsOnAtStartAndOffAtEnd() {
    let h = Harness()
    let c = scheduled(h)
    c.tick()
    #expect(c.isOn == false)
    h.clock.now = monday(9)
    c.tick()
    #expect(c.isOn)
    #expect(c.endsAt == monday(17))
    #expect(c.statusText() == "Keeping Mac awake · 8h 0m left · until 17:00")
    h.clock.now = monday(17)
    c.tick()
    #expect(c.isOn == false)
    #expect(c.statusText() == "Off · starts tomorrow 09:00")
}

@MainActor @Test func enablingInsideWindowTurnsOnRightAway() {
    let h = Harness()
    h.clock.now = monday(11)
    let c = h.makeController()
    c.schedule = workdays()
    #expect(c.isOn)
    #expect(c.endsAt == monday(17))
}

@MainActor @Test func manualStopStaysOffForRestOfWindow() {
    let h = Harness()
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    h.clock.now = monday(11)
    c.toggle()
    h.clock.now = monday(12)
    c.tick()
    #expect(c.isOn == false)
    // Editing the times doesn't bring it back today.
    c.schedule = workdays(9 * 60 + 5, 18 * 60)
    c.tick()
    #expect(c.isOn == false)
    h.clock.now = monday(9, 5, days: 1)
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func lowBatteryStopStaysOffForRestOfWindow() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 50)
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 20)
    c.tick()
    #expect(c.isOn == false)
    h.battery.current = BatteryStatus(isOnBattery: false, percent: 20)
    c.tick()
    #expect(c.isOn == false)
}

@MainActor @Test func waitsForPowerWhenBatteryIsLowAtStart() {
    let h = Harness()
    h.battery.current = BatteryStatus(isOnBattery: true, percent: 10)
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    #expect(c.isOn == false)
    h.battery.current = BatteryStatus(isOnBattery: false, percent: 10)
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func leavesManualSessionAlone() {
    let h = Harness()
    let c = scheduled(h)
    c.toggle()
    h.clock.now = monday(9)
    c.tick()
    #expect(c.endsAt == nil)
    h.clock.now = monday(17)
    c.tick()
    #expect(c.isOn)
}

@MainActor @Test func manualTimedSessionDuringWindowReplacesSchedule() {
    let h = Harness()
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    c.turnOn(for: 3600)
    #expect(c.endsAt == monday(10))
    c.schedule.isEnabled = false
    #expect(c.isOn)
}

@MainActor @Test func disablingScheduleStopsScheduledSession() {
    let h = Harness()
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    c.schedule.isEnabled = false
    #expect(c.isOn == false)
}

@MainActor @Test func editingTimesMovesScheduledEnd() {
    let h = Harness()
    let c = scheduled(h)
    h.clock.now = monday(9)
    c.tick()
    c.schedule.endMinute = 18 * 60
    #expect(c.isOn)
    #expect(c.endsAt == monday(18))
    c.schedule.startMinute = 10 * 60
    #expect(c.isOn == false)
    h.clock.now = monday(10)
    c.tick()
    #expect(c.isOn)
    #expect(c.endsAt == monday(18))
}

@MainActor @Test func statusNamesDayOfNextStart() {
    let h = Harness()
    let c = scheduled(h)
    #expect(c.statusText() == "Off · starts today 09:00")
    h.clock.now = monday(18, days: 4) // Friday evening
    #expect(c.statusText() == "Off · starts Mon 09:00")
}
