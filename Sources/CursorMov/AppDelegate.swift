import AppKit
import CursorMovCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = KeepAwakeController(
        assertion: PowerAssertion(),
        idle: SystemIdleTime(),
        nudger: CGMouseNudger(),
        accessibility: SystemAccessibility(),
        settings: UserDefaultsSettings(),
        battery: SystemBattery())
    private var statusItemController: StatusItemController?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(controller: controller, loginItem: LoginItem())
        let timer = Timer(timeInterval: KeepAwakeController.tickInterval, repeats: true) {
            [controller] _ in
            MainActor.assumeIsolated { controller.tick() }
        }
        // .common keeps ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.turnOff()
    }
}
