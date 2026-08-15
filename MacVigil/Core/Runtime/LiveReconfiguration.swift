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
private enum LiveSessionContinuity {
    struct Entry {
        let deadline: Date
        let generation: UUID
    }

    static var entries: [ObjectIdentifier: Entry] = [:]

    static func deadline(for manager: VigilManager) -> Date? {
        entries[ObjectIdentifier(manager)]?.deadline
    }

    @discardableResult
    static func setDeadline(_ deadline: Date, for manager: VigilManager) -> UUID {
        let generation = UUID()
        entries[ObjectIdentifier(manager)] = Entry(deadline: deadline, generation: generation)
        return generation
    }

    static func clear(for manager: VigilManager) {
        entries.removeValue(forKey: ObjectIdentifier(manager))
    }

    static func isCurrent(_ generation: UUID, for manager: VigilManager) -> Bool {
        entries[ObjectIdentifier(manager)]?.generation == generation
    }
}

@MainActor
extension VigilManager {
    /// The user-visible deadline. During a live mode/option handoff this keeps
    /// the original deadline exact even though the underlying session is
    /// briefly rebuilt with the new power configuration.
    var effectiveEndDate: Date? {
        LiveSessionContinuity.deadline(for: self) ?? endDate
    }

    var effectiveRemainingSeconds: TimeInterval? {
        if let deadline = LiveSessionContinuity.deadline(for: self) {
            return max(0, deadline.timeIntervalSinceNow)
        }
        return remainingSeconds
    }

    func startFreshSession() async {
        LiveSessionContinuity.clear(for: self)
        await startSelectedSession()
    }

    func stopLiveSession() async {
        LiveSessionContinuity.clear(for: self)
        await stopSession()
    }

    /// Changes a single protection option while preserving the exact active
    /// session deadline.
    func changeOptionLive(_ option: VigilOption, to enabled: Bool) async -> Bool {
        if !isActive {
            setOption(option, to: enabled)
            savePreferences()
            return true
        }

        if lidIsClosed && requiresOpenLidForLiveChange(option) {
            return false
        }

        if option == .useGlobalSleepDisable && enabled {
            await refreshAuthorizationStatus()
            guard pmsetPrivilegeAvailable else { return false }
        }

        let snapshot = captureLiveSessionSnapshot()
        LiveSessionContinuity.clear(for: self)
        await stopSession()
        setOption(option, to: enabled)
        savePreferences()
        return await restartFromLiveSnapshot(snapshot)
    }

    /// Applies a preset to a running Vigil session without resetting the
    /// current countdown.
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
        LiveSessionContinuity.clear(for: self)
        await stopSession()
        applyPreset(preset)

        // Closed-Lid Eco keeps display sleep logically blocked while allowing
        // MacVigil to darken the built-in backlight on lid close.
        if preset == .closedLidEco {
            keepDisplayAwake = true
        }

        savePreferences()
        return await restartFromLiveSnapshot(snapshot)
    }

    /// A deliberate duration change starts a new countdown. Mode and option
    /// changes do not.
    func changeDurationLive(_ duration: SessionDuration, customMinutes: Int? = nil) async -> Bool {
        let wasActive = isActive
        LiveSessionContinuity.clear(for: self)

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
        let deadline: Date?
    }

    private func captureLiveSessionSnapshot() -> LiveSessionSnapshot {
        LiveSessionSnapshot(
            selectedDuration: selectedDuration,
            customMinutes: customMinutes,
            deadline: effectiveEndDate
        )
    }

    private func restartFromLiveSnapshot(_ snapshot: LiveSessionSnapshot) async -> Bool {
        if let deadline = snapshot.deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                LiveSessionContinuity.clear(for: self)
                return false
            }

            // The regular timer API accepts whole custom minutes. Start it at a
            // ceiling value, then keep the original exact deadline as the
            // authoritative countdown and expiry. This prevents any visible or
            // behavioral timer reset during live reconfiguration.
            selectedDuration = .custom
            customMinutes = max(1, Int(ceil(remaining / 60.0)))
            await startSelectedSession()

            guard isActive else {
                selectedDuration = snapshot.selectedDuration
                customMinutes = snapshot.customMinutes
                savePreferences()
                return false
            }

            selectedDuration = snapshot.selectedDuration
            customMinutes = snapshot.customMinutes
            savePreferences()
            installExactContinuityDeadline(deadline)
            return true
        }

        selectedDuration = snapshot.selectedDuration
        customMinutes = snapshot.customMinutes
        await startSelectedSession()
        savePreferences()
        return isActive
    }

    private func installExactContinuityDeadline(_ deadline: Date) {
        let generation = LiveSessionContinuity.setDeadline(deadline, for: self)
        let delay = max(0.05, deadline.timeIntervalSinceNow)
        let nanoseconds = UInt64(min(delay, TimeInterval(UInt64.max) / 1_000_000_000.0) * 1_000_000_000.0)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            guard LiveSessionContinuity.isCurrent(generation, for: self) else { return }
            LiveSessionContinuity.clear(for: self)
            if self.isActive {
                await self.stopSession()
            }
        }
    }
}
