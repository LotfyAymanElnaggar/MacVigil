import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var manager: VigilManager

    @State private var copyingDiagnostics = false
    @State private var showAdvanced = false
    @State private var showClosedLidConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                vigilCard
                presetSection
                durationSection
                readinessSection
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
        .onChange(of: manager.selectedDuration) { _ in manager.savePreferences() }
        .onChange(of: manager.customMinutes) { _ in manager.savePreferences() }
        .onChange(of: manager.lowBatteryCutoff) { _ in manager.savePreferences() }
        .onChange(of: manager.preventSystemSleep) { _ in manager.savePreferences() }
        .onChange(of: manager.preventIdleSystemSleep) { _ in manager.savePreferences() }
        .onChange(of: manager.keepDisplayAwake) { _ in manager.savePreferences() }
        .onChange(of: manager.vetoIdleSleepRequests) { _ in manager.savePreferences() }
        .onChange(of: manager.useGlobalSleepDisable) { _ in manager.savePreferences() }
        .onChange(of: manager.useKernelLidGuard) { _ in manager.savePreferences() }
        .onChange(of: manager.darkenBuiltinDisplayOnLidClose) { _ in manager.savePreferences() }
        .onChange(of: manager.enableBatterySafety) { _ in manager.savePreferences() }
        .onChange(of: manager.enableThermalSafety) { _ in manager.savePreferences() }
        .alert("Start closed-lid protection?", isPresented: $showClosedLidConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start Vigil") {
                manager.acknowledgeClosedLidSafety()
                Task { await manager.startSelectedSession() }
            }
        } message: {
            Text("Closed-lid workloads can generate heat. Keep the MacBook on a ventilated surface. MacVigil will not weaken your password or Lock Screen settings, and mandatory macOS safety behavior remains in control.")
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
                    Text(displayConfigurationName)
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
                statusRow("System", value: manager.preventSystemSleep ? "Protected" : "Allowed", icon: "cpu")
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
                    statusRow("Built-in display", value: closedLidDisplayValue, icon: "rectangle.slash")
                }

                statusRow("Power", value: powerValue, icon: "battery.75percent")
                statusRow("Thermal", value: manager.thermalStatus, icon: "thermometer.medium")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Mode", icon: "square.grid.2x2")

            HStack(spacing: 8) {
                presetButton(.computeGuard, icon: "cpu")
                presetButton(.closedLidEco, icon: "laptopcomputer")
                presetButton(.fullAwake, icon: "sun.max")
            }

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(manager.isActive)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Duration", icon: "timer")

            HStack {
                Picker("Duration", selection: $manager.selectedDuration) {
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
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(manager.isActive)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(manager.isActive ? "Live confirmation" : "Ready check", icon: "checkmark.seal")

            readinessRow(
                title: "Runtime protection",
                detail: runtimeProtectionReady ? "Configured" : "Turn on a system protection option",
                confirmed: runtimeProtectionReady
            )

            if manager.closedLidProtectionRequested {
                readinessRow(
                    title: "Closed-lid authorization",
                    detail: manager.useGlobalSleepDisable
                        ? (manager.pmsetPrivilegeAvailable ? "Available" : "Required")
                        : "Not required",
                    confirmed: !manager.useGlobalSleepDisable || manager.pmsetPrivilegeAvailable
                )

                readinessRow(
                    title: "Display / Lock Screen policy",
                    detail: manager.keepDisplayAwake
                        ? "Display sleep blocked; backlight may still darken"
                        : "Display sleep can trigger Lock Screen",
                    confirmed: manager.keepDisplayAwake
                )

                if manager.isActive && manager.useGlobalSleepDisable {
                    readinessRow(
                        title: "SleepDisabled readback",
                        detail: manager.sleepDisabledReadback ? "Verified ON" : "Not verified",
                        confirmed: manager.sleepDisabledReadback
                    )
                }

                if manager.isActive && manager.useKernelLidGuard {
                    readinessRow(
                        title: "Kernel lid guard",
                        detail: manager.kernelGuardStatus,
                        confirmed: manager.kernelGuardActive
                    )
                }

                readinessRow(
                    title: "Safety cutoffs",
                    detail: manager.enableBatterySafety && manager.enableThermalSafety
                        ? "Battery + thermal enabled"
                        : "One or more safety cutoffs disabled",
                    confirmed: manager.enableBatterySafety && manager.enableThermalSafety
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                Divider()

                VStack(alignment: .leading, spacing: 11) {
                    sectionTitle("Runtime controls", icon: "switch.2")

                    optionToggle(
                        "Prevent system sleep",
                        subtitle: "Protect long-running work from system sleep.",
                        isOn: $manager.preventSystemSleep
                    )
                    optionToggle(
                        "Prevent idle system sleep",
                        subtitle: "Keep the Mac available when there is no user activity.",
                        isOn: $manager.preventIdleSystemSleep
                    )
                    optionToggle(
                        "Prevent display sleep",
                        subtitle: "Keep macOS from putting the display to sleep. Recommended for Closed-Lid Eco to avoid Lock Screen behavior caused by display sleep.",
                        isOn: $manager.keepDisplayAwake
                    )
                    optionToggle(
                        "Veto idle sleep requests",
                        subtitle: "Cancel sleep requests that macOS allows applications to veto.",
                        isOn: $manager.vetoIdleSleepRequests
                    )
                }

                VStack(alignment: .leading, spacing: 11) {
                    sectionTitle("Closed lid", icon: "laptopcomputer")

                    optionToggle(
                        "Global SleepDisabled",
                        subtitle: "Use the authorized macOS sleep-disable setting while Vigil is active.",
                        isOn: $manager.useGlobalSleepDisable
                    )
                    optionToggle(
                        "Kernel clamshell guard",
                        subtitle: "Use MacVigil's experimental closed-lid protection layer.",
                        isOn: $manager.useKernelLidGuard
                    )
                    optionToggle(
                        "Darken built-in display",
                        subtitle: "Set built-in brightness to 0 when the lid closes and no external display is connected.",
                        isOn: $manager.darkenBuiltinDisplayOnLidClose,
                        enabled: manager.closedLidProtectionRequested
                    )

                    authorizationRow
                }

                VStack(alignment: .leading, spacing: 11) {
                    sectionTitle("Safety", icon: "leaf")

                    optionToggle(
                        "Battery reserve cutoff",
                        subtitle: "Stop closed-lid protection at the configured reserve.",
                        isOn: $manager.enableBatterySafety
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
                        .disabled(!manager.enableBatterySafety)
                    }
                    .font(.subheadline)

                    optionToggle(
                        "Critical thermal cutoff",
                        subtitle: "Release closed-lid protection if macOS reports critical thermal pressure.",
                        isOn: $manager.enableThermalSafety
                    )
                }

                HStack {
                    Button("Reset Controls") {
                        manager.resetPreferences()
                    }
                    .disabled(manager.isActive)

                    Spacer()

                    Text("Changes are remembered automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            .disabled(manager.isActive)
        } label: {
            HStack {
                sectionTitle("Advanced controls", icon: "slider.horizontal.3")
                Spacer()
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("MacVigil authorizes only the two commands required to enable and restore its global sleep-disable state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    copyingDiagnostics = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("v\(appVersion)")
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                manager.handleAppTermination()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.top, 2)
    }

    private var vigilBinding: Binding<Bool> {
        Binding(
            get: { manager.isActive },
            set: { enabled in
                if enabled {
                    requestStart()
                } else {
                    Task { await manager.stopSession() }
                }
            }
        )
    }

    private func requestStart() {
        if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
            showClosedLidConfirmation = true
        } else {
            Task { await manager.startSelectedSession() }
        }
    }

    private func presetButton(_ preset: RuntimeProfile, icon: String) -> some View {
        Button {
            manager.applyPreset(preset)

            // Closed-Lid Eco keeps display sleep blocked while independently
            // darkening the built-in panel. This avoids using display sleep as
            // the mechanism for making a closed MacBook dark.
            if preset == .closedLidEco {
                manager.keepDisplayAwake = true
            }

            manager.savePreferences()
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
    }

    private func optionToggle(
        _ title: String,
        subtitle: String,
        isOn: Binding<Bool>,
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

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
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

    private func readinessRow(title: String, detail: String, confirmed: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(confirmed ? Color.green : Color.orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runtimeProtectionReady: Bool {
        manager.preventSystemSleep
            || manager.preventIdleSystemSleep
            || manager.vetoIdleSleepRequests
            || manager.keepDisplayAwake
            || manager.closedLidProtectionRequested
    }

    private var runtimeSubtitle: String {
        guard manager.isActive else { return "Ready to protect your local work." }
        guard let remaining = manager.remainingSeconds else { return "Running until you turn Vigil off." }

        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private var displayConfigurationName: String {
        if manager.preventSystemSleep,
           manager.preventIdleSystemSleep,
           !manager.keepDisplayAwake,
           manager.vetoIdleSleepRequests,
           !manager.useGlobalSleepDisable,
           !manager.useKernelLidGuard,
           !manager.darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.computeGuard.title
        }

        if manager.preventSystemSleep,
           manager.preventIdleSystemSleep,
           manager.keepDisplayAwake,
           manager.vetoIdleSleepRequests,
           manager.useGlobalSleepDisable,
           manager.useKernelLidGuard,
           manager.darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.closedLidEco.title
        }

        if manager.preventSystemSleep,
           manager.preventIdleSystemSleep,
           manager.keepDisplayAwake,
           manager.vetoIdleSleepRequests,
           !manager.useGlobalSleepDisable,
           !manager.useKernelLidGuard,
           !manager.darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.fullAwake.title
        }

        return "Custom Vigil"
    }

    private var modeDescription: String {
        switch displayConfigurationName {
        case RuntimeProfile.computeGuard.title:
            return "Keep compute available while allowing normal display behavior."
        case RuntimeProfile.closedLidEco.title:
            return "Keep work running with the lid closed, block display sleep, and darken the built-in panel."
        case RuntimeProfile.fullAwake.title:
            return "Keep both the Mac and display awake."
        default:
            return "Custom mode. Review the ready check before starting."
        }
    }

    private var closedLidDisplayValue: String {
        if manager.hasExternalDisplay { return "External display" }
        if manager.backlightDimmed { return "Backlight dark" }
        if manager.lidIsClosed { return "Managing" }
        return manager.keepDisplayAwake ? "Sleep blocked" : "May sleep"
    }

    private var powerValue: String {
        let source = manager.onBatteryPower ? "Battery" : "External"
        if let level = manager.batteryPercent {
            return "\(source) · \(level)%"
        }
        return source
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
