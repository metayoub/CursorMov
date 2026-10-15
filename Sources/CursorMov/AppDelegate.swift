import AppKit
import CursorMovCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = KeepAwakeController(
        assertion: PowerAssertion(),
        idle: SystemIdleTime(),
        nudger: CGMouseNudger(),
        accessibility: SystemAccessibility(),
        settings: UserDefaultsSettings())
    private var statusItemController: StatusItemController?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(controller: controller, loginItem: LoginItem())
        timer = Timer.scheduledTimer(withTimeInterval: KeepAwakeController.tickInterval, repeats: true) {
            [controller] _ in
            MainActor.assumeIsolated { controller.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.turnOff()
    }
}
