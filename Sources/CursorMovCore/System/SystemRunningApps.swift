import AppKit

/// Running apps from NSWorkspace: regular and menu-bar apps, not background helpers.
public struct SystemRunningApps: RunningAppsSource {
    public init() {}

    public func runningApps() -> [RunningApp] {
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited, !app.isTerminated,
                  let id = app.bundleIdentifier, id != ownID else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id)
        }
    }
}
