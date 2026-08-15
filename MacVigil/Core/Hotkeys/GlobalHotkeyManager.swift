import Foundation
import AppKit
import Carbon
import Combine

@MainActor
final class GlobalHotkeyManager: ObservableObject {
    struct Shortcut: Identifiable, Equatable {
        let id: UInt32
        let title: String
        let detail: String
        var keys: String
        var keyCode: UInt32
        var modifiers: UInt32
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var lastActionText: String?
    @Published private(set) var shortcuts: [Shortcut]
    @Published private(set) var recordingID: UInt32?

    static let defaultShortcuts: [Shortcut] = [
        Shortcut(id: 1, title: "Start / Stop Vigil", detail: "Toggle the current Vigil session.", keys: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)),
        Shortcut(id: 11, title: "Compute Guard", detail: "Switch the protection profile without changing session ownership.", keys: "⌥⌘1", keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | optionKey)),
        Shortcut(id: 12, title: "Closed-Lid Eco", detail: "Switch to the closed-lid protection profile.", keys: "⌥⌘2", keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | optionKey)),
        Shortcut(id: 13, title: "Full Awake", detail: "Switch to the full-awake protection profile.", keys: "⌥⌘3", keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | optionKey))
    ]

    private let enabledKey = "MacVigil.hotkeys.enabled"
    private let shortcutPrefix = "MacVigil.hotkeys.shortcut."
    private let signature: OSType = 0x4D564947 // MVIG
    private weak var manager: VigilManager?
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var localKeyMonitor: Any?
    private var started = false

    init(manager: VigilManager) {
        self.manager = manager
        let defaults = UserDefaults.standard
        self.enabled = defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
        self.shortcuts = Self.defaultShortcuts.map { Self.loadShortcut($0, defaults: defaults) }
    }

    func start() {
        guard !started else {
            if enabled && registeredHotKeys.isEmpty { registerAll() }
            return
        }
        started = true
        installEventHandler()
        if enabled { registerAll() }
    }

    func stop() {
        cancelRecording()
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        started = false
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: enabledKey)
        if value {
            if !started { start() }
            else { registerAll() }
            lastActionText = "Global hotkeys enabled."
        } else {
            cancelRecording()
            unregisterAll()
            lastActionText = "Global hotkeys disabled."
        }
    }

    func shortcut(id: UInt32) -> Shortcut? {
        shortcuts.first { $0.id == id }
    }

    var startStopKeys: String {
        shortcut(id: 1)?.keys ?? "⌥⌘V"
    }

    func beginRecording(id: UInt32) {
        guard shortcuts.contains(where: { $0.id == id }) else { return }
        cancelRecording()
        recordingID = id
        lastActionText = "Press the new shortcut. Use at least one modifier key. Press Escape to cancel."

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers ?? ""

            Task { @MainActor [weak self] in
                self?.captureRecordedShortcut(keyCode: keyCode, flags: flags, characters: characters)
            }
            return nil
        }
    }

    func cancelRecording() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        recordingID = nil
    }

    func resetShortcut(id: UInt32) {
        guard let defaultShortcut = Self.defaultShortcuts.first(where: { $0.id == id }),
              let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index] = defaultShortcut
        clearStoredShortcut(id: id)
        if enabled { registerAll() }
        lastActionText = "Restored \(defaultShortcut.title) to \(defaultShortcut.keys)."
    }

    func resetAllShortcuts() {
        cancelRecording()
        shortcuts = Self.defaultShortcuts
        for shortcut in Self.defaultShortcuts {
            clearStoredShortcut(id: shortcut.id)
        }
        if enabled { registerAll() }
        lastActionText = "Restored all MacVigil hotkeys to their defaults."
    }

    private func captureRecordedShortcut(keyCode: UInt32, flags: NSEvent.ModifierFlags, characters: String) {
        guard let id = recordingID else { return }

        if keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            lastActionText = "Shortcut change cancelled."
            return
        }

        let carbonModifiers = Self.carbonModifiers(from: flags)
        guard carbonModifiers != 0 else {
            NSSound.beep()
            lastActionText = "Use at least one modifier key such as Command, Option, Control, or Shift."
            return
        }

        let keyLabel = Self.keyLabel(keyCode: keyCode, characters: characters)
        let display = Self.displayString(modifiers: carbonModifiers, keyLabel: keyLabel)

        if let duplicate = shortcuts.first(where: {
            $0.id != id && $0.keyCode == keyCode && $0.modifiers == carbonModifiers
        }) {
            NSSound.beep()
            lastActionText = "\(display) is already assigned to \(duplicate.title)."
            return
        }

        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index].keyCode = keyCode
        shortcuts[index].modifiers = carbonModifiers
        shortcuts[index].keys = display
        persist(shortcuts[index])
        cancelRecording()

        if enabled { registerAll() }
        lastActionText = "\(shortcuts[index].title) is now \(display)."
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                await manager.handle(id: hotKeyID.id)
            }
            return noErr
        }

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &handler
        )

        if status == noErr {
            eventHandler = handler
        } else {
            lastActionText = "Could not install the global hotkey handler."
        }
    }

    private func registerAll() {
        guard enabled else { return }
        unregisterAll()

        var failed: [String] = []
        for shortcut in shortcuts {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: shortcut.id)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registeredHotKeys[shortcut.id] = ref
            } else {
                failed.append(shortcut.keys)
            }
        }

        if !failed.isEmpty {
            lastActionText = "Could not register \(failed.joined(separator: ", ")). Another app or macOS may already use the shortcut."
        }
    }

    private func unregisterAll() {
        for ref in registeredHotKeys.values {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
    }

    private func handle(id: UInt32) async {
        guard enabled, let manager else { return }

        switch id {
        case 1:
            if manager.isActive {
                await manager.stopLiveSession()
                lastActionText = "Vigil stopped with \(shortcut(id: 1)?.keys ?? "hotkey")."
            } else {
                if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                    NSSound.beep()
                    lastActionText = "Open MacVigil once to acknowledge Closed-Lid Eco safety before starting it from a hotkey."
                    return
                }
                await manager.startFreshSession()
                if manager.isActive {
                    lastActionText = "Vigil started with \(shortcut(id: 1)?.keys ?? "hotkey")."
                } else {
                    NSSound.beep()
                    lastActionText = manager.lastError ?? "Vigil could not start."
                }
            }

        case 11:
            await apply(.computeGuard, label: "Compute Guard")
        case 12:
            await apply(.closedLidEco, label: "Closed-Lid Eco")
        case 13:
            await apply(.fullAwake, label: "Full Awake")
        default:
            break
        }
    }

    private func apply(_ profile: RuntimeProfile, label: String) async {
        guard let manager else { return }
        let changed = await manager.changeModeLive(profile)
        if changed {
            lastActionText = "Switched to \(label)."
        } else {
            NSSound.beep()
            lastActionText = manager.lidIsClosed
                ? "Open the MacBook lid before changing away from closed-lid protection."
                : "MacVigil could not switch to \(label) safely."
        }
    }

    private func persist(_ shortcut: Shortcut) {
        let defaults = UserDefaults.standard
        let prefix = shortcutPrefix + String(shortcut.id) + "."
        defaults.set(Int(shortcut.keyCode), forKey: prefix + "keyCode")
        defaults.set(Int(shortcut.modifiers), forKey: prefix + "modifiers")
        defaults.set(shortcut.keys, forKey: prefix + "keys")
    }

    private func clearStoredShortcut(id: UInt32) {
        let defaults = UserDefaults.standard
        let prefix = shortcutPrefix + String(id) + "."
        defaults.removeObject(forKey: prefix + "keyCode")
        defaults.removeObject(forKey: prefix + "modifiers")
        defaults.removeObject(forKey: prefix + "keys")
    }

    private static func loadShortcut(_ fallback: Shortcut, defaults: UserDefaults) -> Shortcut {
        let prefix = "MacVigil.hotkeys.shortcut." + String(fallback.id) + "."
        guard defaults.object(forKey: prefix + "keyCode") != nil,
              defaults.object(forKey: prefix + "modifiers") != nil else {
            return fallback
        }
        var shortcut = fallback
        shortcut.keyCode = UInt32(defaults.integer(forKey: prefix + "keyCode"))
        shortcut.modifiers = UInt32(defaults.integer(forKey: prefix + "modifiers"))
        shortcut.keys = defaults.string(forKey: prefix + "keys") ?? fallback.keys
        return shortcut
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func displayString(modifiers: UInt32, keyLabel: String) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    private static func keyLabel(keyCode: UInt32, characters: String) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
        }
    }
}
