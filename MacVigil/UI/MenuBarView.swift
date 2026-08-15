import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var manager: VigilManager
    @State private var copyingDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                runtimeCard
                presetSection
                protectionSwitches
                closedLidSection
                durationSection
                safetySection
                messageSection
                footer
            }
            .padding(18)
        }
        .frame(width: 460, height: 760)
        .task {
            await manager.prepareOnLaunch()
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

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.isActive ? displayConfigurationName : "Vigil is off")
                        .font(.headline)
                    Text(runtimeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: manager.isActive ? "waveform.path.ecg" : "moon.zzz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if manager.isActive {
                Divider()
                statusRow(
                    "System sleep",
                    value: manager.preventSystemSleep ? "Blocked" : "Allowed",
                    icon: "cpu"
                )
                statusRow(
                    "Idle sleep",
                    value: manager.preventIdleSystemSleep ? "Blocked" : "Allowed",
                    icon: "clock"
                )
                statusRow("Display", value: displayValue, icon: "display")

                if manager.closedLidProtectionRequested {
                    statusRow(
                        "SleepDisabled",
                        value: manager.useGlobalSleepDisable
                            ? (manager.sleepDisabledReadback ? "ON" : "Not verified")
                            : "Off",
                        icon: "lock.shield"
                    )
                    statusRow(
                        "Kernel lid guard",
                        value: manager.useKernelLidGuard
                            ? (manager.kernelGuardActive ? "Armed" : "Not armed")
                            : "Off",
                        icon: "laptopcomputer"
                    )
                }

                statusRow("Power", value: powerValue, icon: "battery.75percent")
                statusRow("Thermal", value: manager.thermalStatus, icon: "thermometer.medium")
            }

            Button {
                Task {
                    if manager.isActive {
                        await manager.stopSession()
                    } else {
                        await manager.startSelectedSession()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: manager.isActive ? "stop.fill" : "play.fill")
                    Text(manager.isActive ? "End Vigil" : "Start Vigil")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(.quaternary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionTitle("Presets", icon: "square.grid.2x2")
                Spacer()
                Text(displayConfigurationName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                presetButton(.computeGuard, icon: "cpu")
                presetButton(.closedLidEco, icon: "laptopcomputer")
                presetButton(.fullAwake, icon: "sun.max")
            }

            Text("Presets fill the switches below. Every protection behavior can still be changed independently before starting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var protectionSwitches: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Runtime protection", icon: "switch.2")

            optionToggle(
                "Prevent system sleep",
                subtitle: "Keep long-running work alive while Vigil is active.",
                isOn: $manager.preventSystemSleep
            )

            optionToggle(
                "Prevent idle system sleep",
                subtitle: "Keep the Mac available when there is no keyboard or mouse activity.",
                isOn: $manager.preventIdleSystemSleep
            )

            optionToggle(
                "Veto idle sleep requests",
                subtitle: "Block cancellable idle-sleep requests while Vigil is active.",
                isOn: $manager.vetoIdleSleepRequests
            )

            optionToggle(
                "Prevent display sleep",
                subtitle: "Keep macOS from putting the display to sleep. Closed-Lid Eco enables this so the lid can be dark without relying on display sleep, which may trigger your Lock Screen policy.",
                isOn: $manager.keepDisplayAwake
            )

            if manager.closedLidProtectionRequested && !manager.keepDisplayAwake {
                Label(
                    "Your Mac may show the Lock Screen when the display sleeps. MacVigil never changes your password or Lock Screen settings.",
                    systemImage: "lock.display"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if manager.isActive {
                Label("End Vigil to change protection switches.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(manager.isActive)
    }

    private var closedLidSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Closed-lid protection", icon: "laptopcomputer")

            optionToggle(
                "Global SleepDisabled",
                subtitle: "Keep macOS system sleep disabled while the selected session is active. Requires authorization.",
                isOn: $manager.useGlobalSleepDisable
            )

            optionToggle(
                "Kernel clamshell guard",
                subtitle: "Use the experimental closed-lid guard for supported Macs and macOS versions.",
                isOn: $manager.useKernelLidGuard
            )

            optionToggle(
                "Darken built-in display on lid close",
                subtitle: "Set the built-in backlight to 0 when the lid closes and no external display is connected. This does not weaken Lock Screen security.",
                isOn: $manager.darkenBuiltinDisplayOnLidClose,
                enabled: manager.closedLidProtectionRequested
            )

            Divider()

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: manager.pmsetPrivilegeAvailable ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(manager.pmsetPrivilegeAvailable ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.authorizationStatusText)
                        .font(.subheadline.weight(.medium))
                    Text("MacVigil authorizes only the two commands needed to enable and restore closed-lid sleep behavior.")
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

            if manager.isActive && manager.closedLidProtectionRequested {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Live closed-lid state")
                        .font(.caption.weight(.semibold))
                    Text("SleepDisabled: \(manager.sleepDisabledReadback ? "1" : "0") · Kernel: \(manager.kernelGuardStatus)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(manager.displayStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Label("Crash-recovery cleanup stays enabled whenever closed-lid protection is active; it is not user-disableable.", systemImage: "cross.case")
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
                .disabled(manager.isActive)

                if manager.selectedDuration == .custom {
                    Spacer()
                    TextField("Minutes", value: $manager.customMinutes, format: .number)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .disabled(manager.isActive)
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Safety", icon: "leaf")

            optionToggle(
                "Battery reserve cutoff",
                subtitle: "Stop closed-lid protection before the battery reaches the selected reserve.",
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
                .disabled(manager.isActive || !manager.enableBatterySafety)
            }

            optionToggle(
                "Critical thermal cutoff",
                subtitle: "Release closed-lid protection if macOS reports critical thermal pressure.",
                isOn: $manager.enableThermalSafety
            )

            Text("Mandatory macOS safety transitions are never blocked by these switches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(manager.isActive)
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
        .padding(.top, 2)
    }

    private func presetButton(_ preset: RuntimeProfile, icon: String) -> some View {
        Button {
            manager.applyPreset(preset)

            // Closed-Lid Eco keeps the display logically awake while the
            // backlight is darkened on lid close. This avoids relying on
            // display sleep, which can trigger the user's Lock Screen policy.
            if preset == .closedLidEco {
                manager.keepDisplayAwake = true
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
        .disabled(manager.isActive)
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

    private var runtimeSubtitle: String {
        guard manager.isActive else { return "Choose a preset or build your own protection stack." }
        guard let remaining = manager.remainingSeconds else { return "Running until you end it." }

        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds) }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private var displayConfigurationName: String {
        if manager.preventSystemSleep,
           manager.preventIdleSystemSleep,
           manager.keepDisplayAwake,
           manager.vetoIdleSleepRequests,
           manager.useGlobalSleepDisable,
           manager.useKernelLidGuard,
           manager.darkenBuiltinDisplayOnLidClose {
            return RuntimeProfile.closedLidEco.title
        }

        return manager.configurationName
    }

    private var displayValue: String {
        if manager.keepDisplayAwake {
            if manager.closedLidProtectionRequested && manager.darkenBuiltinDisplayOnLidClose {
                if manager.hasExternalDisplay { return "External display" }
                if manager.backlightDimmed { return "Dark · display awake" }
                return manager.lidIsClosed ? "Darkening" : "Awake until lid closes"
            }
            return "Kept awake"
        }

        if manager.closedLidProtectionRequested && manager.darkenBuiltinDisplayOnLidClose {
            if manager.hasExternalDisplay { return "External display" }
            return manager.backlightDimmed ? "Backlight dark" : (manager.lidIsClosed ? "Managing" : "May sleep")
        }
        return "May sleep"
    }

    private var powerValue: String {
        let source = manager.onBatteryPower ? "Battery" : "External"
        if let level = manager.batteryPercent { return "\(source) · \(level)%" }
        return source
    }
}
