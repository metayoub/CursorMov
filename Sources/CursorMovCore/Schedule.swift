import Foundation

/// Keep the Mac awake between two times of day on chosen weekdays.
public struct Schedule: Equatable, Sendable {
    /// One stretch of time the schedule covers.
    public struct Window: Equatable, Sendable {
        public var start: Date
        public var end: Date
    }

    public var isEnabled: Bool
    /// Minutes after midnight, 0..<1440.
    public var startMinute: Int
    /// Minutes after midnight, 0..<1440. Earlier than `startMinute` means it runs past midnight.
    public var endMinute: Int
    /// `Calendar` weekdays the window starts on: 1 is Sunday, 7 is Saturday.
    public var weekdays: Set<Int>

    public init(isEnabled: Bool, startMinute: Int, endMinute: Int, weekdays: Set<Int>) {
        self.isEnabled = isEnabled
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
    }

    /// Off, Monday to Friday, 09:00–17:00.
    public static let standard = Schedule(isEnabled: false, startMinute: 9 * 60, endMinute: 17 * 60,
                                          weekdays: [2, 3, 4, 5, 6])

    /// Minutes the window lasts; 0 when start and end are the same.
    private var length: Int {
        (endMinute - startMinute + 1440) % 1440
    }

    /// The window that `date` falls in, if the schedule is on and covers it.
    public func window(containing date: Date, calendar: Calendar) -> Window? {
        guard isEnabled, length > 0 else { return nil }
        // An overnight window may have started yesterday.
        let today = calendar.startOfDay(for: date)
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  let window = window(startingOn: day, calendar: calendar) else { continue }
            if window.start <= date && date < window.end { return window }
        }
        return nil
    }

    /// The first window starting after `date`.
    public func nextStart(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled, length > 0 else { return nil }
        let today = calendar.startOfDay(for: date)
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  let window = window(startingOn: day, calendar: calendar) else { continue }
            if window.start > date { return window.start }
        }
        return nil
    }

    private func window(startingOn day: Date, calendar: Calendar) -> Window? {
        guard weekdays.contains(calendar.component(.weekday, from: day)),
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60,
                                        second: 0, of: day) else { return nil }
        let endDay = endMinute > startMinute ? day : calendar.date(byAdding: .day, value: 1, to: day)
        guard let endDay, let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60,
                                                  second: 0, of: endDay) else { return nil }
        return Window(start: start, end: end)
    }

    /// For the menu, e.g. "Mon–Fri 09:00–17:00".
    public var summary: String {
        guard isEnabled else { return "Off" }
        return "\(daysSummary) \(Self.clock(startMinute))–\(Self.clock(endMinute))"
    }

    private static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
    private static let dayNames = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]

    private var daysSummary: String {
        if weekdays.isEmpty { return "No days" }
        if weekdays.count == 7 { return "Every day" }
        // Group consecutive days, Monday first: [Mon, Tue, Wed], [Fri].
        var runs: [[Int]] = []
        for day in Self.mondayFirst where weekdays.contains(day) {
            if let last = runs.last?.last,
               Self.mondayFirst.firstIndex(of: last)! + 1 == Self.mondayFirst.firstIndex(of: day)! {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.map { run in
            let first = Self.dayNames[run.first!]!
            let last = Self.dayNames[run.last!]!
            switch run.count {
            case 1: return first
            case 2: return "\(first), \(last)"
            default: return "\(first)–\(last)"
            }
        }.joined(separator: ", ")
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
