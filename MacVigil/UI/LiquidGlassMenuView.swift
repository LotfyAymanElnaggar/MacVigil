import SwiftUI
import AppKit

struct LiquidGlassMenuView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController
    @ObservedObject var hotkeys: GlobalHotkeyManager

    @Environment(\.openWindow) private var openWindow
    @State private var durationMinutes = 60.0
    @State private var batteryReserve = 15.0
    @State private var message: String?
    @State private var showClosedLidSafety = false
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 14) {
            header
            primaryAction
            modePicker
            durationCard
            batteryCard

            if updater.hasUpdate {
                updateBanner
            }

            destinationRow

            if let text = message ?? manager.lastError ?? updater.lastError ?? hotkeys.lastActionText {
                Label(text, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(message != nil || manager.lastError != nil || updater.lastError != nil ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 470)
        .onAppear { syncControls() }
        .alert("Closed-Lid Eco safety", isPresented: $showClosedLidSafety) {
            Button("Cancel", role: .cancel) { }
            Button("I Understand — Start Vigil") {
                manager.acknowledgeClosedLidSafety()
                Task { await manager.startFreshSession() }
            }
        } message: {
            Text("Closed-lid workloads can generate significant heat. Keep the MacBook on a hard, ventilated surface and never run sustained workloads in a bag, sleeve, drawer, or other enclosed space. macOS battery and thermal safety remain in control.")
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacVigil")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.isActive ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(manager.isActive ? statusText : "Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let battery = power.batteryPercent {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(battery)%", systemImage: power.onBatteryPower ? "battery.50" : "battery.100.bolt")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(power.thermalStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if #available(macOS 26.0, *) {
            primaryButton
                .buttonStyle(.glassProminent)
                .tint(manager.isActive ? .red : .accentColor)
        } else {
            primaryButton
                .buttonStyle(.borderedProminent)
                .tint(manager.isActive ? .red : .accentColor)
        }
    }

    private var primaryButton: some View {
        Button {
            if manager.isActive {
                stopVigil()
            } else if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                showClosedLidSafety = true
            } else {
                Task { await manager.startFreshSession() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: manager.isActive ? "stop.fill" : "play.fill")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(primarySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌥⌘V")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .controlSize(.large)
        .disabled(isStopping || updater.isInstalling)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Mode")
                Spacer()
                Text("⌥⌘1 / 2 / 3")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 9) {
                MVModeButton(profile: .computeGuard, selected: matches(.computeGuard)) { applyMode(.computeGuard) }
                MVModeButton(profile: .closedLidEco, selected: matches(.closedLidEco)) { applyMode(.closedLidEco) }
                MVModeButton(profile: .fullAwake, selected: matches(.fullAwake)) { applyMode(.fullAwake) }
            }
        }
    }

    private var durationCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Duration")
                    Spacer()
                    Text(durationSummary)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    durationButton("15m", .fifteenMinutes)
                    durationButton("30m", .thirtyMinutes)
                    durationButton("1h", .oneHour)
                    durationButton("2h", .twoHours)
                    durationButton("4h", .custom, custom: 240)
                    durationButton("∞", .indefinite)
                }

                Slider(value: $durationMinutes, in: 5...720, step: 5) { editing in
                    guard !editing else { return }
                    Task {
                        let ok = await manager.changeDurationLive(.custom, customMinutes: Int(durationMinutes.rounded()))
                        if ok {
                            message = nil
                            syncControls()
                        } else {
                            message = "Job Guard owns this session lifetime. Duration is available again after Job Guard releases or detaches."
                        }
                    }
                }
                .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)
                .accessibilityValue(formatDurationWords(Int(durationMinutes.rounded())))

                HStack {
                    Text("5m")
                    Spacer()
                    Text("Custom · \(formatDurationWords(Int(durationMinutes.rounded())))")
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Spacer()
                    Text("12h")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var batteryCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Battery reserve")
                    Spacer()
                    Text("\(Int(batteryReserve))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                Slider(value: $batteryReserve, in: 5...30, step: 1) { editing in
                    guard !editing else { return }
                    manager.lowBatteryCutoff = Int(batteryReserve.rounded())
                    manager.savePreferences()
                }
                Text("Release at the reserve when battery safety is enabled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var updateBanner: some View {
        if #available(macOS 26.0, *) {
            updateButton.buttonStyle(.glassProminent)
        } else {
            updateButton.buttonStyle(.borderedProminent)
        }
    }

    private var updateButton: some View {
        Button {
            if manager.isActive {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "update-confirmation")
            } else {
                Task { await updater.installAvailableUpdate() }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text(updater.availableVersion.map { "Update to \($0)" } ?? "Update Now")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(manager.isActive ? "Review" : "Install")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .controlSize(.large)
        .disabled(updater.isInstalling)
    }

    private var destinationRow: some View {
        HStack(spacing: 9) {
            destinationButton(
                title: "Job Guard",
                icon: jobs.isWatching ? "briefcase.fill" : "briefcase",
                badge: jobs.isWatching ? "\(jobs.activeJobCount)" : nil,
                windowID: "job-guard"
            )
            destinationButton(title: "Statistics", icon: "chart.bar.xaxis", badge: nil, windowID: "statistics")
            destinationButton(title: "Settings", icon: "gearshape", badge: nil, windowID: "settings")
        }
    }

    @ViewBuilder
    private func destinationButton(title: String, icon: String, badge: String?, windowID: String) -> some View {
        let button = Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: windowID)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, height: 22)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 7, y: -5)
                    }
                }
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }

        if #available(macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var primaryTitle: String {
        if isStopping { return "Stopping Vigil…" }
        return manager.isActive ? "Stop Vigil" : "Start Vigil"
    }

    private var primarySubtitle: String {
        if manager.isActive {
            if jobs.isWatching { return "Job Guard is protecting \(jobs.activeJobCount) running job\(jobs.activeJobCount == 1 ? "" : "s")" }
            return "Restore normal macOS sleep behavior"
        }
        return "Start \(displayModeName) for \(durationSummary)"
    }

    private var statusText: String {
        if jobs.isWatching { return "Job Guard · \(jobs.activeJobCount) job\(jobs.activeJobCount == 1 ? "" : "s")" }
        if manager.isLiveReconfiguring { return "Applying changes…" }
        if manager.isActive { return "\(displayModeName) · \(durationSummary)" }
        return "Ready"
    }

    private var durationSummary: String {
        if jobs.isWatching { return "until jobs finish" }
        if manager.isActive {
            guard let seconds = manager.effectiveRemainingSeconds else { return "∞" }
            return remainingText(Int(seconds))
        }
        return manager.selectedDuration == .custom ? formatDurationWords(manager.customMinutes) : manager.selectedDuration.title
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func durationButton(_ title: String, _ duration: SessionDuration, custom: Int? = nil) -> some View {
        let selected = duration == .custom && custom != nil
            ? manager.selectedDuration == .custom && manager.customMinutes == custom
            : manager.selectedDuration == duration

        return Button(title) {
            if let custom { durationMinutes = Double(custom) }
            Task {
                let ok = await manager.changeDurationLive(duration, customMinutes: custom)
                if ok {
                    message = nil
                    syncControls()
                } else {
                    message = "Job Guard controls this session lifetime."
                }
            }
        }
        .buttonStyle(MVGlassPillButtonStyle(selected: selected))
        .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)
    }

    private func applyMode(_ profile: RuntimeProfile) {
        Task {
            let ok = await manager.changeModeLive(profile)
            if ok {
                message = nil
            } else if profile == .closedLidEco && !manager.pmsetPrivilegeAvailable {
                message = "Closed-Lid Eco requires authorization. Open Settings → Power & Safety."
            } else if manager.lidIsClosed {
                message = "Open the MacBook lid before removing or changing closed-lid protection."
            } else {
                message = "MacVigil could not apply that mode safely."
            }
        }
    }

    private func matches(_ profile: RuntimeProfile) -> Bool {
        switch profile {
        case .computeGuard:
            return manager.preventSystemSleep && manager.preventIdleSystemSleep && !manager.keepDisplayAwake && manager.vetoIdleSleepRequests && !manager.useGlobalSleepDisable && !manager.useKernelLidGuard && !manager.darkenBuiltinDisplayOnLidClose
        case .closedLidEco:
            return manager.preventSystemSleep && manager.preventIdleSystemSleep && manager.keepDisplayAwake && manager.vetoIdleSleepRequests && manager.useGlobalSleepDisable && manager.useKernelLidGuard && manager.darkenBuiltinDisplayOnLidClose
        case .fullAwake:
            return manager.preventSystemSleep && manager.preventIdleSystemSleep && manager.keepDisplayAwake && manager.vetoIdleSleepRequests && !manager.useGlobalSleepDisable && !manager.useKernelLidGuard && !manager.darkenBuiltinDisplayOnLidClose
        }
    }

    private var displayModeName: String {
        if matches(.computeGuard) { return RuntimeProfile.computeGuard.title }
        if matches(.closedLidEco) { return RuntimeProfile.closedLidEco.title }
        if matches(.fullAwake) { return RuntimeProfile.fullAwake.title }
        return manager.configurationName
    }

    private func stopVigil() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await manager.stopLiveSession()
            isStopping = false
        }
    }

    private func syncControls() {
        durationMinutes = Double(preferredMinutes)
        batteryReserve = Double(manager.lowBatteryCutoff)
    }

    private var preferredMinutes: Int {
        switch manager.selectedDuration {
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .oneHour: return 60
        case .twoHours: return 120
        case .custom: return manager.customMinutes
        case .indefinite: return min(720, max(5, manager.customMinutes))
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func formatDurationWords(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60

        if hours == 0 {
            return "\(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
        }
        if remainingMinutes == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours) hour\(hours == 1 ? "" : "s") \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
    }

    private func remainingText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// Content surfaces deliberately use standard materials. Liquid Glass is reserved
// for navigation and controls in the menu; Settings applies native glass to its
// window chrome and keeps forms readable inside those panes.
struct MVGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(13)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MVGlassPillButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 7)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .contentShape(Capsule())
            .modifier(MVAdaptivePillGlass(selected: selected, pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct MVAdaptivePillGlass: ViewModifier {
    let selected: Bool
    let pressed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular
                    .tint(selected ? Color.accentColor.opacity(0.20) : nil)
                    .interactive(),
                in: Capsule()
            )
        } else {
            content
                .background(
                    selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(pressed ? 0.10 : 0.045),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

struct MVModeButton: View {
    let profile: RuntimeProfile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(profile.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(shortDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(MVAdaptiveModeGlass(selected: selected))
        }
        .buttonStyle(.plain)
        .help(profile.subtitle)
    }

    private var icon: String {
        switch profile {
        case .computeGuard: return "cpu"
        case .closedLidEco: return "leaf"
        case .fullAwake: return "sun.max"
        }
    }

    private var shortDetail: String {
        switch profile {
        case .computeGuard: return "Work first"
        case .closedLidEco: return "Lid closed"
        case .fullAwake: return "Display awake"
        }
    }
}

private struct MVAdaptiveModeGlass: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular
                    .tint(selected ? Color.accentColor.opacity(0.18) : nil)
                    .interactive(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
