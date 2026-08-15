import SwiftUI
import AppKit

struct LiquidGlassMenuView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController

    @Environment(\.openWindow) private var openWindow
    @State private var durationMinutes = 60.0
    @State private var batteryReserve = 15.0
    @State private var message: String?
    @State private var showClosedLidSafety = false
    @State private var isStopping = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                statusRow
                modePicker
                durationCard
                batteryCard
                jobGuardCard
                actions

                if let text = message ?? manager.lastError ?? updater.lastError {
                    Label(text, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .frame(width: 470, height: 720)
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
        MVGlassCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .shadow(color: Color.accentColor.opacity(0.25), radius: 9, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacVigil").font(.title2.weight(.bold))
                    Text("Local work, uninterrupted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("VIGIL").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Toggle("Vigil", isOn: vigilBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .disabled(isStopping || updater.isInstalling)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Label(manager.isActive ? "ACTIVE" : "READY", systemImage: manager.isActive ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(manager.isActive ? Color.green : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let battery = power.batteryPercent {
                Label("\(battery)%", systemImage: power.onBatteryPower ? "battery.50" : "battery.100.bolt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Mode")
            HStack(spacing: 8) {
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
                    Text(durationSummary).font(.caption.monospacedDigit()).foregroundStyle(Color.accentColor)
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
                        if !ok { message = "Job Guard owns this session lifetime. Duration can be changed after Job Guard releases or detaches." }
                    }
                }
                HStack {
                    Text("5m")
                    Spacer()
                    Text("Custom: \(formatMinutes(Int(durationMinutes.rounded())))").fontWeight(.semibold)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Battery reserve")
                    Spacer()
                    Text("\(Int(batteryReserve))%")
                        .font(.headline.monospacedDigit())
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
                    Text("Stop Vigil at the reserved level")
                    Spacer()
                    Text("30%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var jobGuardCard: some View {
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "job-guard")
        } label: {
            MVGlassCard {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.14))
                        Image(systemName: jobs.isWatching ? "briefcase.fill" : "briefcase")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Job Guard").font(.headline)
                            if jobs.isWatching {
                                Text("PROTECTING").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(jobSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if jobs.isWatching {
                        VStack(spacing: 0) {
                            Text("\(jobs.activeJobCount)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Color.accentColor)
                            Text(jobs.activeJobCount == 1 ? "job" : "jobs").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if manager.isActive {
                Button { stopVigil() } label: {
                    Label(isStopping ? "Stopping…" : "Stop Vigil", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(isStopping || updater.isInstalling)
            }
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var vigilBinding: Binding<Bool> {
        Binding(get: { manager.isActive }, set: { enabled in
            if enabled {
                if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                    showClosedLidSafety = true
                } else {
                    Task { await manager.startFreshSession() }
                }
            } else {
                stopVigil()
            }
        })
    }

    private var statusText: String {
        if jobs.isWatching { return jobs.displayStatus }
        if manager.isLiveReconfiguring { return "Applying protection changes…" }
        if updater.hasUpdate, let version = updater.availableVersion { return "MacVigil \(version) is available" }
        if manager.isActive { return displayModeName }
        return "Choose a mode and start Vigil"
    }

    private var jobSubtitle: String {
        if jobs.isWatching { return "Vigil releases after the last protected job finishes." }
        if jobs.detectedWorkloadCount > 0 { return "\(jobs.detectedWorkloadCount) likely workload\(jobs.detectedWorkloadCount == 1 ? "" : "s") detected." }
        return "Protect processes and commands until all selected work is done."
    }

    private var durationSummary: String {
        if jobs.isWatching { return "Job Guard owned" }
        if manager.isActive {
            guard let seconds = manager.effectiveRemainingSeconds else { return "∞" }
            return remainingText(Int(seconds))
        }
        return manager.selectedDuration == .custom ? formatMinutes(manager.customMinutes) : manager.selectedDuration.title
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
    }

    private func durationButton(_ title: String, _ duration: SessionDuration, custom: Int? = nil) -> some View {
        let selected = duration == .custom && custom != nil
            ? manager.selectedDuration == .custom && manager.customMinutes == custom
            : manager.selectedDuration == duration
        return Button(title) {
            if let custom { durationMinutes = Double(custom) }
            Task {
                let ok = await manager.changeDurationLive(duration, customMinutes: custom)
                if !ok { message = "Job Guard controls this session lifetime." } else { message = nil; syncControls() }
            }
        }
        .buttonStyle(MVGlassPillButtonStyle(selected: selected))
        .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)
    }

    private func applyMode(_ profile: RuntimeProfile) {
        Task {
            let ok = await manager.changeModeLive(profile)
            if ok { message = nil }
            else if profile == .closedLidEco && !manager.pmsetPrivilegeAvailable { message = "Closed-Lid Eco requires authorization. Open Settings → Power & Safety." }
            else if manager.lidIsClosed { message = "Open the MacBook lid before removing or changing closed-lid protection." }
            else { message = "MacVigil could not apply that mode safely." }
        }
    }

    private func matches(_ profile: RuntimeProfile) -> Bool {
        switch profile {
        case .computeGuard:
            return manager.preventSystemSleep && manager.preventIdleSystemSleep && !manager.keepDisplayAwake && manager.vetoIdleSleepRequests && !manager.useGlobalSleepDisable && !manager.useKernelLidGuard && !manager.darkenBuiltinDisplayOnLidClose
        case .closedLidEco:
            return manager.preventSystemSleep && manager.preventIdleSystemSleep && manager.vetoIdleSleepRequests && manager.useGlobalSleepDisable && manager.useKernelLidGuard && manager.darkenBuiltinDisplayOnLidClose
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
        Task { await manager.stopLiveSession(); isStopping = false }
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
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 5)
    }
}

struct MVGlassPillButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 7)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045)))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.14), lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct MVModeButton: View {
    let profile: RuntimeProfile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                Text(profile.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(selected ? Color.accentColor : Color.clear)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.horizontal, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: selected ? 1.5 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch profile { case .computeGuard: return "cpu"; case .closedLidEco: return "leaf.fill"; case .fullAwake: return "bolt.fill" }
    }
    private var tint: Color {
        switch profile { case .computeGuard: return .blue; case .closedLidEco: return .green; case .fullAwake: return .purple }
    }
}
