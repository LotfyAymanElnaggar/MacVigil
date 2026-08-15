import Foundation
import IOKit
import IOKit.pwr_mgt

extension Notification.Name {
    static let macVigilSystemPoweredOn = Notification.Name("MacVigil.SystemPoweredOn")
    static let macVigilSleepVetoed = Notification.Name("MacVigil.SleepVetoed")
}

private let kIOMessageCanSystemSleepRaw: UInt32 = 0xE0000270
private let kIOMessageSystemWillSleepRaw: UInt32 = 0xE0000280
private let kIOMessageSystemHasPoweredOnRaw: UInt32 = 0xE0000300

private let macVigilPowerCallback: IOServiceInterestCallback = { refCon, _, messageType, argument in
    guard let refCon else { return }
    let controller = Unmanaged<SystemPowerVeto>.fromOpaque(refCon).takeUnretainedValue()
    controller.handle(messageType: messageType, argument: argument)
}

final class SystemPowerVeto {
    private let lock = NSLock()
    private var enabled = false
    private var rootPowerPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?

    init() {
        let refCon = Unmanaged.passUnretained(self).toOpaque()
        rootPowerPort = IORegisterForSystemPower(refCon, &notifyPort, macVigilPowerCallback, &notifier)

        if rootPowerPort != 0, let notifyPort {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
                CFRunLoopMode.defaultMode
            )
        }
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }

    fileprivate func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        lock.lock()
        let shouldVeto = enabled
        lock.unlock()

        let notificationID = Int(bitPattern: argument)

        switch messageType {
        case kIOMessageCanSystemSleepRaw:
            if shouldVeto {
                IOCancelPowerChange(rootPowerPort, notificationID)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .macVigilSleepVetoed, object: nil)
                }
            } else {
                IOAllowPowerChange(rootPowerPort, notificationID)
            }

        case kIOMessageSystemWillSleepRaw:
            // Mandatory system/safety sleep is acknowledged rather than defeated.
            IOAllowPowerChange(rootPowerPort, notificationID)

        case kIOMessageSystemHasPoweredOnRaw:
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .macVigilSystemPoweredOn, object: nil)
            }

        default:
            break
        }
    }

    deinit {
        setEnabled(false)
        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if rootPowerPort != 0 {
            IOServiceClose(rootPowerPort)
            rootPowerPort = 0
        }
    }
}
