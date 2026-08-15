import Foundation
import IOKit
import Darwin

final class RootDomainLidGuard {
    private let selector: UInt32 = 12
    private var service: io_service_t = 0
    private var connection: io_connect_t = 0

    private(set) var isArmed = false
    private(set) var lastStatus = "not armed"
    private(set) var lastReturn: IOReturn = kIOReturnSuccess

    func setArmed(_ armed: Bool) -> Bool {
        guard ensureConnection() else {
            isArmed = false
            return false
        }

        var input: UInt64 = armed ? 1 : 0
        let result = IOConnectCallScalarMethod(connection, selector, &input, 1, nil, nil)
        lastReturn = result

        guard result == kIOReturnSuccess else {
            isArmed = false
            lastStatus = "selector 12 failed: 0x\(String(UInt32(bitPattern: result), radix: 16))"
            return false
        }

        isArmed = armed
        lastStatus = armed ? "selector 12 accepted" : "selector 12 released"
        return true
    }

    func readBool(_ key: String) -> Bool? {
        let currentService: io_service_t
        let releaseAfterRead: Bool

        if service != 0 {
            currentService = service
            releaseAfterRead = false
        } else {
            currentService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            releaseAfterRead = true
        }

        guard currentService != 0 else { return nil }
        defer {
            if releaseAfterRead { IOObjectRelease(currentService) }
        }

        guard let value = IORegistryEntryCreateCFProperty(
            currentService,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }

    private func ensureConnection() -> Bool {
        if connection != 0 { return true }

        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            lastStatus = "IOPMrootDomain unavailable"
            return false
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            lastStatus = "IOServiceOpen failed: 0x\(String(UInt32(bitPattern: result), radix: 16))"
            IOObjectRelease(service)
            service = 0
            connection = 0
            return false
        }

        return true
    }

    deinit {
        if connection != 0 {
            var input: UInt64 = 0
            _ = IOConnectCallScalarMethod(connection, selector, &input, 1, nil, nil)
        }
        close()
    }
}
