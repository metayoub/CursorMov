import Foundation
import ServiceManagement

public protocol LoginItemControlling {
    var isEnabled: Bool { get }
    /// Registered, but the user has switched it off in Login Items settings.
    var needsApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    func openSettings()
}

/// "Start when I log in", backed by macOS's own login items list.
public struct LoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
