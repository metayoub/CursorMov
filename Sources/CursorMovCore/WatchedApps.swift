import Foundation

/// Keep the Mac awake while any of these apps is running.
public struct WatchedApps: Equatable, Sendable {
    public var isEnabled: Bool
    /// Bundle identifiers, in the order they were chosen.
    public var bundleIDs: [String]

    public init(isEnabled: Bool, bundleIDs: [String]) {
        self.isEnabled = isEnabled
        self.bundleIDs = bundleIDs
    }

    /// Off, no apps chosen.
    public static let standard = WatchedApps(isEnabled: false, bundleIDs: [])

    /// Adds the app if it isn't chosen, removes it if it is.
    public mutating func toggle(_ bundleID: String) {
        if let index = bundleIDs.firstIndex(of: bundleID) {
            bundleIDs.remove(at: index)
        } else {
            bundleIDs.append(bundleID)
        }
    }

    /// The chosen apps among `running`, in the order they were chosen.
    public func running(in running: [RunningApp]) -> [RunningApp] {
        guard isEnabled else { return [] }
        return bundleIDs.compactMap { id in running.first { $0.bundleID == id } }
    }

    /// For the status line: "Cursor is open", "Cursor and Code are open", "Cursor and 2 more are open".
    public static func openPhrase(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) is open"
        case 2: return "\(names[0]) and \(names[1]) are open"
        default: return "\(names[0]) and \(names.count - 1) more are open"
        }
    }
}
