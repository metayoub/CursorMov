import AppKit
import CursorMovCore
import UniformTypeIdentifiers

/// The "Only while" submenu: an on/off switch, the chosen apps (ticked), the apps
/// open now (click to add), and "Other app…" for apps that aren't open.
@MainActor final class WatchedAppsMenu: NSObject {
    private let controller: KeepAwakeController

    init(controller: KeepAwakeController) {
        self.controller = controller
    }

    /// The parent item's title, e.g. "Only while · Cursor, Code".
    var title: String {
        let watched = controller.watchedApps
        guard watched.isEnabled else { return "Only while · Off" }
        let names = watched.bundleIDs.map(Self.name(of:))
        switch names.count {
        case 0: return "Only while · No apps"
        case 1, 2: return "Only while · \(names.joined(separator: ", "))"
        default: return "Only while · \(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem()
        toggle.view = SwitchMenuRow(title: "Only while an app is open",
                                    isOn: controller.watchedApps.isEnabled) { [controller] isOn in
            controller.watchedApps.isEnabled = isOn
        }
        menu.addItem(toggle)
        menu.addItem(.separator())

        let chosen = controller.watchedApps.bundleIDs
        let open = SystemRunningApps().runningApps()
        let openIDs = Set(open.map(\.bundleID))
        if !chosen.isEmpty {
            menu.addItem(.sectionHeader(title: "Chosen"))
            for id in chosen {
                let item = appItem(id: id, name: Self.name(of: id))
                item.state = .on
                if openIDs.contains(id) { item.badge = NSMenuItemBadge(string: "open") }
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let others = open.filter { !chosen.contains($0.bundleID) && Self.isListable($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Two copies of an app (e.g. two versions) would list twice; keep one.
        var seen = Set<String>()
        let unique = others.filter { seen.insert($0.bundleID).inserted }
        if !unique.isEmpty {
            menu.addItem(.sectionHeader(title: "Open now"))
            for app in unique { menu.addItem(appItem(id: app.bundleID, name: app.name)) }
            menu.addItem(.separator())
        }

        let other = NSMenuItem(title: "Other app…", action: #selector(chooseOtherApp), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        return menu
    }

    private func appItem(id: String, name: String) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: #selector(toggleApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.image = Self.icon(of: id)
        return item
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.watchedApps.toggle(id)
    }

    @objc private func chooseOtherApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to keep your Mac awake for"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var watched = controller.watchedApps
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !watched.bundleIDs.contains(id) else { continue }
            watched.bundleIDs.append(id)
        }
        controller.watchedApps = watched
    }

    /// Worth offering in "Open now": regular apps, and menu-bar apps that stand on their own,
    /// not macOS agents or helpers tucked inside another app.
    private static func isListable(_ bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return false }
        if app.activationPolicy == .regular { return true }
        guard let path = app.bundleURL?.path, path.hasSuffix(".app"),
              !path.hasPrefix("/System/"), !path.hasPrefix("/Library/Apple/") else { return false }
        return !path.dropLast(4).contains(".app/")
    }

    private static func name(of bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(of bundleID: String) -> NSImage? {
        let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        guard let copy = icon?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

/// A menu row with a title and a switch, like the one at the top of the Schedule submenu.
@MainActor final class SwitchMenuRow: NSView {
    private let onChange: (Bool) -> Void
    private let toggle = NSSwitch()

    init(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = #selector(switched)
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        let row = NSStackView(views: [label, NSView(), toggle])
        row.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 280),
        ])
        frame.size = fittingSize
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func switched() {
        onChange(toggle.state == .on)
    }
}
