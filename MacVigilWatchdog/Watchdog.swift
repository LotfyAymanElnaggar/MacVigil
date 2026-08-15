import Foundation
import CoreGraphics
import IOKit
import Darwin

// Crash-recovery companion for a MacVigil closed-lid session.
//
// Arguments:
//   1 parent PID
//   2 heartbeat token path
//   3 heartbeat token contents
//   4 saved brightness path
//   5 built-in CGDirectDisplayID (0 when unavailable)
//   6 MacVigil owns pmset SleepDisabled: 1 or 0
//   7 kernel clamshell guard enabled: 1 or 0

private let kPMSetClamshellSleepStateSelector: UInt32 = 12
private let staleHeartbeatSeconds: TimeInterval = 30
private let pollSeconds: UInt32 = 2
private let reinforceEveryTicks = 2 // about every 4 seconds

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
    let result = IOConnectCallScalarMethod(
        connection,
        kPMSetClamshellSleepStateSelector,
        &input,
        1,
        nil,
        nil
    )
    return result == kIOReturnSuccess
}

private func setPMSetSleepDisabled(_ disabled: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = [
        "-n",
        "/usr/bin/pmset",
        "-a",
        "disablesleep",
        disabled ? "1" : "0"
    ]
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

    let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    guard let handle = dlopen(frameworkPath, RTLD_LAZY),
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

    guard let attrs = try? FileManager.default.attributesOfItem(atPath: tokenPath),
          let modified = attrs[.modificationDate] as? Date
    else { return false }

    return Date().timeIntervalSince(modified) <= staleHeartbeatSeconds
}

@main
struct MacVigilWatchdog {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 8,
              let parentPID = Int32(args[1]),
              let displayRaw = UInt32(args[5])
        else { exit(64) }

        let tokenPath = args[2]
        let token = args[3]
        let brightnessPath = args[4]
        let displayID = CGDirectDisplayID(displayRaw)
        let appOwnsPMSet = args[6] == "1"
        let kernelGuardEnabled = args[7] == "1"

        let rootDomain = kernelGuardEnabled ? openRootDomain() : nil
        if kernelGuardEnabled && rootDomain == nil { exit(70) }

        defer {
            if let (_, connection) = rootDomain, kernelGuardEnabled {
                _ = setClamshellSleepDisabled(false, connection: connection)
            }
            if appOwnsPMSet { setPMSetSleepDisabled(false) }
            restoreBrightness(from: brightnessPath, displayID: displayID)
            try? FileManager.default.removeItem(atPath: tokenPath)
            try? FileManager.default.removeItem(atPath: brightnessPath)

            if let (service, connection) = rootDomain {
                IOServiceClose(connection)
                IOObjectRelease(service)
            }
        }

        var tick = 0
        while heartbeatIsValid(parentPID: parentPID, tokenPath: tokenPath, token: token) {
            if tick % reinforceEveryTicks == 0 {
                if let (_, connection) = rootDomain, kernelGuardEnabled {
                    _ = setClamshellSleepDisabled(true, connection: connection)
                }
                if appOwnsPMSet {
                    setPMSetSleepDisabled(true)
                }
            }
            tick += 1
            sleep(pollSeconds)
        }
    }
}
