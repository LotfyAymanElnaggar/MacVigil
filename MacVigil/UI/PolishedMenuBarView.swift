import SwiftUI
import AppKit

struct PolishedMenuBarView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager

    @State private var showAdvanced = false
    @State private var showUpdates = false
    @State private var copyingDiagnostics = false
    @State private var showClosedLidConfirmation = false
    @State private var showActiveUpdateConfirmation = false
    @State private var pendingMode: RuntimeProfile?
    @State private var liveNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if updater.hasUpdate { updateBanner }
                vigilCard
                modeSection
                durationSection
                confirmationSection
                advancedSection
                updatesSection
                messageSection
                footer
            }
            .padding(18)
        }
        .frame(width: 448, height: 720)
        .task {
            manager.loadPreferences()
            await manager.prepareOnLaunch()
            updater.startPeriodicChecks()
            if updater.automaticChecksEnabled {
                await updater.checkForUpdates(userInitiated: false)
                await installAutomaticallyIfEligible()
            }
        }
        .onChange(of: manager.isActive) { active in
            if !active {
                Task { await installAutomaticallyIfEligible() }
            }
        }
        .onChange(of: updater.automaticChecksEnabled) { enabled in
            updater.savePreferences()
            updater.startPeriodicChecks()
            if enabled {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
        }
        .onChange(of: updater.automaticInstallEnabled) { enabled in
            if enabled && !updater.automaticChecksEnabled {
                updater.automaticChecksEnabled = true
            }
            updater.savePreferences()
            if enabled {
                Task { await installAutomaticallyIfEligible() }
            }
        }
        .alert("Use Closed-Lid Eco?", isPresented: $showClosedLidConfirmation) {
            Button("Cancel", role: .cancel) { pendingMode = nil }
            Button("Continue") {
                manager.acknowledgeClosedLidSafety()
                let mode = pendingMode ?? .closedLidEco
                pendingMode = nil
                Task { await applyMode(mode) }
            }
        } message: {
            Text("Closed-lid workloads can generate heat. Keep the MacBook on a ventilated surface. MacVigil does not weaken your password or Lock Screen settings, and mandatory macOS safety behavior remains in control.")
        }
        .alert("Update MacVigil now?", isPresented: $showActiveUpdateConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Stop Vigil & Update") {
                Task {
                    await manager.stopLiveSession()
                    await updater.installAvailableUpdate()
                }
            }
        } message: {
            Text("Updating restarts MacVigil, so the active Vigil session must stop first. Your saved settings will be kept.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)

                Image(systemName: updater.hasUpdate ? "arrow.down.circle.fill" : (manager.isActive ? "bolt.shield.fill" : "bolt.shield"))
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacVigil")
                    .font(.title2.weight(.semibold))
                Text("Local work, uninterrupted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(manager.isActive ? "ACTIVE" : "READY")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(manager.isActive ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                .foregroundStyle(manager.isActive ? Color.green : Color.secondary)
                .clipShape(Capsule())
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacVigil \(updater.availableVersion ?? "update") is available")
                    .font(.subheadline.weight(.semibold))
                Text(updateBannerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(updater.isInstalling ? "Updating…" : "Update Now") {
                requestManualUpdate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(updater.isInstalling)
            .help("Download, verify, install, and restart MacVigil")
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var vigilCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(modeName)
                        .font(.headline)
                    Text(runtimeSubtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Vigil", isOn: vigilBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .help(manager.isActive ? "Stop Vigil" : "Start Vigil")
            }

            if manager.isActive {
                Divider()
                statusRow("System sleep", value: manager.preventSystemSleep ? "Protected" : "Allowed", icon: "cpu")
                statusRow("Idle sleep", value: manager.preventIdleSystemSleep ? "Protected" : "Allowed", icon: "clock")
                statusRow("Display sleep", value: manager.keepDisplayAwake ? "Blocked" : "Allowed", icon: "display")

                if manager.closedLidProtectionRequested {
                    statusRow("SleepDisabled", value: manager.useGlobalSleepDisable ? (manager.sleepDisabledReadback ? "Verified" : "Not verified") : "Off", icon: "lock.shield")
                    statusRow("Lid guard", value: manager.useKernelLidGuard ? (manager.kernelGuardActive ? "Armed" : "Not armed") : "Off", icon: "laptopcomputer")
                }

                statusRow("Battery", value: powerValue, icon: "battery.75percent")
                statusRow("Thermal", value: manager.thermalStatus, icon: "thermometer.medium")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionTitle("Mode", icon: "square.grid.2x2")
                Spacer()
                if manager.isActive {
                    Label("Live", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ModeCardButton(
                    preset: .computeGuard,
                    icon: "cpu",
                    selected: isPresetSelected(.computeGuard),
                    disabled: modeLocked(.computeGuard)
                ) { selectMode(.computeGuard) }

                ModeCardButton(
                    preset: .closedLidEco,
                    icon: "laptopcomputer",
                    selected: isPresetSelected(.closedLidEco),
                    disabled: false
                ) { selectMode(.closedLidEco) }

                ModeCardButton(
                    preset: .fullAwake,
                    icon: "sun.max",
                    selected: isPresetSelected(.fullAwake),
                    disabled: modeLocked(.fullAwake)
                ) { selectMode(.fullAwake) }
            }

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if liveLidTransitionLocked {
                Label("Open the lid before switching away from Closed-Lid Eco or removing lid/display protection.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Duration", icon: "timer")
                Spacer()
                if manager.isActive {
                    Text("Mode changes keep this timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Picker("Duration", selection: durationBinding) {
                    ForEach(SessionDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("Changing duration intentionally starts a new countdown")

                if manager.selectedDuration == .custom {
                    Spacer()
                    TextField("Minutes", value: $manager.customMinutes, format: .number)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)

                    Button("Apply") {
                        Task {
                            let ok = await manager.changeDurationLive(.custom, customMinutes: manager.customMinutes)
                            liveNotice = ok ? "Custom duration applied." : "The custom duration could not be applied."
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(manager.isActive ? "Live confirmation" : "Ready check", icon: "checkmark.seal")

            confirmationRow("Runtime protection", detail: runtimeProtectionReady ? "Configured" : "Choose at least one protection", confirmed: runtimeProtectionReady)

            if manager.closedLidProtectionRequested {
                confirmationRow(
                    "Authorization",
                    detail: manager.useGlobalSleepDisable ? (manager.pmsetPrivilegeAvailable ? "Available" : "Required") : "Not required",
                    confirmed: !manager.useGlobalSleepDisable || manager.pmsetPrivilegeAvailable
                )
                confirmationRow(
                    "Display policy",
                    detail: manager.keepDisplayAwake ? "Display sleep blocked; backlight can still darken" : "Display sleep may invoke Lock Screen",
                    confirmed: manager.keepDisplayAwake
                )
                if manager.isActive && manager.useGlobalSleepDisable {
                    confirmationRow("SleepDisabled", detail: manager.sleepDisabledReadback ? "Verified ON" : "Not verified", confirmed: manager.sleepDisabledReadback)
                }
                if manager.isActive && manager.useKernelLidGuard {
                    confirmationRow("Kernel lid guard", detail: manager.kernelGuardStatus, confirmed: manager.kernelGuardActive)
                }
            }

            confirmationRow(
                "Safety cutoffs",
                detail: manager.enableBatterySafety && manager.enableThermalSafety ? "Battery + thermal enabled" : "Customized",
                confirmed: manager.enableBatterySafety && manager.enableThermalSafety
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 8) {
                InteractiveToggleRow(
                    title: "Prevent system sleep",
                    subtitle: "Protect long-running work from system sleep.",
                    isOn: manager.preventSystemSleep
                ) { changeOption(.preventSystemSleep, to: $0) }

                InteractiveToggleRow(
                    title: "Prevent idle system sleep",
                    subtitle: "Keep the Mac available without keyboard or mouse activity.",
                    isOn: manager.preventIdleSystemSleep
                ) { changeOption(.preventIdleSystemSleep, to: $0) }

                InteractiveToggleRow(
                    title: "Prevent display sleep",
                    subtitle: "Block display sleep. Closed-Lid Eco can still darken the built-in backlight.",
                    isOn: manager.keepDisplayAwake,
                    enabled: !liveLidTransitionLocked
                ) { changeOption(.keepDisplayAwake, to: $0) }

                InteractiveToggleRow(
                    title: "Veto idle sleep requests",
                    subtitle: "Reject cancellable idle-sleep requests while Vigil is active.",
                    isOn: manager.vetoIdleSleepRequests
                ) { changeOption(.vetoIdleSleepRequests, to: $0) }

                Divider().padding(.vertical, 2)
                sectionTitle("Closed-lid", icon: "laptopcomputer")

                InteractiveToggleRow(
                    title: "Global SleepDisabled",
                    subtitle: "Use macOS global SleepDisabled while the session is active.",
                    isOn: manager.useGlobalSleepDisable,
                    enabled: !liveLidTransitionLocked
                ) { changeOption(.useGlobalSleepDisable, to: $0) }

                InteractiveToggleRow(
                    title: "Kernel clamshell guard",
                    subtitle: "Use the experimental closed-lid guard.",
                    isOn: manager.useKernelLidGuard,
                    enabled: !liveLidTransitionLocked
                ) { changeOption(.useKernelLidGuard, to: $0) }

                InteractiveToggleRow(
                    title: "Darken built-in display on lid close",
                    subtitle: "Set the built-in backlight to 0 when appropriate.",
                    isOn: manager.darkenBuiltinDisplayOnLidClose,
                    enabled: !liveLidTransitionLocked && manager.closedLidProtectionRequested
                ) { changeOption(.darkenBuiltinDisplayOnLidClose, to: $0) }

                authorizationRow

                Divider().padding(.vertical, 2)
                sectionTitle("Safety", icon: "leaf")

                InteractiveToggleRow(
                    title: "Battery reserve cutoff",
                    subtitle: "Release closed-lid protection at the configured reserve.",
                    isOn: manager.enableBatterySafety
                ) { changeOption(.enableBatterySafety, to: $0) }

                HStack {
                    Text("Battery reserve")
                    Spacer()
                    Picker("Battery reserve", selection: $manager.lowBatteryCutoff) {
                        ForEach([5, 10, 15, 20, 25, 30], id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: manager.lowBatteryCutoff) { _ in manager.savePreferences() }
                }
                .font(.subheadline)
                .padding(.horizontal, 8)

                InteractiveToggleRow(
                    title: "Critical thermal cutoff",
                    subtitle: "Release closed-lid protection if macOS reports critical thermal pressure.",
                    isOn: manager.enableThermalSafety
                ) { changeOption(.enableThermalSafety, to: $0) }

                Button("Reset options to defaults") {
                    manager.resetPreferences()
                    liveNotice = "Options reset to defaults."
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isActive)
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced controls", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
        }
    }

    private var updatesSection: some View {
        DisclosureGroup(isExpanded: $showUpdates) {
            VStack(alignment: .leading, spacing: 10) {
                InteractivePreferenceToggle(
                    title: "Check automatically",
                    subtitle: "Check GitHub on launch and periodically while MacVigil is running.",
                    isOn: $updater.automaticChecksEnabled
                )

                InteractivePreferenceToggle(
                    title: "Install automatically",
                    subtitle: "Verified updates install automatically when no Vigil session is active.",
                    isOn: $updater.automaticInstallEnabled
                )

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current version \(updater.currentVersion)")
                            .font(.caption.weight(.medium))
                        if let status = updater.statusText {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(updater.isChecking ? "Checking…" : "Check Now") {
                        Task { await updater.checkForUpdates(userInitiated: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updater.isChecking || updater.isInstalling)
                }

                if updater.hasUpdate {
                    HStack {
                        Button("Release Notes") { updater.openReleasePage() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                        Button("Update Now") { requestManualUpdate() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(updater.isInstalling)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                if updater.hasUpdate {
                    Text("NEW")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var authorizationRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: manager.pmsetPrivilegeAvailable ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundStyle(manager.pmsetPrivilegeAvailable ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.authorizationStatusText)
                    .font(.subheadline.weight(.medium))
                Text("Authorization is only needed for Global SleepDisabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(manager.authorizationInstalled ? "Remove…" : "Install…") {
                Task {
                    if manager.authorizationInstalled {
                        await manager.removeClosedLidAuthorization()
                    } else {
                        await manager.installClosedLidAuthorization()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.isActive)
        }
        .padding(8)
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = manager.lastError ?? updater.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let notice = liveNotice {
            Label(notice, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let message = manager.statusMessage {
            Label(message, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(copyingDiagnostics ? "Copied" : "Copy Diagnostics") {
                copyingDiagnostics = true
                Task {
                    let text = await manager.diagnostics()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    copyingDiagnostics = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("Quit MacVigil") {
                manager.handleAppTermination()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .font(.caption)
    }

    private var vigilBinding: Binding<Bool> {
        Binding(
            get: { manager.isActive },
            set: { enabled in
                if enabled {
                    if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                        pendingMode = nil
                        showClosedLidConfirmation = true
                    } else {
                        Task { await manager.startFreshSession() }
                    }
                } else {
                    Task { await manager.stopLiveSession() }
                }
            }
        )
    }

    private var durationBinding: Binding<SessionDuration> {
        Binding(
            get: { manager.selectedDuration },
            set: { duration in
                Task {
                    let wasActive = manager.isActive
                    let ok = await manager.changeDurationLive(duration)
                    liveNotice = ok
                        ? (wasActive ? "Duration changed. A new countdown started." : "Duration updated.")
                        : "The duration change could not be applied."
                }
            }
        )
    }

    private func selectMode(_ preset: RuntimeProfile) {
        guard !modeLocked(preset) else {
            liveNotice = "Open the lid before switching away from closed-lid protection."
            return
        }

        if preset == .closedLidEco && !manager.hasAcknowledgedClosedLidSafety {
            pendingMode = preset
            showClosedLidConfirmation = true
        } else {
            Task { await applyMode(preset) }
        }
    }

    private func applyMode(_ preset: RuntimeProfile) async {
        let wasActive = manager.isActive
        let before = manager.effectiveEndDate
        let ok = await manager.changeModeLive(preset)
        if ok {
            if wasActive, let before, let after = manager.effectiveEndDate {
                let drift = abs(after.timeIntervalSince(before))
                liveNotice = drift < 0.25
                    ? "\(preset.title) applied. Timer continued unchanged."
                    : "\(preset.title) applied."
            } else {
                liveNotice = "\(preset.title) selected."
            }
        } else {
            liveNotice = manager.lidIsClosed
                ? "Open the lid before removing or changing closed-lid protection."
                : "The mode could not be applied. Closed-Lid Eco may require authorization first."
        }
    }

    private func changeOption(_ option: VigilOption, to enabled: Bool) {
        Task {
            let wasActive = manager.isActive
            let before = manager.effectiveEndDate
            let ok = await manager.changeOptionLive(option, to: enabled)
            if ok {
                if wasActive, let before, let after = manager.effectiveEndDate, abs(after.timeIntervalSince(before)) < 0.25 {
                    liveNotice = "Active configuration updated. Timer continued unchanged."
                } else {
                    liveNotice = wasActive ? "Active configuration updated." : "Option updated."
                }
            } else {
                liveNotice = manager.lidIsClosed
                    ? "Open the lid before changing this protection."
                    : "This change could not be applied. Global SleepDisabled may require authorization."
            }
        }
    }

    private func requestManualUpdate() {
        if manager.isActive {
            showActiveUpdateConfirmation = true
        } else {
            Task { await updater.installAvailableUpdate() }
        }
    }

    private func installAutomaticallyIfEligible() async {
        guard updater.automaticInstallEnabled,
              updater.hasUpdate,
              !manager.isActive,
              !updater.isInstalling else { return }
        await updater.installAvailableUpdate()
    }

    private func modeLocked(_ preset: RuntimeProfile) -> Bool {
        manager.isActive
            && manager.lidIsClosed
            && manager.closedLidProtectionRequested
            && preset != .closedLidEco
    }

    private var liveLidTransitionLocked: Bool {
        manager.isActive && manager.lidIsClosed && manager.closedLidProtectionRequested
    }

    private var updateBannerDetail: String {
        if updater.isInstalling { return updater.statusText ?? "Preparing update…" }
        if updater.automaticInstallEnabled && manager.isActive { return "Automatic update will install when Vigil stops." }
        if updater.automaticInstallEnabled { return "Automatic updates are enabled." }
        return "Update now, or enable automatic installation below."
    }

    private var runtimeProtectionReady: Bool {
        manager.preventSystemSleep
            || manager.preventIdleSystemSleep
            || manager.vetoIdleSleepRequests
            || manager.keepDisplayAwake
            || manager.closedLidProtectionRequested
    }

    private var runtimeSubtitle: String {
        guard manager.isActive else { return "Choose a mode, then turn Vigil on." }
        guard let remaining = manager.effectiveRemainingSeconds else { return "Running until you turn Vigil off." }

        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds) }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private var modeName: String {
        if isPresetSelected(.closedLidEco) { return RuntimeProfile.closedLidEco.title }
        if isPresetSelected(.fullAwake) { return RuntimeProfile.fullAwake.title }
        if isPresetSelected(.computeGuard) { return RuntimeProfile.computeGuard.title }
        return "Custom Vigil"
    }

    private var modeDescription: String {
        if isPresetSelected(.closedLidEco) {
            return "Keep work running with the lid closed. The built-in backlight can darken while display sleep stays blocked."
        }
        if isPresetSelected(.fullAwake) { return "Keep both the Mac and display awake." }
        if isPresetSelected(.computeGuard) { return "Keep compute and network work running while the display may sleep normally." }
        return "Custom protection. Changes apply live without resetting the active timer."
    }

    private func isPresetSelected(_ preset: RuntimeProfile) -> Bool {
        switch preset {
        case .computeGuard:
            return manager.preventSystemSleep
                && manager.preventIdleSystemSleep
                && !manager.keepDisplayAwake
                && manager.vetoIdleSleepRequests
                && !manager.useGlobalSleepDisable
                && !manager.useKernelLidGuard
                && !manager.darkenBuiltinDisplayOnLidClose
        case .closedLidEco:
            return manager.preventSystemSleep
                && manager.preventIdleSystemSleep
                && manager.keepDisplayAwake
                && manager.vetoIdleSleepRequests
                && manager.useGlobalSleepDisable
                && manager.useKernelLidGuard
                && manager.darkenBuiltinDisplayOnLidClose
        case .fullAwake:
            return manager.preventSystemSleep
                && manager.preventIdleSystemSleep
                && manager.keepDisplayAwake
                && manager.vetoIdleSleepRequests
                && !manager.useGlobalSleepDisable
                && !manager.useKernelLidGuard
                && !manager.darkenBuiltinDisplayOnLidClose
        }
    }

    private func confirmationRow(_ title: String, detail: String, confirmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(confirmed ? Color.green : Color.secondary)
                .frame(width: 16)
            Text(title).font(.caption.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var powerValue: String {
        guard let battery = manager.batteryPercent else { return "Unknown" }
        return manager.onBatteryPower ? "\(battery)% battery" : "\(battery)% · power"
    }
}

private struct ModeCardButton: View {
    let preset: RuntimeProfile
    let icon: String
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                    }
                }
                Text(preset.title)
                    .font(.caption.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModeCardButtonStyle(selected: selected, hovering: hovering))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .help(disabled ? "Open the lid before changing this mode" : preset.subtitle)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct ModeCardButtonStyle: ButtonStyle {
    let selected: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.14)
                            : Color.primary.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.055 : 0.025))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(hovering ? 0.38 : 0.16),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.975 : (hovering ? 1.012 : 1))
            .shadow(color: selected ? Color.accentColor.opacity(0.10) : .clear, radius: 4, y: 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.16), value: selected)
    }
}

private struct InteractiveToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    var enabled: Bool = true
    let onChange: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering && enabled ? 0.045 : 0))
        }
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.5)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
    }
}

private struct InteractivePreferenceToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.045 : 0))
        }
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
    }
}
