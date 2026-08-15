import SwiftUI
import AppKit

struct LiveMenuBarView: View {
    @ObservedObject var manager: VigilManager

    @State private var showAdvanced = false
    @State private var copyingDiagnostics = false
    @State private var showClosedLidConfirmation = false
    @State private var pendingMode: RuntimeProfile?
    @State private var liveNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                vigilCard
                modeSection
                durationSection
                confirmationSection
                advancedSection
                messageSection
                footer
            }
            .padding(18)
        }
        .frame(width: 440, height: 700)
        .task {
            manager.loadPreferences()
            await manager.prepareOnLaunch()
        }
        .alert("Use Closed-Lid Eco?", isPresented: $showClosedLidConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingMode = nil
            }
            Button("Continue") {
                manager.acknowledgeClosedLidSafety()
                let mode = pendingMode ?? .closedLidEco
                pendingMode = nil
                Task { await applyMode(mode) }
            }
        } message: {
            Text("Closed-lid workloads can generate heat. Keep the MacBook on a ventilated surface. MacVigil does not weaken your password or Lock Screen settings, and mandatory macOS safety behavior remains in control.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)

                Image(systemName: manager.isActive ? "bolt.shield.fill" : "bolt.shield")
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

    private var vigilCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(modeName)
                        .font(.headline)
                    Text(runtimeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Vigil", isOn: vigilBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
            }

            if manager.isActive {
                Divider()
                statusRow("System sleep", value: manager.preventSystemSleep ? "Protected" : "Allowed", icon: "cpu")
                statusRow("Idle sleep", value: manager.preventIdleSystemSleep ? "Protected" : "Allowed", icon: "clock")
                statusRow("Display sleep", value: manager.keepDisplayAwake ? "Blocked" : "Allowed", icon: "display")

                if manager.closedLidProtectionRequested {
                    statusRow(
                        "SleepDisabled",
                        value: manager.useGlobalSleepDisable
                            ? (manager.sleepDisabledReadback ? "Verified" : "Not verified")
                            : "Off",
                        icon: "lock.shield"
                    )
                    statusRow(
                        "Lid guard",
                        value: manager.useKernelLidGuard
                            ? (manager.kernelGuardActive ? "Armed" : "Not armed")
                            : "Off",
                        icon: "laptopcomputer"
                    )
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
                modeButton(.computeGuard, icon: "cpu")
                modeButton(.closedLidEco, icon: "laptopcomputer")
                modeButton(.fullAwake, icon: "sun.max")
            }

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if manager.isActive && manager.lidIsClosed && manager.closedLidProtectionRequested {
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
                    Text("Changing duration starts a fresh countdown")
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

                if manager.selectedDuration == .custom {
                    Spacer()
                    TextField("Minutes", value: $manager.customMinutes, format: .number)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .disabled(manager.isActive)
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(manager.isActive ? "Live confirmation" : "Ready check", icon: "checkmark.seal")

            confirmationRow(
                "Runtime protection",
                detail: runtimeProtectionReady ? "Configured" : "Choose at least one protection",
                confirmed: runtimeProtectionReady
            )

            if manager.closedLidProtectionRequested {
                confirmationRow(
                    "Authorization",
                    detail: manager.useGlobalSleepDisable
                        ? (manager.pmsetPrivilegeAvailable ? "Available" : "Required")
                        : "Not required",
                    confirmed: !manager.useGlobalSleepDisable || manager.pmsetPrivilegeAvailable
                )

                confirmationRow(
                    "Display policy",
                    detail: manager.keepDisplayAwake
                        ? "Display sleep blocked; backlight can still darken"
                        : "Display sleep may invoke Lock Screen",
                    confirmed: manager.keepDisplayAwake
                )

                if manager.isActive && manager.useGlobalSleepDisable {
                    confirmationRow(
                        "SleepDisabled",
                        detail: manager.sleepDisabledReadback ? "Verified ON" : "Not verified",
                        confirmed: manager.sleepDisabledReadback
                    )
                }

                if manager.isActive && manager.useKernelLidGuard {
                    confirmationRow(
                        "Kernel lid guard",
                        detail: manager.kernelGuardStatus,
                        confirmed: manager.kernelGuardActive
                    )
                }
            }

            confirmationRow(
                "Safety cutoffs",
                detail: manager.enableBatterySafety && manager.enableThermalSafety
                    ? "Battery + thermal enabled"
                    : "Customized",
                confirmed: manager.enableBatterySafety && manager.enableThermalSafety
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Divider()

                optionToggle(
                    "Prevent system sleep",
                    subtitle: "Protect long-running work from system sleep.",
                    option: .preventSystemSleep,
                    value: manager.preventSystemSleep
                )

                optionToggle(
                    "Prevent idle system sleep",
                    subtitle: "Keep the Mac available without keyboard or mouse activity.",
                    option: .preventIdleSystemSleep,
                    value: manager.preventIdleSystemSleep
                )

                optionToggle(
                    "Prevent display sleep",
                    subtitle: "Block display sleep. Closed-Lid Eco can still darken the built-in backlight.",
                    option: .keepDisplayAwake,
                    value: manager.keepDisplayAwake,
                    enabled: !liveLidTransitionLocked
                )

                optionToggle(
                    "Veto idle sleep requests",
                    subtitle: "Reject cancellable idle-sleep requests while Vigil is active.",
                    option: .vetoIdleSleepRequests,
                    value: manager.vetoIdleSleepRequests
                )

                Divider()
                sectionTitle("Closed-lid", icon: "laptopcomputer")

                optionToggle(
                    "Global SleepDisabled",
                    subtitle: "Use macOS global SleepDisabled while the session is active.",
                    option: .useGlobalSleepDisable,
                    value: manager.useGlobalSleepDisable,
                    enabled: !liveLidTransitionLocked
                )

                optionToggle(
                    "Kernel clamshell guard",
                    subtitle: "Use the experimental kernel closed-lid guard.",
                    option: .useKernelLidGuard,
                    value: manager.useKernelLidGuard,
                    enabled: !liveLidTransitionLocked
                )

                optionToggle(
                    "Darken built-in display on lid close",
                    subtitle: "Set the built-in backlight to 0 when appropriate.",
                    option: .darkenBuiltinDisplayOnLidClose,
                    value: manager.darkenBuiltinDisplayOnLidClose,
                    enabled: !liveLidTransitionLocked && manager.closedLidProtectionRequested
                )

                authorizationRow

                Divider()
                sectionTitle("Safety", icon: "leaf")

                optionToggle(
                    "Battery reserve cutoff",
                    subtitle: "Release closed-lid protection at the configured reserve.",
                    option: .enableBatterySafety,
                    value: manager.enableBatterySafety
                )

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

                optionToggle(
                    "Critical thermal cutoff",
                    subtitle: "Release closed-lid protection if macOS reports critical thermal pressure.",
                    option: .enableThermalSafety,
                    value: manager.enableThermalSafety
                )

                Button("Reset options to defaults") {
                    manager.resetPreferences()
                    liveNotice = "Options reset to defaults."
                }
                .disabled(manager.isActive)
                .font(.caption)
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced controls", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
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
            .disabled(manager.isActive)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = manager.lastError {
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
        HStack {
            Button(copyingDiagnostics ? "Copied" : "Copy Diagnostics") {
                copyingDiagnostics = true
                Task {
                    let text = await manager.diagnostics()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    copyingDiagnostics = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit MacVigil") {
                manager.handleAppTermination()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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
                        Task { await manager.startSelectedSession() }
                    }
                } else {
                    Task { await manager.stopSession() }
                }
            }
        )
    }

    private var durationBinding: Binding<SessionDuration> {
        Binding(
            get: { manager.selectedDuration },
            set: { duration in
                Task {
                    let ok = await manager.changeDurationLive(duration)
                    liveNotice = ok
                        ? (manager.isActive ? "Duration updated. A fresh countdown started." : "Duration updated.")
                        : "The duration change could not be applied."
                }
            }
        )
    }

    private func modeButton(_ preset: RuntimeProfile, icon: String) -> some View {
        let selected = isPresetSelected(preset)
        let locked = manager.isActive
            && manager.lidIsClosed
            && manager.closedLidProtectionRequested
            && preset != .closedLidEco

        return Button {
            if preset == .closedLidEco && !manager.hasAcknowledgedClosedLidSafety {
                pendingMode = preset
                showClosedLidConfirmation = true
            } else {
                Task { await applyMode(preset) }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                Text(preset.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : nil)
        .disabled(locked)
    }

    private func applyMode(_ preset: RuntimeProfile) async {
        let wasActive = manager.isActive
        let ok = await manager.changeModeLive(preset)
        if ok {
            liveNotice = wasActive
                ? "\(preset.title) applied to the active Vigil session."
                : "\(preset.title) selected."
        } else {
            liveNotice = manager.lidIsClosed
                ? "Open the lid before removing or changing closed-lid protection."
                : "The mode could not be applied. Closed-Lid Eco may require authorization first."
        }
    }

    private func optionToggle(
        _ title: String,
        subtitle: String,
        option: VigilOption,
        value: Bool,
        enabled: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { value },
                set: { newValue in
                    Task {
                        let wasActive = manager.isActive
                        let ok = await manager.changeOptionLive(option, to: newValue)
                        if ok {
                            liveNotice = wasActive
                                ? "Active Vigil configuration updated."
                                : "Option updated."
                        } else {
                            liveNotice = manager.lidIsClosed
                                ? "Open the lid before changing this protection."
                                : "This change could not be applied. Global SleepDisabled may require authorization."
                        }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }

    private func confirmationRow(_ title: String, detail: String, confirmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(confirmed ? Color.green : Color.secondary)
                .frame(width: 16)
            Text(title)
                .font(.caption.weight(.medium))
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
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var runtimeProtectionReady: Bool {
        manager.preventSystemSleep
            || manager.preventIdleSystemSleep
            || manager.vetoIdleSleepRequests
            || manager.keepDisplayAwake
            || manager.closedLidProtectionRequested
    }

    private var liveLidTransitionLocked: Bool {
        manager.isActive && manager.lidIsClosed && manager.closedLidProtectionRequested
    }

    private var runtimeSubtitle: String {
        guard manager.isActive else { return "Choose a mode, then turn Vigil on." }
        guard let remaining = manager.remainingSeconds else { return "Running until you turn Vigil off." }

        let total = max(0, Int(remaining.rounded()))
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
        if isPresetSelected(.fullAwake) {
            return "Keep both the Mac and display awake."
        }
        if isPresetSelected(.computeGuard) {
            return "Keep compute and network work running while the display may sleep normally."
        }
        return "Custom protection. Changes are applied to an active session automatically."
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

    private var powerValue: String {
        guard let battery = manager.batteryPercent else { return "Unknown" }
        return manager.onBatteryPower ? "\(battery)% battery" : "\(battery)% · power"
    }
}
