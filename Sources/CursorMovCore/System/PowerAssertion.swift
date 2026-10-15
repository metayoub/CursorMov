import Foundation
import IOKit.pwr_mgt

/// Holds an IOKit assertion that stops idle display sleep, which also keeps
/// the system awake and the screen from locking.
public final class PowerAssertion: KeepAwakeAssertion {
    public static let name = "CursorMov is keeping the Mac awake"

    private var assertionID = IOPMAssertionID(0)
    private var isHeld = false

    public init() {}

    deinit { release() }

    public func acquire() -> Bool {
        if isHeld { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.name as CFString,
            &assertionID)
        isHeld = result == kIOReturnSuccess
        return isHeld
    }

    public func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }
}
