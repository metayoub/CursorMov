import AppKit
import CursorMovCore

/// The coffee cup in the menu bar: left-click toggles, right-click opens the menu.
@MainActor final class StatusItemController: NSObject {
    private static let offSymbol = "cup.and.saucer"
    private static let onSymbol = "cup.and.heat.waves.fill"

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
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: controller.statusText())
        image?.isTemplate = true
        button.image = image
        button.toolTip = "CursorMov — \(controller.statusText())"
    }

    private func showMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: controller.statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(item("Nudge mouse", #selector(toggleNudge), checked: controller.nudgeEnabled))
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

    @objc private func toggleNudge() {
        controller.nudgeEnabled.toggle()
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItem.setEnabled(!loginItem.isEnabled)
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
