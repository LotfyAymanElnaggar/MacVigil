import Foundation
import AppKit
import Carbon
import Combine

@MainActor
final class GlobalHotkeyManager: ObservableObject {
    struct Shortcut: Identifiable {
        let id: UInt32
        let title: String
        let detail: String
        let keys: String
        let keyCode: UInt32
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var lastActionText: String?

    static let shortcuts: [Shortcut] = [
        Shortcut(id: 1, title: "Start / Stop Vigil", detail: "Toggle the current Vigil session.", keys: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V)),
        Shortcut(id: 11, title: "Compute Guard", detail: "Switch the protection profile without changing session ownership.", keys: "⌥⌘1", keyCode: UInt32(kVK_ANSI_1)),
        Shortcut(id: 12, title: "Closed-Lid Eco", detail: "Switch to the closed-lid protection profile.", keys: "⌥⌘2", keyCode: UInt32(kVK_ANSI_2)),
        Shortcut(id: 13, title: "Full Awake", detail: "Switch to the full-awake protection profile.", keys: "⌥⌘3", keyCode: UInt32(kVK_ANSI_3))
    ]

    private let enabledKey = "MacVigil.hotkeys.enabled"
    private let signature: OSType = 0x4D564947 // MVIG
    private weak var manager: VigilManager?
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var started = false

    init(manager: VigilManager) {
        self.manager = manager
        let defaults = UserDefaults.standard
        self.enabled = defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
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
            unregisterAll()
            lastActionText = "Global hotkeys disabled."
        }
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

        let modifiers = UInt32(cmdKey | optionKey)
        for shortcut in Self.shortcuts {
            var ref: EventHotKeyRef?
            var hotKeyID = EventHotKeyID(signature: signature, id: shortcut.id)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registeredHotKeys[shortcut.id] = ref
            }
        }

        if registeredHotKeys.count != Self.shortcuts.count {
            lastActionText = "Some MacVigil hotkeys could not be registered because another app may already use them."
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
                lastActionText = "Vigil stopped with ⌥⌘V."
            } else {
                if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                    NSSound.beep()
                    lastActionText = "Open MacVigil once to acknowledge Closed-Lid Eco safety before starting it from a hotkey."
                    return
                }
                await manager.startFreshSession()
                if manager.isActive {
                    lastActionText = "Vigil started with ⌥⌘V."
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
}
