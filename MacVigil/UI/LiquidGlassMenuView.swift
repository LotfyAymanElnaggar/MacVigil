import SwiftUI
import AppKit

// MARK: - Everyday menu

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
        ZStack {
            MVGlassBackdrop()

            ScrollView {
                VStack(spacing: 13) {
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
                            .padding(.horizontal, 5)
                            .lineLimit(3)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: 690)
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
        MVGlassCard(padding: 13) {
            HStack(spacing: 12) {
                MVAppGlyph(size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("MacVigil")
                        .font(.title3.weight(.bold))
                    HStack(spacing: 7) {
                        Circle()
                            .fill(manager.isActive ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(manager.isActive ? statusText : "Ready to protect your work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let battery = power.batteryPercent {
                    VStack(alignment: .trailing, spacing: 3) {
                        Label("\(battery)%", systemImage: power.onBatteryPower ? "battery.50" : "battery.100.bolt")
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Text(power.thermalStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            HStack(spacing: 12) {
                Image(systemName: manager.isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 23, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(primarySubtitle)
                        .font(.caption)
                        .opacity(0.82)
                        .lineLimit(1)
                }
                Spacer()
                MVKeycap("⌥⌘V")
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MVGlassActionButtonStyle(tint: manager.isActive ? .red : .accentColor, prominent: true))
        .frame(maxWidth: .infinity)
        .disabled(isStopping || updater.isInstalling)
        .help(manager.isActive ? "Stop Vigil and restore normal macOS sleep behavior" : "Start the selected Vigil configuration")
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
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    sectionTitle("Duration")
                    Spacer()
                    Text(durationSummary)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.accentColor)
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
            VStack(alignment: .leading, spacing: 9) {
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
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.availableVersion.map { "Update to \($0)" } ?? "Update Now")
                        .font(.subheadline.weight(.semibold))
                    Text(manager.isActive ? "Review the update without interrupting Vigil" : "Install the verified GitHub release")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
        .frame(maxWidth: .infinity)
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
            destinationButton(title: "Settings", icon: "gearshape.fill", badge: nil, windowID: "settings")
        }
    }

    private func destinationButton(title: String, icon: String, badge: String?, windowID: String) -> some View {
        MVGlassNavigationButton(title: title, icon: icon, badge: badge) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: windowID)
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
        return manager.selectedDuration == .custom ? formatMinutes(manager.customMinutes) : manager.selectedDuration.title
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func durationButton(_ title: String, _ duration: SessionDuration, custom: Int? = nil) -> some View {
        let selected = duration == .custom && custom != nil
            ? manager.selectedDuration == .custom && manager.customMinutes == custom
            : manager.selectedDuration == duration

        return Button {
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
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(MVGlassPillButtonStyle(selected: selected))
        .frame(maxWidth: .infinity)
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

// MARK: - Glass Settings

struct LiquidGlassSettingsView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController
    @ObservedObject var hotkeys: GlobalHotkeyManager

    @Environment(\.openWindow) private var openWindow
    @State private var selection: Section = .general
    @State private var batteryReserve = 15.0
    @State private var durationMinutes = 60.0

    private enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case vigil = "Vigil"
        case jobGuard = "Job Guard"
        case statistics = "Statistics"
        case hotkeys = "Hotkeys"
        case updates = "Updates"
        case power = "Power & Safety"
        case appearance = "Appearance"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .vigil: return "bolt.shield"
            case .jobGuard: return "briefcase"
            case .statistics: return "chart.bar.xaxis"
            case .hotkeys: return "keyboard"
            case .updates: return "arrow.triangle.2.circlepath"
            case .power: return "battery.100.bolt"
            case .appearance: return "paintbrush"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            MVGlassBackdrop()

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selection.rawValue)
                                    .font(.title2.weight(.bold))
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if manager.isActive {
                                Label("Vigil active", systemImage: "bolt.shield.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }

                        content
                    }
                    .padding(26)
                }
            }
        }
        .frame(width: 980, height: 710)
        .onAppear {
            batteryReserve = Double(manager.lowBatteryCutoff)
            durationMinutes = Double(preferredMinutes)
            updater.refreshLaunchAtLoginState()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 11) {
                MVAppGlyph(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacVigil").font(.headline)
                    Text("Settings").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            ForEach(Section.allCases) { item in
                MVGlassSidebarButton(
                    title: item.rawValue,
                    icon: item.icon,
                    selected: selection == item
                ) {
                    selection = item
                }
            }

            Spacer()

            MVGlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(manager.isActive ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(manager.isActive ? "Vigil active" : "Vigil idle")
                            .font(.caption.weight(.semibold))
                    }
                    Text(manager.isActive ? manager.configurationName : "Normal macOS sleep behavior")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if hotkeys.enabled {
                        HStack(spacing: 5) {
                            MVKeycap("⌥⌘V")
                            Text("Start / Stop")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(17)
        .frame(width: 245)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general: general
        case .vigil: vigil
        case .jobGuard: jobGuard
        case .statistics: statistics
        case .hotkeys: hotkeySettings
        case .updates: updates
        case .power: powerSafety
        case .appearance: appearance
        case .about: about
        }
    }

    private var general: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                VStack(spacing: 7) {
                    toggleRow("Launch at login", "Start MacVigil automatically after sign-in.", "power", updater.launchAtLoginEnabled) {
                        updater.setLaunchAtLogin($0)
                    }
                    toggleRow("Global hotkeys", "Control Vigil without opening the menu-bar panel.", "keyboard", hotkeys.enabled) {
                        hotkeys.setEnabled($0)
                    }
                    toggleRow("Automatic update checks", "Check GitHub in the background while MacVigil is running.", "bell", updater.automaticChecksEnabled) {
                        updater.automaticChecksEnabled = $0
                        updater.savePreferences()
                        updater.startPeriodicChecks()
                    }
                }
            }
            modeDurationCard
            reserveCard
        }
    }

    private var modeDurationCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Default mode & duration").font(.headline)
                    Spacer()
                    Text("⌥⌘1 / 2 / 3")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 9) {
                    MVModeButton(profile: .computeGuard, selected: matches(.computeGuard)) {
                        Task { _ = await manager.changeModeLive(.computeGuard) }
                    }
                    MVModeButton(profile: .closedLidEco, selected: matches(.closedLidEco)) {
                        Task { _ = await manager.changeModeLive(.closedLidEco) }
                    }
                    MVModeButton(profile: .fullAwake, selected: matches(.fullAwake)) {
                        Task { _ = await manager.changeModeLive(.fullAwake) }
                    }
                }
                HStack(spacing: 7) {
                    durationButton("15m", .fifteenMinutes)
                    durationButton("30m", .thirtyMinutes)
                    durationButton("1h", .oneHour)
                    durationButton("2h", .twoHours)
                    durationButton("4h", .custom, 240)
                    durationButton("∞", .indefinite)
                }
                Slider(value: $durationMinutes, in: 5...720, step: 5) { editing in
                    guard !editing else { return }
                    Task { _ = await manager.changeDurationLive(.custom, customMinutes: Int(durationMinutes.rounded())) }
                }
                .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)
                Text("Custom duration: \(formatMinutes(Int(durationMinutes.rounded())))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reserveCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Battery reserve").font(.headline)
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
                Text("Battery safety stops Vigil at the configured reserve when enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vigil: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Protection switches").font(.headline)
                    Text("Presets populate these switches. Every major behavior remains independently controllable, including safe live changes while Vigil is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            MVGlassCard {
                VStack(spacing: 7) {
                    optionRow("Prevent system sleep", "Keep the Mac from entering system sleep.", .preventSystemSleep)
                    optionRow("Prevent idle system sleep", "Block idle sleep while work is protected.", .preventIdleSystemSleep)
                    optionRow("Prevent display sleep", "Keep display sleep logically blocked.", .keepDisplayAwake)
                    optionRow("Veto idle sleep requests", "Cancel cancellable idle-sleep requests.", .vetoIdleSleepRequests)
                    optionRow("Global SleepDisabled", "Use pmset closed-lid protection when authorized.", .useGlobalSleepDisable)
                    optionRow("Kernel clamshell guard", "Experimental low-level closed-lid protection.", .useKernelLidGuard)
                    optionRow("Darken built-in display on lid close", "Reduce built-in backlight while protected.", .darkenBuiltinDisplayOnLidClose)
                }
            }
        }
    }

    private var jobGuard: some View {
        VStack(spacing: 15) {
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "job-guard")
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Multi-job Job Guard").font(.headline)
                        Text(jobs.isWatching
                             ? "\(jobs.activeJobCount) protected job\(jobs.activeJobCount == 1 ? "" : "s") attached."
                             : "Protect multiple processes and commands; Vigil releases after the final selected job finishes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(jobs.isWatching ? "Manage Jobs" : "Open Job Guard")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(15)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
            .frame(maxWidth: .infinity)

            MVGlassCard {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Session ownership").font(.headline)
                    Text("Changing modes or individual protection options changes only the power profile. Job Guard stays attached and continues to own when the session ends.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statistics: some View {
        StatisticsDashboardView(manager: manager, power: power)
    }

    private var hotkeySettings: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                toggleRow("Enable global hotkeys", "Hotkeys work even when the MacVigil menu is closed.", "keyboard", hotkeys.enabled) {
                    hotkeys.setEnabled($0)
                }
            }

            MVGlassCard {
                VStack(spacing: 7) {
                    ForEach(GlobalHotkeyManager.shortcuts) { shortcut in
                        HStack(spacing: 13) {
                            Image(systemName: shortcut.id == 1 ? "bolt.shield.fill" : "slider.horizontal.3")
                                .frame(width: 28)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcut.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(shortcut.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            MVKeycap(shortcut.keys)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.white.opacity(0.11), lineWidth: 1)
                        }
                    }
                }
            }

            if let status = hotkeys.lastActionText {
                Label(status, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Closed-Lid Eco safety and authorization rules still apply when a hotkey is used. A mode hotkey changes the profile underneath the current session and does not detach Job Guard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var updates: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                VStack(spacing: 7) {
                    toggleRow("Automatic checks", "Check at launch, hourly while running, and after wake.", "arrow.triangle.2.circlepath", updater.automaticChecksEnabled) {
                        updater.automaticChecksEnabled = $0
                        updater.savePreferences()
                        updater.startPeriodicChecks()
                    }
                    toggleRow("Automatic install", "Install only after Vigil becomes inactive.", "arrow.down.app", updater.automaticInstallEnabled) {
                        updater.automaticInstallEnabled = $0
                        updater.savePreferences()
                    }
                }
            }

            MVGlassCard {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MacVigil \(updater.currentVersion)").font(.headline)
                            Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await updater.checkForUpdates(userInitiated: true) }
                        } label: {
                            Label(updater.isChecking ? "Checking…" : "Check Now", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
                        .frame(maxWidth: .infinity)
                        .disabled(updater.isChecking || updater.isInstalling)

                        if updater.hasUpdate {
                            Button {
                                if manager.isActive {
                                    openWindow(id: "update-confirmation")
                                } else {
                                    Task { await updater.installAvailableUpdate() }
                                }
                            } label: {
                                Label(updater.isInstalling ? "Updating…" : "Update Now", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: true))
                            .frame(maxWidth: .infinity)
                            .disabled(updater.isInstalling)
                        }
                    }
                }
            }
        }
    }

    private var powerSafety: some View {
        VStack(spacing: 15) {
            reserveCard
            MVGlassCard {
                VStack(spacing: 7) {
                    optionRow("Battery safety", "Stop protection at the configured reserve.", .enableBatterySafety)
                    optionRow("Critical thermal cutoff", "Keep macOS thermal safety in control.", .enableThermalSafety)
                    toggleRow("Require external power for closed-lid mode", "Release closed-lid protection if the Mac switches to battery.", "powerplug", power.requireExternalPowerForClosedLid) {
                        power.setRequireExternalPowerForClosedLid($0)
                    }
                }
            }

            MVGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Closed-lid authorization").font(.headline)
                            Text(manager.authorizationStatusText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Button {
                        if manager.authorizationInstalled {
                            Task { await manager.removeClosedLidAuthorization() }
                        } else {
                            Task { await manager.installClosedLidAuthorization() }
                        }
                    } label: {
                        Label(manager.authorizationInstalled ? "Remove Authorization" : "Install Authorization", systemImage: manager.authorizationInstalled ? "minus.circle" : "checkmark.shield")
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: manager.authorizationInstalled ? .orange : .accentColor, prominent: !manager.authorizationInstalled))
                    .frame(maxWidth: .infinity)

                    Text("Closed-lid workloads can generate significant heat. Use a hard, ventilated surface—not a bag, sleeve, drawer, or other enclosed space.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var appearance: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Layered Liquid Glass", systemImage: "drop.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text("MacVigil now layers translucent material over subtle blue and violet depth fields, adds edge highlights, and gives every interactive surface a full-row hover, pressed, and selected state.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Text("System appearance")
                        Spacer()
                        Text("Follows macOS").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            MVGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interaction rule").font(.headline)
                    Text("The whole visible control is the hit target. Sidebar rows, mode cards, duration pills, settings toggles, update actions, and navigation cards no longer require clicking directly on the text.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var about: some View {
        VStack(spacing: 15) {
            MVGlassCard {
                HStack(spacing: 15) {
                    MVAppGlyph(size: 74)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MacVigil").font(.title2.weight(.bold))
                        Text("Version \(updater.currentVersion)").font(.subheadline).foregroundStyle(.secondary)
                        Text("Local work, uninterrupted.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            MVGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Link("GitHub repository", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil")!)
                    Link("Latest releases", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/releases")!)
                    Text("MacVigil is currently distributed with ad-hoc signing rather than Developer ID notarization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        switch selection {
        case .general: return "The settings most people need most often."
        case .vigil: return "Fine-grained protection controls, including safe live changes."
        case .jobGuard: return "Protect multiple jobs until the final selected job finishes."
        case .statistics: return "Recent local session, battery, thermal, and mode summaries."
        case .hotkeys: return "Control Vigil without opening the menu first."
        case .updates: return "Background update discovery and installation."
        case .power: return "Battery, thermal, and closed-lid safety."
        case .appearance: return "Layered glass presentation and full-surface interactions."
        case .about: return "Version and project information."
        }
    }

    private var updateStatus: String {
        if let version = updater.availableVersion { return "Version \(version) is available." }
        if let status = updater.statusText { return status }
        if let date = updater.lastCheckAt { return "Last checked \(date.formatted(date: .omitted, time: .shortened))." }
        return "Automatic checks do not require opening the menu-bar panel."
    }

    private func toggleRow(_ title: String, _ detail: String, _ icon: String, _ value: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            set(!value)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 30)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(value))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(MVInteractiveGlassModifier(cornerRadius: 13, selected: value, tint: .accentColor))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func optionRow(_ title: String, _ detail: String, _ option: VigilOption) -> some View {
        let value = optionValue(option)
        return Button {
            Task { _ = await manager.changeOptionLive(option, to: !value) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(value))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(MVInteractiveGlassModifier(cornerRadius: 13, selected: value, tint: .accentColor))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func optionValue(_ option: VigilOption) -> Bool {
        switch option {
        case .preventSystemSleep: return manager.preventSystemSleep
        case .preventIdleSystemSleep: return manager.preventIdleSystemSleep
        case .keepDisplayAwake: return manager.keepDisplayAwake
        case .vetoIdleSleepRequests: return manager.vetoIdleSleepRequests
        case .useGlobalSleepDisable: return manager.useGlobalSleepDisable
        case .useKernelLidGuard: return manager.useKernelLidGuard
        case .darkenBuiltinDisplayOnLidClose: return manager.darkenBuiltinDisplayOnLidClose
        case .enableBatterySafety: return manager.enableBatterySafety
        case .enableThermalSafety: return manager.enableThermalSafety
        }
    }

    private func durationButton(_ title: String, _ duration: SessionDuration, _ custom: Int? = nil) -> some View {
        let selected = duration == .custom && custom != nil
            ? manager.selectedDuration == .custom && manager.customMinutes == custom
            : manager.selectedDuration == duration

        return Button {
            if let custom { durationMinutes = Double(custom) }
            Task { _ = await manager.changeDurationLive(duration, customMinutes: custom) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(MVGlassPillButtonStyle(selected: selected))
        .frame(maxWidth: .infinity)
        .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)
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
}

// MARK: - Glass Job Guard

struct LiquidGlassJobGuardWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var showManualPID = false
    @State private var isStopping = false

    private enum Field: Hashable {
        case search
        case pid
        case command
    }

    var body: some View {
        ZStack {
            MVGlassBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if manager.isActive || updater.hasUpdate {
                        criticalActions
                    }

                    if jobs.isWatching {
                        activeJobsCard
                    }

                    suggestedWorkloadsCard
                    processPickerCard
                    commandCard

                    if let error = jobs.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let status = jobs.statusText {
                        Label(status, systemImage: jobs.isWatching ? "bolt.shield.fill" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 700, height: 790)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task { await jobs.refreshProcesses() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MVAppGlyph(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Job Guard")
                    .font(.title2.weight(.bold))
                Text("Protect the work until every selected job is done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(minWidth: 62, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
            .keyboardShortcut(.cancelAction)
        }
    }

    private var criticalActions: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vigil controls")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                if manager.isActive {
                    Button {
                        guard !isStopping else { return }
                        isStopping = true
                        Task {
                            await manager.stopLiveSession()
                            isStopping = false
                        }
                    } label: {
                        Label(isStopping ? "Stopping Vigil…" : "Stop Vigil", systemImage: "stop.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: .red, prominent: true))
                    .frame(maxWidth: .infinity)
                    .disabled(isStopping || updater.isInstalling)
                }

                if updater.hasUpdate {
                    Button {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if manager.isActive {
                            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
                        }
                    } label: {
                        Label(updater.availableVersion.map { "Update to \($0)" } ?? "Update Now", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var activeJobsCard: some View {
        MVGlassCard(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("JOB GUARD ACTIVE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(jobs.activeJobCount == 1 ? "1 protected job" : "\(jobs.activeJobCount) protected jobs")
                            .font(.headline)
                        Text("Vigil releases only after the last running job finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.green)
                        Text(jobs.elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(jobs.protectedJobs) { job in
                        protectedJobRow(job)
                    }
                }

                Button {
                    jobs.detachAll()
                } label: {
                    Label("Detach All", systemImage: "link.badge.minus")
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MVGlassActionButtonStyle(tint: .orange, prominent: false))
                .frame(maxWidth: .infinity)
                .disabled(!jobs.isWatching)
            }
        }
    }

    private func protectedJobRow(_ job: JobAwareController.ProtectedJob) -> some View {
        HStack(spacing: 11) {
            Image(systemName: job.state == .running ? job.kind.systemImage : job.state.systemImage)
                .foregroundStyle(job.state == .running ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.subheadline.weight(job.state == .running ? .semibold : .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text("PID \(job.pid)").monospacedDigit()
                    Text("•")
                    Text(jobs.elapsedText(for: job)).monospacedDigit()
                    if let exit = job.exitCode {
                        Text("•")
                        Text("exit \(exit)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if job.logURL != nil {
                Button {
                    jobs.openLog(for: job)
                } label: {
                    Text("Log")
                        .frame(minWidth: 48, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
            }

            if job.state == .running {
                Button {
                    jobs.detachJob(job.id)
                } label: {
                    Label("Detach", systemImage: "link.badge.minus")
                        .frame(minWidth: 72, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MVGlassActionButtonStyle(tint: .orange, prominent: false))
            } else {
                Text(job.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var suggestedWorkloadsCard: some View {
        let suggestions = Array(jobs.suggestedProcesses.prefix(6))
        MVGlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label(jobs.isWatching ? "Add a suggested workload" : "Suggested workloads", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(jobs.detectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if suggestions.isEmpty {
                    Text("Nothing obvious to protect right now. You can still choose any process below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 5)
                } else {
                    ForEach(suggestions) { process in
                        processRow(process, showCategory: true)
                    }
                }
            }
        }
    }

    private var processPickerCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(jobs.isWatching ? "Add running processes" : "All running processes", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await jobs.refreshProcesses() }
                    } label: {
                        Label(jobs.isRefreshingProcesses ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
                    .disabled(jobs.isRefreshingProcesses)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by app, workload type, process, or PID", text: $jobs.processSearchText)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .search)
                    if !jobs.processSearchText.isEmpty {
                        Button("Clear") { jobs.processSearchText = "" }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(jobs.filteredProcesses.prefix(80))) { process in
                            processRow(process, showCategory: true)
                        }
                        if jobs.filteredProcesses.isEmpty && !jobs.isRefreshingProcesses {
                            Text("No matching processes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 26)
                        }
                    }
                }
                .frame(height: 230)

                DisclosureGroup(isExpanded: $showManualPID) {
                    HStack(spacing: 9) {
                        TextField("PID, for example 43127", text: $jobs.pidText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .pid)
                            .onSubmit { addManualPID() }
                        Button {
                            addManualPID()
                        } label: {
                            Text("Add PID")
                                .frame(minWidth: 82, minHeight: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: true))
                        .disabled(jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Enter a PID manually")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func processRow(_ process: JobAwareController.ProcessCandidate, showCategory: Bool) -> some View {
        let protected = jobs.isProtected(pid: process.pid)

        return Button {
            guard !protected else { return }
            Task { await jobs.watchProcess(process) }
        } label: {
            HStack(spacing: 11) {
                processIcon(process)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if showCategory, let kind = process.workloadKind {
                            Label(kind.title, systemImage: kind.systemImage)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("PID \(process.pid)").monospacedDigit()
                        if !process.cpuText.isEmpty {
                            Text("•")
                            Text("CPU \(process.cpuText)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label(protected ? "Protected" : "Add", systemImage: protected ? "checkmark.shield.fill" : "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(protected ? Color.green : Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(MVInteractiveGlassModifier(cornerRadius: 12, selected: protected, tint: protected ? .green : .accentColor))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(protected)
    }

    private func processIcon(_ process: JobAwareController.ProcessCandidate) -> some View {
        Group {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else if let kind = process.workloadKind {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var commandCard: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label(jobs.isWatching ? "Add a command" : "Run a command", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    if !jobs.commandHistory.isEmpty {
                        Menu("Recent") {
                            ForEach(jobs.commandHistory, id: \.self) { command in
                                Button(command) { jobs.useCommandFromHistory(command) }
                            }
                            Divider()
                            Button("Clear History", role: .destructive) { jobs.clearCommandHistory() }
                        }
                    }
                }

                Text("Commands are non-interactive, run with /bin/zsh -lc from your home directory, and keep an individual output log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("npm test  ·  python train.py  ·  make build", text: $jobs.commandText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .command)
                    .onSubmit { runCommand() }

                Button {
                    runCommand()
                } label: {
                    Label(jobs.isWatching ? "Add Command to Job Guard" : "Run with Vigil", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: true))
                .frame(maxWidth: .infinity)
                .disabled(jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addManualPID() {
        guard !jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.watchPID() }
    }

    private func runCommand() {
        guard !jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.runCommand() }
    }
}

// MARK: - Glass Statistics wrapper

struct LiquidGlassStatisticsWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    var body: some View {
        ZStack {
            MVGlassBackdrop()
            ScrollView {
                StatisticsDashboardView(manager: manager, power: power)
                    .padding(22)
            }
        }
        .frame(width: 760, height: 720)
    }
}

// MARK: - Glass update window

struct LiquidGlassUpdateConfirmationView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var localError: String?

    var body: some View {
        ZStack {
            MVGlassBackdrop()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    MVAppGlyph(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Update MacVigil")
                            .font(.title2.weight(.bold))
                        Text(versionLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if manager.isActive {
                    MVGlassCard(tint: .orange) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Vigil is currently active", systemImage: "bolt.shield.fill")
                                .font(.headline)
                            Text("Installing an update restarts MacVigil. The current Vigil session must stop first; protected jobs themselves are never terminated.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(manager.configurationName)
                                Spacer()
                                Text(remainingText).monospacedDigit()
                            }
                            .font(.caption.weight(.medium))
                        }
                    }
                }

                if let error = localError ?? updater.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if working || updater.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(updater.statusText ?? (manager.isActive ? "Stopping Vigil…" : "Preparing update…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    beginUpdate()
                } label: {
                    Label(primaryButtonTitle, systemImage: manager.isActive ? "stop.circle.fill" : "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MVGlassActionButtonStyle(tint: manager.isActive ? .red : .accentColor, prominent: true))
                .frame(maxWidth: .infinity)
                .disabled(working || updater.isInstalling)

                HStack(spacing: 10) {
                    Button {
                        updater.openReleasePage()
                    } label: {
                        Text("View Release")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: .accentColor, prominent: false))
                    .frame(maxWidth: .infinity)

                    Button {
                        dismiss()
                    } label: {
                        Text(manager.isActive ? "Keep Vigil Running" : "Cancel")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MVGlassActionButtonStyle(tint: .secondary, prominent: false))
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(23)
        }
        .frame(width: 500, height: manager.isActive ? 380 : 300)
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    private var versionLine: String {
        if let version = updater.availableVersion {
            return "MacVigil \(updater.currentVersion) → \(version)"
        }
        return "Install the latest available release"
    }

    private var primaryButtonTitle: String {
        if working || updater.isInstalling { return "Updating…" }
        return manager.isActive ? "Stop Vigil & Update" : "Update Now"
    }

    private var remainingText: String {
        guard let remaining = manager.effectiveRemainingSeconds else { return "No timer" }
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds) }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private func beginUpdate() {
        guard !working else { return }
        working = true
        localError = nil
        Task {
            if manager.isActive {
                await manager.stopLiveSession()
                guard !manager.isActive else {
                    localError = "Vigil could not be stopped safely. The update was not started."
                    working = false
                    return
                }
            }
            await updater.installAvailableUpdate()
            if let error = updater.lastError {
                localError = error
                working = false
            }
        }
    }
}

// MARK: - Glass design system

struct MVGlassBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color.blue.opacity(0.08),
                        Color.purple.opacity(0.07),
                        Color(nsColor: .windowBackgroundColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: proxy.size.width * 0.55)
                    .blur(radius: 70)
                    .offset(x: -proxy.size.width * 0.28, y: -proxy.size.height * 0.25)

                Circle()
                    .fill(Color.purple.opacity(0.16))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 80)
                    .offset(x: proxy.size.width * 0.35, y: proxy.size.height * 0.28)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.74)

                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }
}

struct MVAppGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.95), Color.purple.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 1)
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: size * 0.49, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.blue.opacity(0.22), radius: 10, y: 5)
        .shadow(color: Color.purple.opacity(0.15), radius: 14, y: 8)
    }
}

struct MVGlassCard<Content: View>: View {
    let padding: CGFloat
    let tint: Color
    let content: Content

    init(padding: CGFloat = 14, tint: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.13),
                                    tint.opacity(0.045),
                                    Color.white.opacity(0.025)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.36), tint.opacity(0.18), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 90, height: 1)
                    .padding(.top, 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
            .shadow(color: tint.opacity(0.055), radius: 16, y: 3)
    }
}

struct MVInteractiveGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let selected: Bool
    let tint: Color
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: selected
                                    ? [tint.opacity(0.19), tint.opacity(0.08), Color.white.opacity(0.045)]
                                    : [Color.white.opacity(hovering ? 0.13 : 0.065), tint.opacity(hovering ? 0.07 : 0.025), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(selected ? tint.opacity(0.62) : Color.white.opacity(hovering ? 0.30 : 0.13), lineWidth: 1)
            }
            .shadow(color: selected ? tint.opacity(0.12) : Color.black.opacity(hovering ? 0.10 : 0.045), radius: hovering || selected ? 10 : 5, y: 4)
            .onHover { value in
                hovering = value
            }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.14), value: selected)
    }
}

struct MVGlassActionButtonStyle: ButtonStyle {
    let tint: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: prominent
                                    ? [tint.opacity(configuration.isPressed ? 0.72 : 0.92), tint.opacity(0.64)]
                                    : [Color.white.opacity(configuration.isPressed ? 0.08 : 0.12), tint.opacity(configuration.isPressed ? 0.07 : 0.11)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(prominent ? Color.white.opacity(0.27) : tint.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: tint.opacity(prominent ? 0.20 : 0.08), radius: configuration.isPressed ? 5 : 11, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct MVGlassPillButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.17) : Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: selected ? Color.accentColor.opacity(0.10) : Color.clear, radius: 7, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct MVGlassNavigationButton: View {
    let title: String
    let icon: String
    let badge: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 30, height: 25)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 9, y: -6)
                    }
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.13 : 0.055))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(hovering ? 0.31 : 0.13), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(hovering ? 0.10 : 0.04), radius: hovering ? 9 : 4, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

struct MVGlassSidebarButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                ZStack {
                    if selected || hovering {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.46) : Color.white.opacity(hovering ? 0.17 : 0), lineWidth: 1)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

struct MVKeycap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
    }
}

struct MVModeButton: View {
    let profile: RuntimeProfile
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
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
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: selected
                                    ? [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.07)]
                                    : [Color.white.opacity(hovering ? 0.13 : 0.055), iconColor.opacity(hovering ? 0.07 : 0.025)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.63) : Color.white.opacity(hovering ? 0.30 : 0.13), lineWidth: 1)
            }
            .shadow(color: selected ? Color.accentColor.opacity(0.13) : Color.black.opacity(hovering ? 0.09 : 0.035), radius: hovering || selected ? 9 : 4, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
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
