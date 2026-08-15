import SwiftUI
import AppKit

struct MacVigilSettingsView: View {
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
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selection.rawValue)
                            .font(.title2.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    content
                }
                .padding(24)
            }
        }
        .frame(width: 930, height: 680)
        .background(.ultraThinMaterial)
        .onAppear {
            batteryReserve = Double(manager.lowBatteryCutoff)
            durationMinutes = Double(preferredMinutes)
            updater.refreshLaunchAtLoginState()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bolt.shield.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 21, weight: .semibold))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacVigil").font(.headline)
                    Text("Settings").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            ForEach(Section.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon).frame(width: 20)
                        Text(item.rawValue)
                            .font(.subheadline.weight(selection == item ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selection == item ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(selection == item ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            MVGlassCard {
                VStack(alignment: .leading, spacing: 4) {
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
                        Text("⌥⌘V · Start / Stop")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 225)
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
        VStack(spacing: 14) {
            MVGlassCard {
                VStack(spacing: 0) {
                    toggleRow("Launch at login", "Start MacVigil automatically after sign-in.", "power", updater.launchAtLoginEnabled) {
                        updater.setLaunchAtLogin($0)
                    }
                    Divider().padding(.leading, 42)
                    toggleRow("Global hotkeys", "Control Vigil without opening the menu-bar panel.", "keyboard", hotkeys.enabled) {
                        hotkeys.setEnabled($0)
                    }
                    Divider().padding(.leading, 42)
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
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Default mode & duration").font(.headline)
                    Spacer()
                    Text("Mode hotkeys: ⌥⌘1 / 2 / 3")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
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
                HStack(spacing: 6) {
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
            VStack(alignment: .leading, spacing: 8) {
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
        VStack(spacing: 14) {
            MVGlassCard {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Protection switches").font(.headline)
                    Text("Presets only populate these controls. Every major behavior remains independently switchable, including while Vigil is active when safe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            MVGlassCard {
                VStack(spacing: 0) {
                    optionRow("Prevent system sleep", "Keep the Mac from entering system sleep.", .preventSystemSleep)
                    Divider()
                    optionRow("Prevent idle system sleep", "Block idle sleep while work is protected.", .preventIdleSystemSleep)
                    Divider()
                    optionRow("Prevent display sleep", "Keep display sleep logically blocked.", .keepDisplayAwake)
                    Divider()
                    optionRow("Veto idle sleep requests", "Cancel cancellable idle-sleep requests.", .vetoIdleSleepRequests)
                    Divider()
                    optionRow("Global SleepDisabled", "Use pmset closed-lid protection when authorized.", .useGlobalSleepDisable)
                    Divider()
                    optionRow("Kernel clamshell guard", "Experimental low-level closed-lid protection.", .useKernelLidGuard)
                    Divider()
                    optionRow("Darken built-in display on lid close", "Reduce built-in backlight while protected.", .darkenBuiltinDisplayOnLidClose)
                }
            }
        }
    }

    private var jobGuard: some View {
        VStack(spacing: 14) {
            MVGlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Multi-job Job Guard").font(.headline)
                        Text(jobs.isWatching
                             ? "\(jobs.activeJobCount) protected job\(jobs.activeJobCount == 1 ? "" : "s") attached."
                             : "Protect multiple processes and commands; Vigil releases after the final selected job finishes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(jobs.isWatching ? "Manage Jobs" : "Open Job Guard") {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        openWindow(id: "job-guard")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
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
        VStack(spacing: 14) {
            MVGlassCard {
                toggleRow("Enable global hotkeys", "Hotkeys work even when the MacVigil menu is closed.", "keyboard", hotkeys.enabled) {
                    hotkeys.setEnabled($0)
                }
            }

            MVGlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(GlobalHotkeyManager.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
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
                            Text(shortcut.keys)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.vertical, 10)
                        if index < GlobalHotkeyManager.shortcuts.count - 1 {
                            Divider().padding(.leading, 41)
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
        VStack(spacing: 14) {
            MVGlassCard {
                VStack(spacing: 0) {
                    toggleRow("Automatic checks", "Check at launch, hourly while running, and after wake.", "arrow.triangle.2.circlepath", updater.automaticChecksEnabled) {
                        updater.automaticChecksEnabled = $0
                        updater.savePreferences()
                        updater.startPeriodicChecks()
                    }
                    Divider().padding(.leading, 42)
                    toggleRow("Automatic install", "Install only after Vigil becomes inactive.", "arrow.down.app", updater.automaticInstallEnabled) {
                        updater.automaticInstallEnabled = $0
                        updater.savePreferences()
                    }
                }
            }
            MVGlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacVigil \(updater.currentVersion)").font(.headline)
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updater.isChecking ? "Checking…" : "Check Now") {
                        Task { await updater.checkForUpdates(userInitiated: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(updater.isChecking || updater.isInstalling)

                    if updater.hasUpdate {
                        Button(updater.isInstalling ? "Updating…" : "Update Now") {
                            if manager.isActive {
                                openWindow(id: "update-confirmation")
                            } else {
                                Task { await updater.installAvailableUpdate() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isInstalling)
                    }
                }
            }
        }
    }

    private var powerSafety: some View {
        VStack(spacing: 14) {
            reserveCard
            MVGlassCard {
                VStack(spacing: 0) {
                    optionRow("Battery safety", "Stop protection at the configured reserve.", .enableBatterySafety)
                    Divider()
                    optionRow("Critical thermal cutoff", "Keep macOS thermal safety in control.", .enableThermalSafety)
                    Divider()
                    toggleRow("Require external power for closed-lid mode", "Release closed-lid protection if the Mac switches to battery.", "powerplug", power.requireExternalPowerForClosedLid) {
                        power.setRequireExternalPowerForClosedLid($0)
                    }
                }
            }
            MVGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Closed-lid authorization").font(.headline)
                            Text(manager.authorizationStatusText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.authorizationInstalled {
                            Button("Remove") {
                                Task { await manager.removeClosedLidAuthorization() }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Install Authorization") {
                                Task { await manager.installClosedLidAuthorization() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Text("Closed-lid workloads can generate significant heat. Use a hard, ventilated surface—not a bag, sleeve, drawer, or other enclosed space.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var appearance: some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Liquid Glass interface", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Text("The menu-bar panel is intentionally optimized for quick Start/Stop, mode, duration, battery reserve, Job Guard, Statistics, and Settings. Fine-grained options stay here rather than crowding the everyday controls.")
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
    }

    private var about: some View {
        VStack(spacing: 14) {
            MVGlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacVigil").font(.title2.weight(.bold))
                        Text("Version \(updater.currentVersion)").font(.subheadline).foregroundStyle(.secondary)
                        Text("Local work, uninterrupted.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            MVGlassCard {
                VStack(alignment: .leading, spacing: 10) {
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
        case .appearance: return "Native glass presentation and interaction design."
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 9)
    }

    private func optionRow(_ title: String, _ detail: String, _ option: VigilOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { optionValue(option) },
                set: { enabled in
                    Task { _ = await manager.changeOptionLive(option, to: enabled) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 9)
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

        return Button(title) {
            if let custom { durationMinutes = Double(custom) }
            Task { _ = await manager.changeDurationLive(duration, customMinutes: custom) }
        }
        .buttonStyle(MVGlassPillButtonStyle(selected: selected))
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
