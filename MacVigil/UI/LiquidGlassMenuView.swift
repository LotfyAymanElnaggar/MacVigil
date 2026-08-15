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
        VStack(spacing: 12) {
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
                Label(text, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(message != nil || manager.lastError != nil || updater.lastError != nil ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 3)
                    .lineLimit(2)
            }
        }
        .padding(15)
        .frame(width: 480)
        .background(.ultraThinMaterial)
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(color: Color.accentColor.opacity(0.22), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacVigil")
                    .font(.title3.weight(.bold))
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

    private var primaryAction: some View {
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
                Image(systemName: manager.isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(primarySubtitle)
                        .font(.caption)
                        .opacity(0.82)
                }
                Spacer()
                Text("⌥⌘V")
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(manager.isActive ? Color.red : Color.accentColor)
        .disabled(isStopping || updater.isInstalling)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("Mode")
                Spacer()
                Text("⌥⌘1 / 2 / 3")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                MVModeButton(profile: .computeGuard, selected: matches(.computeGuard)) { applyMode(.computeGuard) }
                MVModeButton(profile: .closedLidEco, selected: matches(.closedLidEco)) { applyMode(.closedLidEco) }
                MVModeButton(profile: .fullAwake, selected: matches(.fullAwake)) { applyMode(.fullAwake) }
            }
        }
    }

    private var durationCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    sectionTitle("Duration")
                    Spacer()
                    Text(durationSummary)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 6) {
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

                HStack {
                    Text("5m")
                    Spacer()
                    Text("Fine tune · \(formatMinutes(Int(durationMinutes.rounded())))")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("12h")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var batteryCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    sectionTitle("Battery reserve")
                    Spacer()
                    Text("\(Int(batteryReserve))%")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                Slider(value: $batteryReserve, in: 5...30, step: 1) { editing in
                    guard !editing else { return }
                    manager.lowBatteryCutoff = Int(batteryReserve.rounded())
                    manager.savePreferences()
                }
                HStack {
                    Text("5%")
                    Spacer()
                    Text("Release at reserve when battery safety is on")
                    Spacer()
                    Text("30%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var updateBanner: some View {
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
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(updater.isInstalling)
    }

    private var destinationRow: some View {
        HStack(spacing: 8) {
            destinationButton(
                title: "Job Guard",
                icon: jobs.isWatching ? "briefcase.fill" : "briefcase",
                badge: jobs.isWatching ? "\(jobs.activeJobCount)" : nil,
                windowID: "job-guard"
            )
            destinationButton(title: "Statistics", icon: "chart.bar.xaxis", badge: nil, windowID: "statistics")
            destinationButton(title: "Settings", icon: "gearshape.fill", badge: nil, windowID: "settings")
        }
    }

    private func destinationButton(title: String, icon: String, badge: String?, windowID: String) -> some View {
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: windowID)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28, height: 24)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 8, y: -5)
                    }
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
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
        return manager.selectedDuration == .custom ? formatMinutes(manager.customMinutes) : manager.selectedDuration.title
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.55)
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

    private func remainingText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct MVGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.17), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.055), radius: 9, y: 4)
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
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(configuration.isPressed ? 0.11 : 0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.58) : Color.secondary.opacity(0.13), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MVModeButton: View {
    let profile: RuntimeProfile
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(selected ? Color.accentColor : iconColor)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
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
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.065 : 0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(hovering ? 0.26 : 0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(profile.subtitle)
    }

    private var icon: String {
        switch profile {
        case .computeGuard: return "cpu.fill"
        case .closedLidEco: return "leaf.fill"
        case .fullAwake: return "bolt.fill"
        }
    }

    private var iconColor: Color {
        switch profile {
        case .computeGuard: return .blue
        case .closedLidEco: return .green
        case .fullAwake: return .purple
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
