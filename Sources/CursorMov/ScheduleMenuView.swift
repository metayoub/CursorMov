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
    private let fromPicker = TimeStepper()
    private let toPicker = TimeStepper()
    private let days = NSSegmentedControl(labels: ScheduleMenuView.dayLabels, trackingMode: .selectAny,
                                          target: nil, action: nil)

    init(schedule: Schedule, onChange: @escaping (Schedule) -> Void) {
        self.schedule = schedule
        self.onChange = onChange
        super.init(frame: .zero)

        enabledSwitch.controlSize = .small
        enabledSwitch.state = schedule.isEnabled ? .on : .off
        fromPicker.minuteOfDay = schedule.startMinute
        toPicker.minuteOfDay = schedule.endMinute
        for (index, weekday) in Self.weekdays.enumerated() {
            days.setSelected(schedule.weekdays.contains(weekday), forSegment: index)
        }
        days.segmentDistribution = .fillEqually
        days.selectedSegmentBezelColor = .controlAccentColor
        for control in [enabledSwitch, days] as [NSControl] {
            control.target = self
            control.action = #selector(controlChanged)
        }
        for picker in [fromPicker, toPicker] {
            picker.onChange = { [weak self] in self?.controlChanged() }
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
            widthAnchor.constraint(equalToConstant: 340),
        ])
        frame.size = fittingSize
        updateEnabled()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func controlChanged() {
        schedule.isEnabled = enabledSwitch.state == .on
        schedule.startMinute = fromPicker.minuteOfDay
        schedule.endMinute = toPicker.minuteOfDay
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
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }
}

/// A time of day as separate hour and minute boxes, each with its own arrows.
/// (NSDatePicker's single stepper only changes the selected part, and inside a
/// menu the minutes can't be selected.)
@MainActor final class TimeStepper: NSStackView {
    static let minuteStep = 5

    var onChange: (() -> Void)?
    var minuteOfDay: Int {
        get { hourStepper.integerValue * 60 + minuteStepper.integerValue }
        set {
            hourStepper.integerValue = newValue / 60
            minuteStepper.integerValue = newValue % 60
            updateFields()
        }
    }

    private let hourField = TimeStepper.makeField()
    private let minuteField = TimeStepper.makeField()
    private let hourStepper = TimeStepper.makeStepper(max: 23, step: 1)
    private let minuteStepper = TimeStepper.makeStepper(max: 59, step: Double(TimeStepper.minuteStep))

    init() {
        super.init(frame: .zero)
        spacing = 2
        setViews([hourField, hourStepper, minuteField, minuteStepper], in: .leading)
        setCustomSpacing(8, after: hourStepper)
        for stepper in [hourStepper, minuteStepper] {
            stepper.target = self
            stepper.action = #selector(stepped(_:))
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func stepped(_ sender: NSStepper) {
        // Keep minutes on the step grid; wrap 55 → 00 and 00 → 55.
        if sender === minuteStepper {
            let step = Self.minuteStep
            let value = sender.integerValue
            let snapped = value == 59 ? 60 - step : value / step * step
            sender.integerValue = snapped
        }
        updateFields()
        onChange?()
    }

    private func updateFields() {
        hourField.stringValue = String(format: "%02d", hourStepper.integerValue)
        minuteField.stringValue = String(format: "%02d", minuteStepper.integerValue)
    }

    private static func makeField() -> NSTextField {
        let field = NSTextField(string: "00")
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 32).isActive = true
        return field
    }

    private static func makeStepper(max: Double, step: Double) -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = 0
        stepper.maxValue = max
        stepper.increment = step
        stepper.valueWraps = true
        return stepper
    }
}
