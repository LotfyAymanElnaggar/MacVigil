import Foundation
import Combine
import IOKit
import IOKit.pwr_mgt

@MainActor
final class VigilManager: ObservableObject {
    // MARK: - User configuration

    @Published var selectedDuration: SessionDuration = .oneHour
    @Published var customMinutes = 90
    @Published var lowBatteryCutoff = 15

    // Every runtime behavior is independently configurable. Presets only set
    // these switches; the switches are the source of truth.
    @Published var preventSystemSleep = true
    @Published var preventIdleSystemSleep = true
    @Published var keepDisplayAwake = false
    @Published var vetoIdleSleepRequests = true
    @Published var useGlobalSleepDisable = false
    @Published var useKernelLidGuard = false
    @Published var darkenBuiltinDisplayOnLidClose = false
    @Published var enableBatterySafety = true
    @Published var enableThermalSafety = true

    // MARK: - Runtime state

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var remainingSeconds: TimeInterval?
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?

    // MARK: - Power / lid / display state

    @Published private(set) var authorizationInstalled = false
    @Published private(set) var pmsetPrivilegeAvailable = false
    @Published private(set) var sleepDisabledReadback = false
    @Published private(set) var lidModeActive = false
    @Published private(set) var lidIsClosed = false
    @Published private(set) var hasExternalDisplay = false
    @Published private(set) var kernelGuardActive = false
    @Published private(set) var kernelGuardStatus = "not armed"
    @Published private(set) var appleClamshellCausesSleep: Bool?
    @Published private(set) var backlightDimmed = false
    @Published private(set) var displayStatus = "Idle"

    // MARK: - Safety / diagnostics state

    @Published private(set) var batteryPercent: Int?
    @Published private(set) var onBatteryPower = false
    @Published private(set) var thermalStatus = "Nominal"
    @Published private(set) var lastSleepVetoAt: Date?
    @Published private(set) var lastSystemWillSleepAt: Date?
    @Published private(set) var lastSystemWakeAt: Date?

    private let ownershipKey = "MacVigil.ownsSleepDisabled"
    private let sudoersPath = "/etc/sudoers.d/macvigil"

    private let assertions = PowerAssertions()
    private let systemPowerVeto = SystemPowerVeto()
    private let lidGuard = RootDomainLidGuard()
    private let backlight = BacklightController()

    private var activityToken: NSObjectProtocol?
    private var ownsSleepDisabled = false
    private var prepared = false

    private var endTimer: Timer?
    private var ticker: Timer?
    private var safetyTimer: Timer?
    private var lidMonitorTimer: Timer?
    private var kernelHeartbeatTimer: Timer?

    private var wakeObserver: NSObjectProtocol?
    private var vetoObserver: NSObjectProtocol?
    private var willSleepObserver: NSObjectProtocol?

    private var watchdogTokenPath: String?
    private var watchdogBrightnessPath: String?
    private var watchdogProcess: Process?

    private var runtimeEvents: [String] = []

    // MARK: - Configuration helpers

    var closedLidProtectionRequested: Bool {
        useGlobalSleepDisable || useKernelLidGuard
    }

    var configurationName: String {
        if preventSystemSleep,
           preventIdleSystemSleep,
           !keepDisplayAwake,
           vetoIdleSleepRequests,
           !useGlobalSleepDisable,
           !useKernelLidGuard,
           !darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.computeGuard.title
        }

        if preventSystemSleep,
           preventIdleSystemSleep,
           !keepDisplayAwake,
           vetoIdleSleepRequests,
           useGlobalSleepDisable,
           useKernelLidGuard,
           darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.closedLidEco.title
        }

        if preventSystemSleep,
           preventIdleSystemSleep,
           keepDisplayAwake,
           vetoIdleSleepRequests,
           !useGlobalSleepDisable,
           !useKernelLidGuard,
           !darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.fullAwake.title
        }

        return "Custom Vigil"
    }

    var authorizationStatusText: String {
        if authorizationInstalled {
            return "MacVigil authorization installed"
        }
        if pmsetPrivilegeAvailable {
            return "Compatible pmset authorization available"
        }
        return "Authorization required for Global SleepDisabled"
    }

    func applyPreset(_ preset: RuntimeProfile) {
        guard !isActive else { return }

        preventSystemSleep = true
        preventIdleSystemSleep = true
        vetoIdleSleepRequests = true
        enableBatterySafety = true
        enableThermalSafety = true

        switch preset {
        case .computeGuard:
            keepDisplayAwake = false
            useGlobalSleepDisable = false
            useKernelLidGuard = false
            darkenBuiltinDisplayOnLidClose = false

        case .closedLidEco:
            keepDisplayAwake = false
            useGlobalSleepDisable = true
            useKernelLidGuard = true
            darkenBuiltinDisplayOnLidClose = true

        case .fullAwake:
            keepDisplayAwake = true
            useGlobalSleepDisable = false
            useKernelLidGuard = false
            darkenBuiltinDisplayOnLidClose = false
        }

        statusMessage = "Applied \(preset.title) preset. You can still change any switch before starting."
    }

    // MARK: - Lifecycle

    func prepareOnLaunch() async {
        guard !prepared else { return }
        prepared = true

        installPowerNotifications()
        refreshLocalHardwareState(forceDisplayAction: false)
        await refreshAuthorizationStatus()
        await refreshSleepDisabledState()
        await refreshBatteryState()
        refreshThermalState()
        recordEvent("app prepared")

        // Recover only a global pmset setting that MacVigil explicitly marked
        // as its own. Never disable another utility's pre-existing setting.
        if UserDefaults.standard.bool(forKey: ownershipKey) {
            _ = lidGuard.setArmed(false)
            kernelGuardActive = false
            kernelGuardStatus = lidGuard.lastStatus

            if sleepDisabledReadback, pmsetPrivilegeAvailable {
                if await setGlobalSleepDisabled(false) {
                    UserDefaults.standard.set(false, forKey: ownershipKey)
                    ownsSleepDisabled = false
                    statusMessage = "Recovered normal sleep after an interrupted MacVigil session."
                    recordEvent("recovered stale SleepDisabled=1 from previous session")
                } else {
                    lastError = "A previous MacVigil session may still have SleepDisabled enabled. Run: sudo pmset -a disablesleep 0"
                }
            } else if !sleepDisabledReadback {
                UserDefaults.standard.set(false, forKey: ownershipKey)
                ownsSleepDisabled = false
            }
        }
    }

    func startSelectedSession() async {
        guard !isActive else { return }
        lastError = nil
        statusMessage = nil

        let hasProtection = preventSystemSleep
            || preventIdleSystemSleep
            || keepDisplayAwake
            || vetoIdleSleepRequests
            || useGlobalSleepDisable
            || useKernelLidGuard

        guard hasProtection else {
            lastError = "Turn on at least one protection switch before starting Vigil."
            return
        }

        if useGlobalSleepDisable {
            await refreshAuthorizationStatus()
            guard pmsetPrivilegeAvailable else {
                lastError = authorizationInstalled
                    ? "MacVigil's authorization exists, but sudo is not accepting the two required pmset commands."
                    : "Global SleepDisabled needs authorization. Install it in the Closed-lid section or turn that switch off."
                return
            }
        }

        let reason = "MacVigil runtime protection enabled by user"
        let assertionResult = assertions.start(
            preventSystemSleep: preventSystemSleep,
            preventIdleSystemSleep: preventIdleSystemSleep,
            keepDisplayAwake: keepDisplayAwake,
            reason: reason
        )
        guard assertionResult == kIOReturnSuccess else {
            lastError = "Could not create the selected macOS power assertions (IOKit error \(assertionResult))."
            return
        }

        var activityOptions: ProcessInfo.ActivityOptions = [.userInitiated]
        if preventIdleSystemSleep { activityOptions.insert(.idleSystemSleepDisabled) }
        if keepDisplayAwake { activityOptions.insert(.idleDisplaySleepDisabled) }
        activityToken = ProcessInfo.processInfo.beginActivity(options: activityOptions, reason: reason)

        systemPowerVeto.setEnabled(vetoIdleSleepRequests)
        isActive = true
        recordEvent("session started: \(configurationName)")

        if closedLidProtectionRequested {
            guard await armClosedLidMode() else {
                stopCore()
                return
            }
        }

        configureDurationTimer()
        startSafetyTimer()
        statusMessage = "\(configurationName) is active."
    }

    func stopSession() async {
        let shouldDisarmLid = lidModeActive
            || kernelGuardActive
            || ownsSleepDisabled
            || UserDefaults.standard.bool(forKey: ownershipKey)

        recordEvent("session stop requested")
        stopCore()
        if shouldDisarmLid {
            await disarmClosedLidMode()
        }
        statusMessage = "Normal macOS sleep behavior restored."
    }

    func handleAppTermination() {
        recordEvent("application terminating")
        systemPowerVeto.setEnabled(false)
        assertions.stop()

        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }

        backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
        removeWatchdogToken()
        _ = lidGuard.setArmed(false)
        kernelGuardActive = false
    }

    // MARK: - Authorization

    func installClosedLidAuthorization() async {
        lastError = nil
        statusMessage = nil

        let username = NSUserName()
        guard username.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            lastError = "Your macOS username contains characters the authorization installer does not support."
            return
        }

        let rule = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        let safeRule = rule.replacingOccurrences(of: "'", with: "'\\''")
        let tempPath = "/tmp/macvigil.sudoers.\(getpid())"
        let command = "umask 077; printf '%s\\n' '\(safeRule)' > '\(tempPath)' && /usr/sbin/visudo -cf '\(tempPath)' && /usr/sbin/chown root:wheel '\(tempPath)' && /bin/chmod 0440 '\(tempPath)' && /bin/mkdir -p /etc/sudoers.d && /bin/mv '\(tempPath)' '\(sudoersPath)' && /usr/sbin/visudo -cf '\(sudoersPath)'"

        let result = await ShellRunner.runAdministratorCommand(command)
        await refreshAuthorizationStatus()

        if result.succeeded && authorizationInstalled && pmsetPrivilegeAvailable {
            statusMessage = "Closed-lid authorization installed. It permits only pmset disablesleep 1 and 0."
            recordEvent("MacVigil sudoers authorization installed")
        } else if result.succeeded && authorizationInstalled {
            lastError = "The authorization file was installed, but sudo did not make the two exact pmset commands available."
        } else {
            lastError = "Could not install closed-lid authorization. \(ShellRunner.cleanError(result))"
        }
    }

    func removeClosedLidAuthorization() async {
        lastError = nil
        statusMessage = nil

        if lidModeActive || kernelGuardActive || ownsSleepDisabled || UserDefaults.standard.bool(forKey: ownershipKey) {
            await disarmClosedLidMode()
        }

        let result = await ShellRunner.runAdministratorCommand("/bin/rm -f '\(sudoersPath)'")
        await refreshAuthorizationStatus()

        if result.succeeded && !authorizationInstalled {
            statusMessage = pmsetPrivilegeAvailable
                ? "MacVigil authorization removed. Another compatible sudoers rule still provides pmset access."
                : "MacVigil closed-lid authorization removed."
            recordEvent("MacVigil sudoers authorization removed")
        } else {
            lastError = "Could not remove MacVigil's authorization. \(ShellRunner.cleanError(result))"
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationInstalled = FileManager.default.fileExists(atPath: sudoersPath)

        let enable = await ShellRunner.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        let disable = await ShellRunner.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        pmsetPrivilegeAvailable = enable.succeeded && disable.succeeded
    }

    // MARK: - Closed-lid protection

    private func armClosedLidMode() async -> Bool {
        var enabledPMSetThisTime = false

        if useGlobalSleepDisable {
            await refreshSleepDisabledState()
            if sleepDisabledReadback {
                ownsSleepDisabled = UserDefaults.standard.bool(forKey: ownershipKey)
                recordEvent("Global SleepDisabled already active before MacVigil arm")
            } else {
                guard await setGlobalSleepDisabled(true) else { return false }
                ownsSleepDisabled = true
                enabledPMSetThisTime = true
                UserDefaults.standard.set(true, forKey: ownershipKey)
                recordEvent("Global SleepDisabled=1 armed and verified")
            }
        }

        if useKernelLidGuard {
            guard lidGuard.setArmed(true) else {
                kernelGuardStatus = lidGuard.lastStatus
                kernelGuardActive = false
                if enabledPMSetThisTime {
                    _ = await setGlobalSleepDisabled(false)
                    ownsSleepDisabled = false
                    UserDefaults.standard.set(false, forKey: ownershipKey)
                }
                lastError = "The macOS kernel rejected the experimental clamshell guard. Closed-lid protection was not armed."
                recordEvent("kernel clamshell guard rejected: \(lidGuard.lastStatus)")
                return false
            }
            kernelGuardActive = true
            kernelGuardStatus = lidGuard.lastStatus
            recordEvent("kernel clamshell guard armed: \(lidGuard.lastStatus)")
        } else {
            kernelGuardActive = false
            kernelGuardStatus = "disabled by user"
        }

        lidModeActive = true

        guard installWatchdog() else {
            lastError = lastError ?? "Closed-lid protection requires its crash-recovery watchdog, but the watchdog could not start."
            await rollbackFailedClosedLidArm(enabledPMSetThisTime: enabledPMSetThisTime)
            return false
        }

        startLidMonitor()
        startKernelHeartbeat()
        refreshLocalHardwareState(forceDisplayAction: true)
        await refreshBatteryState()
        await refreshSleepDisabledState()

        if enableBatterySafety,
           onBatteryPower,
           let batteryPercent,
           batteryPercent <= max(5, lowBatteryCutoff) {
            lastError = "Closed-lid protection was stopped because the battery is already at the configured reserve."
            await disarmClosedLidMode()
            return false
        }

        recordEvent(
            "closed-lid protection ready: SleepDisabled=\(sleepDisabledReadback), kernel=\(kernelGuardActive), AppleClamshellCausesSleep=\(appleClamshellCausesSleep.map(String.init) ?? "unknown")"
        )
        return true
    }

    private func rollbackFailedClosedLidArm(enabledPMSetThisTime: Bool) async {
        lidModeActive = false
        stopLidMonitor()
        stopKernelHeartbeat()
        removeWatchdogToken()
        backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
        _ = lidGuard.setArmed(false)
        kernelGuardActive = false
        kernelGuardStatus = lidGuard.lastStatus

        if enabledPMSetThisTime {
            _ = await setGlobalSleepDisabled(false)
            ownsSleepDisabled = false
            UserDefaults.standard.set(false, forKey: ownershipKey)
        }
    }

    private func disarmClosedLidMode() async {
        recordEvent("disarming closed-lid protection")
        lidModeActive = false
        stopLidMonitor()
        stopKernelHeartbeat()

        backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
        syncDisplayPublishedState()
        removeWatchdogToken()

        _ = lidGuard.setArmed(false)
        kernelGuardActive = false
        kernelGuardStatus = lidGuard.lastStatus

        let markerOwned = UserDefaults.standard.bool(forKey: ownershipKey)
        if ownsSleepDisabled || markerOwned {
            if await setGlobalSleepDisabled(false) {
                ownsSleepDisabled = false
                UserDefaults.standard.set(false, forKey: ownershipKey)
                recordEvent("Global SleepDisabled=0 restored")
            } else {
                lastError = "Could not restore SleepDisabled=0. Run: sudo pmset -a disablesleep 0"
            }
        } else {
            await refreshSleepDisabledState()
        }

        lidGuard.close()
    }

    private func reinforceClosedLidProtection(source: String) async {
        guard isActive, lidModeActive else { return }

        if useKernelLidGuard {
            _ = lidGuard.setArmed(true)
            kernelGuardActive = lidGuard.isArmed
            kernelGuardStatus = lidGuard.lastStatus
        }

        if useGlobalSleepDisable {
            await refreshSleepDisabledState()
            if !sleepDisabledReadback {
                if await setGlobalSleepDisabled(true) {
                    ownsSleepDisabled = true
                    UserDefaults.standard.set(true, forKey: ownershipKey)
                    recordEvent("\(source): SleepDisabled had dropped; re-armed to 1")
                } else {
                    recordEvent("\(source): FAILED to re-arm SleepDisabled")
                }
            }
        }

        touchWatchdogToken()
    }

    private func setGlobalSleepDisabled(_ enabled: Bool) async -> Bool {
        let value = enabled ? "1" : "0"
        let result = await ShellRunner.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])

        guard result.succeeded else {
            lastError = "pmset failed. \(ShellRunner.cleanError(result))"
            return false
        }

        await refreshSleepDisabledState()
        return sleepDisabledReadback == enabled
    }

    func refreshSleepDisabledState() async {
        let result = await ShellRunner.run("/usr/bin/pmset", ["-g"])
        sleepDisabledReadback = parseSleepDisabled(result.stdout)
    }

    // MARK: - Lid / display monitoring

    private func startLidMonitor() {
        lidMonitorTimer?.invalidate()
        lidMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLocalHardwareState(forceDisplayAction: false)
            }
        }
        lidMonitorTimer?.tolerance = 0.03
    }

    private func stopLidMonitor() {
        lidMonitorTimer?.invalidate()
        lidMonitorTimer = nil
    }

    private func startKernelHeartbeat() {
        kernelHeartbeatTimer?.invalidate()
        kernelHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.reinforceClosedLidProtection(source: "heartbeat")
            }
        }
        kernelHeartbeatTimer?.tolerance = 0.25
    }

    private func stopKernelHeartbeat() {
        kernelHeartbeatTimer?.invalidate()
        kernelHeartbeatTimer = nil
    }

    private func refreshLocalHardwareState(forceDisplayAction: Bool) {
        let wasClosed = lidIsClosed
        lidIsClosed = lidGuard.readBool("AppleClamshellState") ?? lidIsClosed
        appleClamshellCausesSleep = lidGuard.readBool("AppleClamshellCausesSleep")
        hasExternalDisplay = backlight.hasExternalDisplay()

        guard lidModeActive else {
            syncDisplayPublishedState()
            return
        }

        let changedToClosed = lidIsClosed && !wasClosed
        let changedToOpen = !lidIsClosed && wasClosed

        if changedToClosed {
            recordEvent("physical lid closed")
            // Re-assert both layers immediately on the physical edge. This is
            // intentionally in addition to the periodic heartbeat/watchdog.
            Task { @MainActor [weak self] in
                await self?.reinforceClosedLidProtection(source: "lid-close edge")
            }
        } else if changedToOpen {
            recordEvent("physical lid opened")
        }

        if changedToOpen || !lidIsClosed {
            backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
            displayStatus = "Built-in display available."
            syncDisplayPublishedState()
            return
        }

        if hasExternalDisplay {
            backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
            displayStatus = "Lid closed · external display detected; built-in backlight override skipped."
            syncDisplayPublishedState()
            return
        }

        guard darkenBuiltinDisplayOnLidClose else {
            backlight.restoreBuiltinDisplay(from: watchdogBrightnessPath)
            displayStatus = "Lid closed · built-in backlight control disabled by user."
            syncDisplayPublishedState()
            return
        }

        if changedToClosed || forceDisplayAction || !backlight.isDimmed {
            backlight.dimBuiltinDisplay(saveTo: watchdogBrightnessPath)
        }
        syncDisplayPublishedState()
    }

    private func syncDisplayPublishedState() {
        backlightDimmed = backlight.isDimmed
        if backlight.status != "idle" { displayStatus = backlight.status }
    }

    // MARK: - Battery / thermal safety

    func refreshBatteryState() async {
        let result = await ShellRunner.run("/usr/bin/pmset", ["-g", "batt"])
        onBatteryPower = result.stdout.localizedCaseInsensitiveContains("Battery Power")

        if let match = result.stdout.range(of: #"\b(\d{1,3})%"#, options: .regularExpression) {
            batteryPercent = Int(result.stdout[match].dropLast())
        } else {
            batteryPercent = nil
        }
    }

    private func refreshThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalStatus = "Nominal"
        case .fair: thermalStatus = "Fair"
        case .serious: thermalStatus = "Serious"
        case .critical: thermalStatus = "Critical"
        @unknown default: thermalStatus = "Unknown"
        }
    }

    private func startSafetyTimer() {
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }

                await self.refreshBatteryState()
                self.refreshThermalState()

                if self.enableBatterySafety,
                   self.lidModeActive,
                   self.onBatteryPower,
                   let batteryPercent = self.batteryPercent,
                   batteryPercent <= max(5, self.lowBatteryCutoff) {
                    let message = "Closed-lid protection stopped at \(batteryPercent)% to preserve the configured battery reserve."
                    self.recordEvent("battery safety stop at \(batteryPercent)%")
                    await self.stopSession()
                    self.lastError = message
                    return
                }

                if self.enableThermalSafety,
                   self.lidModeActive,
                   ProcessInfo.processInfo.thermalState == .critical {
                    let message = "Closed-lid protection stopped because macOS reports critical thermal pressure."
                    self.recordEvent("critical thermal safety stop")
                    await self.stopSession()
                    self.lastError = message
                }
            }
        }
        safetyTimer?.tolerance = 1
    }

    // MARK: - Session timing

    private func configureDurationTimer() {
        endTimer?.invalidate()
        ticker?.invalidate()

        let interval = selectedDuration.interval(customMinutes: customMinutes)
        guard let interval else {
            endDate = nil
            remainingSeconds = nil
            return
        }

        let safeInterval = max(1, interval)
        let deadline = Date().addingTimeInterval(safeInterval)
        endDate = deadline
        remainingSeconds = safeInterval

        endTimer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordEvent("duration timer expired")
                await self.stopSession()
            }
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let endDate = self.endDate else { return }
                self.remainingSeconds = max(0, endDate.timeIntervalSinceNow)
            }
        }
    }

    private func stopCore() {
        endTimer?.invalidate()
        ticker?.invalidate()
        safetyTimer?.invalidate()
        endTimer = nil
        ticker = nil
        safetyTimer = nil
        endDate = nil
        remainingSeconds = nil

        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }

        systemPowerVeto.setEnabled(false)
        assertions.stop()
        isActive = false
    }

    // MARK: - Watchdog

    @discardableResult
    private func installWatchdog() -> Bool {
        removeWatchdogToken()

        let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MacVigil", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            let tokenURL = cacheDirectory.appendingPathComponent("lid-watchdog.token")
            let brightnessURL = cacheDirectory.appendingPathComponent("lid-watchdog.brightness")
            let token = UUID().uuidString

            try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: brightnessURL)
            watchdogTokenPath = tokenURL.path
            watchdogBrightnessPath = brightnessURL.path

            guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
                lastError = "Closed-lid protection is active, but the watchdog executable directory could not be found."
                return false
            }

            let helperURL = executableDirectory.appendingPathComponent("MacVigilWatchdog")
            guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
                lastError = "MacVigilWatchdog is missing from this build. Closed-lid protection was not started."
                return false
            }

            let process = Process()
            process.executableURL = helperURL
            process.arguments = [
                "\(getpid())",
                tokenURL.path,
                token,
                brightnessURL.path,
                "\(backlight.builtinDisplayIdentifier())",
                ownsSleepDisabled ? "1" : "0",
                useKernelLidGuard ? "1" : "0"
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            watchdogProcess = process
            recordEvent("crash watchdog started pid=\(process.processIdentifier)")
            return true
        } catch {
            lastError = "Closed-lid protection could not start its crash watchdog: \(error.localizedDescription)"
            return false
        }
    }

    private func touchWatchdogToken() {
        guard let path = watchdogTokenPath else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
    }

    private func removeWatchdogToken() {
        if let path = watchdogTokenPath { try? FileManager.default.removeItem(atPath: path) }
        watchdogTokenPath = nil
        watchdogProcess = nil
    }

    // MARK: - System power notifications

    private func installPowerNotifications() {
        guard wakeObserver == nil, vetoObserver == nil, willSleepObserver == nil else { return }

        wakeObserver = NotificationCenter.default.addObserver(
            forName: .macVigilSystemPoweredOn,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastSystemWakeAt = Date()
                self.recordEvent("IOKit system powered-on notification")
                guard self.isActive, self.lidModeActive else { return }
                await self.reinforceClosedLidProtection(source: "system wake")
                self.refreshLocalHardwareState(forceDisplayAction: true)
            }
        }

        vetoObserver = NotificationCenter.default.addObserver(
            forName: .macVigilSleepVetoed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastSleepVetoAt = Date()
                self.recordEvent("idle system-sleep request vetoed")
            }
        }

        willSleepObserver = NotificationCenter.default.addObserver(
            forName: .macVigilSystemWillSleep,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastSystemWillSleepAt = Date()
                self.recordEvent("SYSTEM WILL SLEEP notification received")
            }
        }
    }

    // MARK: - Diagnostics

    func diagnostics() async -> String {
        await refreshAuthorizationStatus()
        await refreshSleepDisabledState()
        await refreshBatteryState()
        refreshThermalState()
        refreshLocalHardwareState(forceDisplayAction: false)

        async let pmset = ShellRunner.run("/usr/bin/pmset", ["-g"])
        async let assertionsOutput = ShellRunner.run("/usr/bin/pmset", ["-g", "assertions"])
        async let battery = ShellRunner.run("/usr/bin/pmset", ["-g", "batt"])
        async let clamshell = ShellRunner.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"])
        async let sleepLog = ShellRunner.run("/bin/sh", ["-c", "/usr/bin/pmset -g log | /usr/bin/tail -n 120"])

        let (pmsetResult, assertionsResult, batteryResult, clamshellResult, sleepLogResult) = await (
            pmset, assertionsOutput, battery, clamshell, sleepLog
        )

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let batteryText = batteryPercent.map(String.init) ?? "unknown"
        let clamshellSleepText = appleClamshellCausesSleep.map { $0 ? "true" : "false" } ?? "unknown"
        let kernelReturn = String(format: "0x%08x", UInt32(bitPattern: lidGuard.lastReturn))
        let events = runtimeEvents.isEmpty ? "none" : runtimeEvents.joined(separator: "\n")

        return """
        MacVigil diagnostics
        Version: \(version)
        Session active: \(isActive)
        Configuration: \(configurationName)

        --- user switches ---
        Prevent system sleep: \(preventSystemSleep)
        Prevent idle system sleep: \(preventIdleSystemSleep)
        Keep display awake: \(keepDisplayAwake)
        Veto idle sleep requests: \(vetoIdleSleepRequests)
        Global SleepDisabled: \(useGlobalSleepDisable)
        Kernel clamshell guard: \(useKernelLidGuard)
        Darken built-in display on lid close: \(darkenBuiltinDisplayOnLidClose)
        Battery reserve safety: \(enableBatterySafety)
        Critical thermal safety: \(enableThermalSafety)

        --- live state ---
        MacVigil authorization installed: \(authorizationInstalled)
        pmset privilege available: \(pmsetPrivilegeAvailable)
        Closed-lid mode active: \(lidModeActive)
        Physical lid closed: \(lidIsClosed)
        External display detected: \(hasExternalDisplay)
        Kernel lid guard active: \(kernelGuardActive)
        Kernel selector status: \(kernelGuardStatus)
        Kernel selector return: \(kernelReturn)
        AppleClamshellCausesSleep: \(clamshellSleepText)
        SleepDisabled readback: \(sleepDisabledReadback)
        MacVigil owns SleepDisabled: \(ownsSleepDisabled)
        Backlight dimmed by MacVigil: \(backlightDimmed)
        Display status: \(displayStatus)
        Battery: \(batteryText)% / on battery: \(onBatteryPower)
        Battery reserve: \(lowBatteryCutoff)%
        Thermal pressure: \(thermalStatus)
        Last idle-sleep veto: \(timestamp(lastSleepVetoAt))
        Last SYSTEM WILL SLEEP: \(timestamp(lastSystemWillSleepAt))
        Last system powered-on: \(timestamp(lastSystemWakeAt))

        --- MacVigil runtime event trail ---
        \(events)

        --- pmset -g ---
        \(pmsetResult.stdout)
        \(pmsetResult.stderr)

        --- pmset -g assertions ---
        \(assertionsResult.stdout)
        \(assertionsResult.stderr)

        --- pmset -g batt ---
        \(batteryResult.stdout)
        \(batteryResult.stderr)

        --- ioreg clamshell ---
        \(clamshellResult.stdout)
        \(clamshellResult.stderr)

        --- recent pmset sleep/wake log (last 120 lines) ---
        \(sleepLogResult.stdout)
        \(sleepLogResult.stderr)
        """
    }

    private func parseSleepDisabled(_ text: String) -> Bool {
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.contains("sleepdisabled") || lower.contains("disablesleep") {
                if let last = line.split(whereSeparator: { $0.isWhitespace }).last {
                    return last == "1"
                }
            }
        }
        return false
    }

    private func recordEvent(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        runtimeEvents.append("\(stamp)  \(message)")
        if runtimeEvents.count > 50 {
            runtimeEvents.removeFirst(runtimeEvents.count - 50)
        }
    }

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "none" }
        return ISO8601DateFormatter().string(from: date)
    }

    deinit {
        endTimer?.invalidate()
        ticker?.invalidate()
        safetyTimer?.invalidate()
        lidMonitorTimer?.invalidate()
        kernelHeartbeatTimer?.invalidate()
        systemPowerVeto.setEnabled(false)
        assertions.stop()

        if let wakeObserver { NotificationCenter.default.removeObserver(wakeObserver) }
        if let vetoObserver { NotificationCenter.default.removeObserver(vetoObserver) }
        if let willSleepObserver { NotificationCenter.default.removeObserver(willSleepObserver) }
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
    }
}
