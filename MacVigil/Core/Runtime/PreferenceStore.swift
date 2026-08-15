import Foundation

private enum MacVigilPreferenceKey {
    static let selectedDuration = "MacVigil.preference.selectedDuration"
    static let customMinutes = "MacVigil.preference.customMinutes"
    static let lowBatteryCutoff = "MacVigil.preference.lowBatteryCutoff"
    static let preventSystemSleep = "MacVigil.preference.preventSystemSleep"
    static let preventIdleSystemSleep = "MacVigil.preference.preventIdleSystemSleep"
    static let keepDisplayAwake = "MacVigil.preference.keepDisplayAwake"
    static let vetoIdleSleepRequests = "MacVigil.preference.vetoIdleSleepRequests"
    static let useGlobalSleepDisable = "MacVigil.preference.useGlobalSleepDisable"
    static let useKernelLidGuard = "MacVigil.preference.useKernelLidGuard"
    static let darkenBuiltinDisplayOnLidClose = "MacVigil.preference.darkenBuiltinDisplayOnLidClose"
    static let enableBatterySafety = "MacVigil.preference.enableBatterySafety"
    static let enableThermalSafety = "MacVigil.preference.enableThermalSafety"
    static let closedLidAcknowledged = "MacVigil.closedLidAcknowledged"
}

@MainActor
extension VigilManager {
    func loadPreferences() {
        guard !isActive else { return }

        let defaults = UserDefaults.standard

        if let rawDuration = defaults.string(forKey: MacVigilPreferenceKey.selectedDuration),
           let duration = SessionDuration(rawValue: rawDuration) {
            selectedDuration = duration
        }

        if defaults.object(forKey: MacVigilPreferenceKey.customMinutes) != nil {
            customMinutes = min(24 * 60, max(1, defaults.integer(forKey: MacVigilPreferenceKey.customMinutes)))
        }

        if defaults.object(forKey: MacVigilPreferenceKey.lowBatteryCutoff) != nil {
            lowBatteryCutoff = min(30, max(5, defaults.integer(forKey: MacVigilPreferenceKey.lowBatteryCutoff)))
        }

        loadBool(MacVigilPreferenceKey.preventSystemSleep, into: &preventSystemSleep)
        loadBool(MacVigilPreferenceKey.preventIdleSystemSleep, into: &preventIdleSystemSleep)
        loadBool(MacVigilPreferenceKey.keepDisplayAwake, into: &keepDisplayAwake)
        loadBool(MacVigilPreferenceKey.vetoIdleSleepRequests, into: &vetoIdleSleepRequests)
        loadBool(MacVigilPreferenceKey.useGlobalSleepDisable, into: &useGlobalSleepDisable)
        loadBool(MacVigilPreferenceKey.useKernelLidGuard, into: &useKernelLidGuard)
        loadBool(MacVigilPreferenceKey.darkenBuiltinDisplayOnLidClose, into: &darkenBuiltinDisplayOnLidClose)
        loadBool(MacVigilPreferenceKey.enableBatterySafety, into: &enableBatterySafety)
        loadBool(MacVigilPreferenceKey.enableThermalSafety, into: &enableThermalSafety)
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(selectedDuration.rawValue, forKey: MacVigilPreferenceKey.selectedDuration)
        defaults.set(min(24 * 60, max(1, customMinutes)), forKey: MacVigilPreferenceKey.customMinutes)
        defaults.set(min(30, max(5, lowBatteryCutoff)), forKey: MacVigilPreferenceKey.lowBatteryCutoff)
        defaults.set(preventSystemSleep, forKey: MacVigilPreferenceKey.preventSystemSleep)
        defaults.set(preventIdleSystemSleep, forKey: MacVigilPreferenceKey.preventIdleSystemSleep)
        defaults.set(keepDisplayAwake, forKey: MacVigilPreferenceKey.keepDisplayAwake)
        defaults.set(vetoIdleSleepRequests, forKey: MacVigilPreferenceKey.vetoIdleSleepRequests)
        defaults.set(useGlobalSleepDisable, forKey: MacVigilPreferenceKey.useGlobalSleepDisable)
        defaults.set(useKernelLidGuard, forKey: MacVigilPreferenceKey.useKernelLidGuard)
        defaults.set(darkenBuiltinDisplayOnLidClose, forKey: MacVigilPreferenceKey.darkenBuiltinDisplayOnLidClose)
        defaults.set(enableBatterySafety, forKey: MacVigilPreferenceKey.enableBatterySafety)
        defaults.set(enableThermalSafety, forKey: MacVigilPreferenceKey.enableThermalSafety)
    }

    func resetPreferences() {
        guard !isActive else { return }

        selectedDuration = .oneHour
        customMinutes = 90
        lowBatteryCutoff = 15
        preventSystemSleep = true
        preventIdleSystemSleep = true
        keepDisplayAwake = false
        vetoIdleSleepRequests = true
        useGlobalSleepDisable = false
        useKernelLidGuard = false
        darkenBuiltinDisplayOnLidClose = false
        enableBatterySafety = true
        enableThermalSafety = true
        savePreferences()
    }

    var hasAcknowledgedClosedLidSafety: Bool {
        UserDefaults.standard.bool(forKey: MacVigilPreferenceKey.closedLidAcknowledged)
    }

    func acknowledgeClosedLidSafety() {
        UserDefaults.standard.set(true, forKey: MacVigilPreferenceKey.closedLidAcknowledged)
    }

    private func loadBool(_ key: String, into value: inout Bool) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return }
        value = defaults.bool(forKey: key)
    }
}
