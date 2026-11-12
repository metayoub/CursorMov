import AppKit
import CursorMovCore

/// The "Turn off at" submenu: a time and a Start button.
@MainActor final class TurnOffAtMenuView: NSView {
    private let picker = TimeStepper()
    private let onStart: (Int) -> Void

    init(minuteOfDay: Int, onStart: @escaping (Int) -> Void) {
        self.onStart = onStart
        super.init(frame: .zero)
        picker.minuteOfDay = minuteOfDay
        let start = NSButton(title: "Start", target: nil, action: nil)
        start.target = self
        start.action = #selector(startPressed)
        start.bezelStyle = .push
        start.keyEquivalent = "\r"
        let row = NSStackView(views: [picker, NSView(), start])
        row.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 230),
        ])
        frame.size = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func startPressed() {
        onStart(picker.minuteOfDay)
        // Close the whole menu, as clicking a regular item would.
        var menu = enclosingMenuItem?.menu
        while let parent = menu?.supermenu { menu = parent }
        menu?.cancelTracking()
    }
}
