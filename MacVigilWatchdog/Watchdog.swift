import Foundation
import CoreGraphics
import IOKit
import Darwin

// Companion process used only while Closed-Lid Eco is armed.
// If the GUI process disappears or its heartbeat becomes stale, this helper
// releases the experimental kernel clamshell guard, restores SleepDisabled
// only when MacVigil owned it, and restores the saved built-in brightness.

private let selector: UInt32 = 12
private let staleHeartbeatSeconds: TimeInterval = 30
private let pollSeconds: UInt32 = 2
private let reinforceEveryTicks = 3

typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

private func openRootDomain() -> (io_service_t, io_connect_t)? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return nil }

    var connection: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard result == KERN_SUCCESS else {
        IOObjectRelease(service)
        return nil
    }
    return (service, connection)
}

@discardableResult
private func setClamshellSleepDisabled(_ disabled: Bool, connection: io_connect_t) -> Bool {
    var input: UInt64 = disabled ? 1 : 0
    let result = IOConnectCallScalarMethod(connection, selector, &input, 1, nil, nil)
    return result == kIOReturnSuccess
}

private func restorePMSetSleep() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

private func restoreBrightness(from brightnessPath: String, displayID: CGDirectDisplayID) {
    guard displayID != 0,
          let raw = try? String(contentsOfFile: brightnessPath, encoding: .utf8),
          let brightness = Float(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return }

    let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    guard let handle = dlopen(path, RTLD_LAZY),
          let symbol = dlsym(handle, "DisplayServicesSetBrightness")
    else { return }

    let setBrightness = unsafeBitCast(symbol, to: DSSetBrightnessFn.self)
    _ = setBrightness(displayID, max(0.05, min(1.0, brightness)))
    dlclose(handle)
}

private func heartbeatIsValid(parentPID: pid_t, tokenPath: String, token: String) -> Bool {
    guard kill(parentPID, 0) == 0 else { return false }
    guard let stored = try? String(contentsOfFile: tokenPath, encoding: .utf8),
          stored.trimmingCharacters(in: .whitespacesAndNewlines) == token
    else { return false }

    guard let attributes = try? FileManager.default.attributesOfItem(atPath: tokenPath),
          let modified = attributes[.modificationDate] as? Date
    else { return false }

    return Date().timeIntervalSince(modified) <= staleHeartbeatSeconds
}

@main
struct MacVigilWatchdog {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 7,
              let parentPID = Int32(args[1]),
              let displayRaw = UInt32(args[5])
        else { exit(64) }

        let tokenPath = args[2]
        let token = args[3]
        let brightnessPath = args[4]
        let displayID = CGDirectDisplayID(displayRaw)
        let macVigilOwnsPMSet = args[6] == "1"

        guard let (service, connection) = openRootDomain() else { exit(70) }
        defer {
            _ = setClamshellSleepDisabled(false, connection: connection)
            if macVigilOwnsPMSet { restorePMSetSleep() }
            restoreBrightness(from: brightnessPath, displayID: displayID)
            try? FileManager.default.removeItem(atPath: tokenPath)
            try? FileManager.default.removeItem(atPath: brightnessPath)
            IOServiceClose(connection)
            IOObjectRelease(service)
        }

        var tick = 0
        while heartbeatIsValid(parentPID: parentPID, tokenPath: tokenPath, token: token) {
            if tick % reinforceEveryTicks == 0 {
                _ = setClamshellSleepDisabled(true, connection: connection)
            }
            tick += 1
            sleep(pollSeconds)
        }
    }
}
