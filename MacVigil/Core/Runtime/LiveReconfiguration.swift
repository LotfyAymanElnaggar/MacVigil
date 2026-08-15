import Foundation

enum VigilOption {
    case preventSystemSleep
    case preventIdleSystemSleep
    case keepDisplayAwake
    case vetoIdleSleepRequests
    case useGlobalSleepDisable
    case useKernelLidGuard
    case darkenBuiltinDisplayOnLidClose
    case enableBatterySafety
    case enableThermalSafety
}

@MainActor
extension VigilManager {
    /// Changes a single protection option while preserving an active session.
    /// Returns false when the requested transition is unsafe or cannot be
    /// prepared without interrupting the current protection.
    func changeOptionLive(_ option: VigilOption, to enabled: Bool) async -> Bool {
        if !isActive {
            setOption(option, to: enabled)
            savePreferences()
            return true
        }

        if lidIsClosed && requiresOpenLidForLiveChange(option) {
            return false
        }

        // Preflight privileged closed-lid protection before touching the
        // currently running session so a failed authorization check never
        // tears down working protection.
        if option == .useGlobalSleepDisable && enabled {
            await refreshAuthorizationStatus()
            guard pmsetPrivilegeAvailable else { return false }
        }

        let snapshot = captureLiveSessionSnapshot()
        await stopSession()
        setOption(option, to: enabled)
        savePreferences()

        let restarted = await restartFromLiveSnapshot(snapshot)
        if !restarted {
            return false
        }

        return true
    }

    /// Applies a preset to a running Vigil session. The remaining countdown is
    /// preserved instead of restarting the full selected duration.
    func changeModeLive(_ preset: RuntimeProfile) async -> Bool {
        if !isActive {
            applyPreset(preset)
            if preset == .closedLidEco {
                keepDisplayAwake = true
            }
            savePreferences()
            return true
        }

        if lidIsClosed && closedLidProtectionRequested && preset != .closedLidEco {
            return false
        }

        if preset == .closedLidEco {
            await refreshAuthorizationStatus()
            guard pmsetPrivilegeAvailable else { return false }
        }

        let snapshot = captureLiveSessionSnapshot()
        await stopSession()
        applyPreset(preset)

        // Closed-Lid Eco keeps the display logically awake and darkens the
        // built-in backlight on lid close. This avoids relying on display sleep,
        // which may invoke the user's Lock Screen policy.
        if preset == .closedLidEco {
            keepDisplayAwake = true
        }

        savePreferences()
        return await restartFromLiveSnapshot(snapshot)
    }

    /// Duration changes intentionally start a fresh countdown using the newly
    /// selected duration while keeping the current protection configuration.
    func changeDurationLive(_ duration: SessionDuration, customMinutes: Int? = nil) async -> Bool {
        let wasActive = isActive

        if wasActive {
            await stopSession()
        }

        selectedDuration = duration
        if let customMinutes {
            self.customMinutes = min(24 * 60, max(1, customMinutes))
        }
        savePreferences()

        if wasActive {
            await startSelectedSession()
            return isActive
        }

        return true
    }

    private func setOption(_ option: VigilOption, to enabled: Bool) {
        switch option {
        case .preventSystemSleep:
            preventSystemSleep = enabled
        case .preventIdleSystemSleep:
            preventIdleSystemSleep = enabled
        case .keepDisplayAwake:
            keepDisplayAwake = enabled
        case .vetoIdleSleepRequests:
            vetoIdleSleepRequests = enabled
        case .useGlobalSleepDisable:
            useGlobalSleepDisable = enabled
        case .useKernelLidGuard:
            useKernelLidGuard = enabled
        case .darkenBuiltinDisplayOnLidClose:
            darkenBuiltinDisplayOnLidClose = enabled
        case .enableBatterySafety:
            enableBatterySafety = enabled
        case .enableThermalSafety:
            enableThermalSafety = enabled
        }
    }

    private func requiresOpenLidForLiveChange(_ option: VigilOption) -> Bool {
        switch option {
        case .useGlobalSleepDisable, .useKernelLidGuard, .darkenBuiltinDisplayOnLidClose, .keepDisplayAwake:
            return true
        default:
            return false
        }
    }

    private struct LiveSessionSnapshot {
        let selectedDuration: SessionDuration
        let customMinutes: Int
        let hadDeadline: Bool
        let remainingMinutes: Int?
    }

    private func captureLiveSessionSnapshot() -> LiveSessionSnapshot {
        let hadDeadline = endDate != nil
        let seconds = remainingSeconds ?? endDate?.timeIntervalSinceNow
        let minutes: Int?

        if hadDeadline, let seconds {
            minutes = max(1, Int(ceil(max(1, seconds) / 60.0)))
        } else {
            minutes = nil
        }

        return LiveSessionSnapshot(
            selectedDuration: selectedDuration,
            customMinutes: customMinutes,
            hadDeadline: hadDeadline,
            remainingMinutes: minutes
        )
    }

    private func restartFromLiveSnapshot(_ snapshot: LiveSessionSnapshot) async -> Bool {
        if snapshot.hadDeadline, let remainingMinutes = snapshot.remainingMinutes {
            selectedDuration = .custom
            customMinutes = remainingMinutes
            await startSelectedSession()

            let restarted = isActive
            selectedDuration = snapshot.selectedDuration
            customMinutes = snapshot.customMinutes
            savePreferences()
            return restarted
        }

        selectedDuration = snapshot.selectedDuration
        customMinutes = snapshot.customMinutes
        await startSelectedSession()
        savePreferences()
        return isActive
    }
}
