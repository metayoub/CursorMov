import AppKit
import CursorMovCore

/// The coffee cup in the menu bar: left-click toggles, right-click opens the menu.
@MainActor final class StatusItemController: NSObject {
    private static let offSymbol = "cup.and.saucer"
    private static let onSymbol = "cup.and.heat.waves.fill"
    private static let accessibilitySettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let durations: [(title: String, seconds: TimeInterval)] = [
        ("15 minutes", 15 * 60), ("30 minutes", 30 * 60), ("1 hour", 3600),
        ("2 hours", 2 * 3600), ("4 hours", 4 * 3600),
    ]
    private static let batteryThresholds = [0, 10, 20, 30]

    private let controller: KeepAwakeController
    private let loginItem: LoginItemControlling
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(controller: KeepAwakeController, loginItem: LoginItemControlling) {
        self.controller = controller
        self.loginItem = loginItem
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        controller.onStateChange = { [weak self] _ in self?.updateIcon() }
        updateIcon()
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            controller.toggle()
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol = controller.isOn ? Self.onSymbol : Self.offSymbol
        let state = controller.isOn ? "On" : "Off"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CursorMov \(state)")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "CursorMov — \(state)"
    }

    private func showMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: controller.statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if controller.needsAccessibility {
            menu.addItem(item("⚠︎ Allow mouse nudge in Accessibility…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        let keepAwakeFor = NSMenu()
        for (index, duration) in Self.durations.enumerated() {
            let entry = item(duration.title, #selector(keepAwakeForDuration(_:)))
            entry.tag = index
            keepAwakeFor.addItem(entry)
        }
        menu.addItem(submenu("Keep awake for", keepAwakeFor))
        menu.addItem(.separator())

        menu.addItem(item("Nudge mouse", #selector(toggleNudge), checked: controller.nudgeEnabled))
        let battery = NSMenu()
        for threshold in Self.batteryThresholds {
            let entry = item(threshold == 0 ? "Never" : "\(threshold)%", #selector(setBatteryThreshold(_:)),
                             checked: controller.batteryThreshold == threshold)
            entry.tag = threshold
            battery.addItem(entry)
        }
        menu.addItem(submenu("Turn off below battery", battery))
        menu.addItem(item("Start when I log in", #selector(toggleLoginItem), checked: loginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))

        // Attach the menu only for this click so a left-click keeps toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func keepAwakeForDuration(_ sender: NSMenuItem) {
        controller.turnOn(for: Self.durations[sender.tag].seconds)
    }

    @objc private func toggleNudge() {
        controller.nudgeEnabled.toggle()
    }

    @objc private func setBatteryThreshold(_ sender: NSMenuItem) {
        controller.batteryThreshold = sender.tag
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettings)
    }

    @objc private func toggleLoginItem() {
        if loginItem.needsApproval {
            loginItem.openSettings()
            return
        }
        do {
            try loginItem.setEnabled(!loginItem.isEnabled)
            if loginItem.needsApproval { loginItem.openSettings() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change “Start when I log in”"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
