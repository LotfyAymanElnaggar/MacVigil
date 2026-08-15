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
                profileSection
                durationSection
                safetySection

                if manager.profile == .closedLidEco || manager.authorizationInstalled {
                    closedLidSection
                }

                messageSection
                footer
            }
            .padding(18)
        }
        .frame(width: 420, height: 620)
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
                    Text(manager.isActive ? manager.profile.title : "Vigil is off")
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
                statusRow("Compute", value: "Protected", icon: "cpu")
                statusRow("Display", value: displayValue, icon: "display")
                statusRow("Power", value: powerValue, icon: "battery.75percent")
                statusRow("Thermal", value: manager.thermalStatus, icon: "thermometer.medium")

                if manager.profile == .closedLidEco {
                    statusRow("Lid guard", value: manager.kernelGuardActive ? "Armed" : "Not armed", icon: "laptopcomputer")
                }
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

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Runtime profile", icon: "slider.horizontal.3")

            Picker("Runtime profile", selection: $manager.profile) {
                ForEach(RuntimeProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(manager.isActive)

            Text(manager.profile.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Power & safety", icon: "leaf")

            HStack {
                Text("Battery reserve")
                Spacer()
                Picker("Battery reserve", selection: $manager.lowBatteryCutoff) {
                    ForEach([10, 15, 20, 25], id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Text("Closed-Lid Eco stops at the reserve level and also releases the lid guard if macOS reports critical thermal pressure.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var closedLidSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Closed-Lid Eco", icon: "laptopcomputer")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.authorizationInstalled ? "Authorization installed" : "Authorization required")
                        .font(.subheadline.weight(.medium))
                    Text("Only two exact pmset disablesleep commands are authorized.")
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

            if manager.isActive && manager.profile == .closedLidEco {
                HStack(spacing: 8) {
                    Circle()
                        .fill(manager.kernelGuardActive ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(manager.kernelGuardStatus)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(manager.displayStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        guard manager.isActive else { return "Choose a profile and protect the work that matters." }
        guard let remaining = manager.remainingSeconds else { return "Running until you end it." }

        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds) }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private var displayValue: String {
        switch manager.profile {
        case .fullAwake:
            return "Protected"
        case .computeGuard:
            return "May sleep"
        case .closedLidEco:
            if manager.hasExternalDisplay { return "External display" }
            return manager.backlightDimmed ? "Backlight dark" : (manager.lidIsClosed ? "Managing" : "Ready")
        }
    }

    private var powerValue: String {
        let source = manager.onBatteryPower ? "Battery" : "External"
        if let level = manager.batteryPercent { return "\(source) · \(level)%" }
        return source
    }
}
