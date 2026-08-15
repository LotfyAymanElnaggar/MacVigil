import Foundation
import IOKit.pwr_mgt

final class PowerAssertions {
    private var systemAssertionID: IOPMAssertionID = 0
    private var idleSystemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    func start(keepDisplayAwake: Bool, reason: String) -> IOReturn {
        stop()

        var result = create(type: kIOPMAssertionTypePreventSystemSleep, reason: reason, id: &systemAssertionID)
        guard result == kIOReturnSuccess else { return result }

        result = create(type: kIOPMAssertionTypePreventUserIdleSystemSleep, reason: reason, id: &idleSystemAssertionID)
        guard result == kIOReturnSuccess else {
            stop()
            return result
        }

        if keepDisplayAwake {
            result = create(type: kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: reason, id: &displayAssertionID)
            guard result == kIOReturnSuccess else {
                stop()
                return result
            }
        }

        return kIOReturnSuccess
    }

    func stop() {
        release(&displayAssertionID)
        release(&idleSystemAssertionID)
        release(&systemAssertionID)
    }

    private func create(type: String, reason: String, id: inout IOPMAssertionID) -> IOReturn {
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as NSString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as NSString,
            &newID
        )
        if result == kIOReturnSuccess { id = newID }
        return result
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }

    deinit {
        stop()
    }
}
