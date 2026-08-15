import Foundation
import CoreGraphics
import Darwin

private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

final class BacklightController {
    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: DSGetBrightnessFn?
    private var setBrightness: DSSetBrightnessFn?
    private var builtinDisplayID: CGDirectDisplayID?

    private(set) var savedBrightness: Float?
    private(set) var isDimmed = false
    private(set) var status = "idle"

    init() {
        loadDisplayServices()
        findBuiltinDisplay()
    }

    func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }

        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    func dimBuiltinDisplay(saveTo brightnessFile: String?) {
        loadDisplayServices()
        findBuiltinDisplay()

        guard !isDimmed,
              let display = builtinDisplayID,
              let getBrightness,
              let setBrightness else {
            status = "Backlight control unavailable on this macOS build."
            return
        }

        var current: Float = 0
        guard getBrightness(display, &current) == 0 else {
            status = "Could not read built-in display brightness."
            return
        }

        let clamped = max(0, min(1, current))
        savedBrightness = clamped
        if let brightnessFile {
            try? "\(clamped)\n".write(toFile: brightnessFile, atomically: true, encoding: .utf8)
        }

        let result = setBrightness(display, 0)
        if result == 0 {
            isDimmed = true
            status = "Built-in backlight set to 0."
        } else {
            savedBrightness = nil
            if let brightnessFile { try? FileManager.default.removeItem(atPath: brightnessFile) }
            status = "macOS rejected the backlight request (\(result))."
        }
    }

    func restoreBuiltinDisplay(from brightnessFile: String?) {
        guard isDimmed || savedBrightness != nil else { return }

        loadDisplayServices()
        findBuiltinDisplay()

        var target = savedBrightness
        if target == nil,
           let brightnessFile,
           let raw = try? String(contentsOfFile: brightnessFile, encoding: .utf8) {
            target = Float(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let display = builtinDisplayID,
           let setBrightness,
           let target {
            _ = setBrightness(display, max(0.05, min(1, target)))
        }

        isDimmed = false
        savedBrightness = nil
        status = "Built-in brightness restored."
        if let brightnessFile { try? FileManager.default.removeItem(atPath: brightnessFile) }
    }

    func builtinDisplayIdentifier() -> CGDirectDisplayID {
        findBuiltinDisplay()
        return builtinDisplayID ?? 0
    }

    private func loadDisplayServices() {
        guard getBrightness == nil || setBrightness == nil else { return }

        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            status = "DisplayServices unavailable."
            return
        }

        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            dlclose(handle)
            status = "DisplayServices brightness symbols unavailable."
            return
        }

        self.handle = handle
        getBrightness = unsafeBitCast(getSymbol, to: DSGetBrightnessFn.self)
        setBrightness = unsafeBitCast(setSymbol, to: DSSetBrightnessFn.self)
    }

    private func findBuiltinDisplay() {
        if builtinDisplayID != nil { return }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return }

        builtinDisplayID = displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    deinit {
        if let handle { dlclose(handle) }
    }
}
