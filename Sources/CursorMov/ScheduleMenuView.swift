import AppKit
import CursorMovCore

/// The controls inside the "Schedule" submenu: an on/off switch, From/To times, and weekdays.
@MainActor final class ScheduleMenuView: NSView {
    /// Segment order, Monday first, as `Calendar` weekdays (1 is Sunday).
    private static let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private static let dayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    private var schedule: Schedule
    private let onChange: (Schedule) -> Void
    private let enabledSwitch = NSSwitch()
    private let fromPicker = ScheduleMenuView.makeTimePicker()
    private let toPicker = ScheduleMenuView.makeTimePicker()
    private let days = NSSegmentedControl(labels: ScheduleMenuView.dayLabels, trackingMode: .selectAny,
                                          target: nil, action: nil)

    init(schedule: Schedule, onChange: @escaping (Schedule) -> Void) {
        self.schedule = schedule
        self.onChange = onChange
        super.init(frame: .zero)

        enabledSwitch.controlSize = .small
        enabledSwitch.state = schedule.isEnabled ? .on : .off
        fromPicker.dateValue = Self.date(minute: schedule.startMinute)
        toPicker.dateValue = Self.date(minute: schedule.endMinute)
        for (index, weekday) in Self.weekdays.enumerated() {
            days.setSelected(schedule.weekdays.contains(weekday), forSegment: index)
        }
        days.segmentDistribution = .fillEqually
        days.selectedSegmentBezelColor = .controlAccentColor
        for control in [enabledSwitch, fromPicker, toPicker, days] as [NSControl] {
            control.target = self
            control.action = #selector(controlChanged)
        }

        let title = NSTextField(labelWithString: "Schedule")
        title.font = .menuFont(ofSize: 0)
        let header = NSStackView(views: [title, NSView(), enabledSwitch])
        let times = NSStackView(views: [Self.label("From"), fromPicker, NSView(), Self.label("To"), toPicker])
        let stack = NSStackView(views: [header, times, days])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        for row in [header, times, days] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 290),
        ])
        frame.size = fittingSize
        updateEnabled()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func controlChanged() {
        schedule.isEnabled = enabledSwitch.state == .on
        schedule.startMinute = Self.minute(of: fromPicker.dateValue)
        schedule.endMinute = Self.minute(of: toPicker.dateValue)
        schedule.weekdays = Set(Self.weekdays.indices.filter { days.isSelected(forSegment: $0) }
            .map { Self.weekdays[$0] })
        updateEnabled()
        onChange(schedule)
    }

    /// Times and days stay editable when off, but look secondary.
    private func updateEnabled() {
        let alpha: CGFloat = schedule.isEnabled ? 1 : 0.5
        for view in [fromPicker, toPicker, days] as [NSView] { view.alphaValue = alpha }
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func makeTimePicker() -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.isBordered = false
        picker.isBezeled = true
        // 24-hour clock, like the status line.
        picker.locale = Locale(identifier: "en_GB")
        return picker
    }

    private static func date(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date())
            ?? Date()
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
