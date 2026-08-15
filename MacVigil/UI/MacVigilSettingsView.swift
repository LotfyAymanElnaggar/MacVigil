import SwiftUI
import AppKit

struct MacVigilSettingsView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController
    @ObservedObject var hotkeys: GlobalHotkeyManager

    @Environment(\.openWindow) private var openWindow
    @State private var selection: SettingsSection? = .general
    @State private var batteryReserve = 15.0
    @State private var durationMinutes = 60.0

    private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
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
            case .power: return "battery.100percent.bolt"
            case .appearance: return "paintbrush"
            case .about: return "info.circle"
            }
        }
    }

    private var currentSection: SettingsSection { selection ?? .general }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(width: 930, height: 680)
        .onAppear {
            batteryReserve = Double(manager.lowBatteryCutoff)
            durationMinutes = Double(preferredMinutes)
            updater.refreshLaunchAtLoginState()
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("MacVigil")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusFooter
        }
    }

    private var statusFooter: some View {
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
                .lineLimit(1)
            if hotkeys.enabled {
                Text("⌥⌘V · Start / Stop")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentSection.rawValue)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            selectedContent
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch currentSection {
        case .general: general
        case .vigil: vigil
        case .jobGuard: jobGuard
        case .statistics:
            ScrollView {
                StatisticsDashboardView(manager: manager, power: power)
                    .padding(24)
            }
        case .hotkeys: hotkeySettings
        case .updates: updates
        case .power: powerSafety
        case .appearance: appearance
        case .about: about
        }
    }

    private var general: some View {
        SwiftUI.Form {
            SwiftUI.Section("Startup & control") {
                settingToggle(
                    "Launch at login",
                    "Start MacVigil automatically after sign-in.",
                    icon: "power",
                    value: updater.launchAtLoginEnabled
                ) { updater.setLaunchAtLogin($0) }

                settingToggle(
                    "Global hotkeys",
                    "Control Vigil without opening the menu-bar panel.",
                    icon: "keyboard",
                    value: hotkeys.enabled
                ) { hotkeys.setEnabled($0) }

                settingToggle(
                    "Automatic update checks",
                    "Check GitHub in the background while MacVigil is running.",
                    icon: "arrow.triangle.2.circlepath",
                    value: updater.automaticChecksEnabled
                ) {
                    updater.automaticChecksEnabled = $0
                    updater.savePreferences()
                    updater.startPeriodicChecks()
                }
            }

            SwiftUI.Section("Default mode") {
                HStack(spacing: 10) {
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
                .padding(.vertical, 4)
            }

            SwiftUI.Section("Default duration") {
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

                LabeledContent("Custom duration") {
                    Text(formatMinutes(Int(durationMinutes.rounded())))
                        .foregroundStyle(.secondary)
                }
            }

            SwiftUI.Section("Battery reserve") {
                Slider(value: $batteryReserve, in: 5...30, step: 1) { editing in
                    guard !editing else { return }
                    manager.lowBatteryCutoff = Int(batteryReserve.rounded())
                    manager.savePreferences()
                }
                LabeledContent("Release threshold") {
                    Text("\(Int(batteryReserve))%")
                        .monospacedDigit()
                }
                Text("Battery safety stops Vigil at the configured reserve when enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var vigil: some View {
        SwiftUI.Form {
            SwiftUI.Section {
                Text("Presets populate these switches. Every major protection behavior remains independently controllable, including safe live changes while Vigil is active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Sleep prevention") {
                optionToggle("Prevent system sleep", "Keep the Mac from entering system sleep.", .preventSystemSleep)
                optionToggle("Prevent idle system sleep", "Block idle sleep while work is protected.", .preventIdleSystemSleep)
                optionToggle("Prevent display sleep", "Keep display sleep logically blocked.", .keepDisplayAwake)
                optionToggle("Veto idle sleep requests", "Cancel cancellable idle-sleep requests.", .vetoIdleSleepRequests)
            }

            SwiftUI.Section("Closed-lid protection") {
                optionToggle("Global SleepDisabled", "Use pmset closed-lid protection when authorized.", .useGlobalSleepDisable)
                optionToggle("Kernel clamshell guard", "Experimental low-level closed-lid protection.", .useKernelLidGuard)
                optionToggle("Darken built-in display on lid close", "Reduce built-in backlight while protected.", .darkenBuiltinDisplayOnLidClose)
            }
        }
        .formStyle(.grouped)
    }

    private var jobGuard: some View {
        SwiftUI.Form {
            SwiftUI.Section("Multi-job protection") {
                LabeledContent("Status") {
                    Text(jobs.isWatching
                         ? "\(jobs.activeJobCount) protected job\(jobs.activeJobCount == 1 ? "" : "s")"
                         : "Idle")
                        .foregroundStyle(jobs.isWatching ? Color.green : Color.secondary)
                }

                Text("Job Guard keeps one Vigil session alive while any selected job is still running and releases protection only after the final protected job finishes naturally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(jobs.isWatching ? "Manage Protected Jobs" : "Open Job Guard") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "job-guard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            SwiftUI.Section("Session ownership") {
                Text("Changing modes or individual protection options changes only the power profile. Job Guard remains attached and continues to own when the session ends.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeySettings: some View {
        SwiftUI.Form {
            SwiftUI.Section {
                settingToggle(
                    "Enable global hotkeys",
                    "Hotkeys work even when the MacVigil menu is closed.",
                    icon: "keyboard",
                    value: hotkeys.enabled
                ) { hotkeys.setEnabled($0) }
            }

            SwiftUI.Section("Shortcuts") {
                ForEach(GlobalHotkeyManager.shortcuts) { shortcut in
                    LabeledContent {
                        Text(shortcut.keys)
                            .font(.body.monospaced().weight(.medium))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                                .font(.body)
                            Text(shortcut.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SwiftUI.Section {
                Text("Closed-Lid Eco safety and authorization rules still apply when a hotkey is used. Mode hotkeys change the profile underneath the current session without detaching Job Guard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var updates: some View {
        SwiftUI.Form {
            SwiftUI.Section("Background updates") {
                settingToggle(
                    "Automatic checks",
                    "Check at launch, hourly while running, and after wake.",
                    icon: "arrow.triangle.2.circlepath",
                    value: updater.automaticChecksEnabled
                ) {
                    updater.automaticChecksEnabled = $0
                    updater.savePreferences()
                    updater.startPeriodicChecks()
                }

                settingToggle(
                    "Automatic install",
                    "Install only after Vigil becomes inactive.",
                    icon: "arrow.down.app",
                    value: updater.automaticInstallEnabled
                ) {
                    updater.automaticInstallEnabled = $0
                    updater.savePreferences()
                }
            }

            SwiftUI.Section("Current version") {
                LabeledContent("Installed") {
                    Text("MacVigil \(updater.currentVersion)")
                }
                LabeledContent("Status") {
                    Text(updateStatus)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(updater.isChecking ? "Checking…" : "Check Now") {
                        Task { await updater.checkForUpdates(userInitiated: true) }
                    }
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
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
    }

    private var powerSafety: some View {
        SwiftUI.Form {
            SwiftUI.Section("Battery & thermal") {
                optionToggle("Battery safety", "Stop protection at the configured reserve.", .enableBatterySafety)
                optionToggle("Critical thermal cutoff", "Keep macOS thermal safety in control.", .enableThermalSafety)

                Slider(value: $batteryReserve, in: 5...30, step: 1) { editing in
                    guard !editing else { return }
                    manager.lowBatteryCutoff = Int(batteryReserve.rounded())
                    manager.savePreferences()
                }
                LabeledContent("Battery reserve") {
                    Text("\(Int(batteryReserve))%")
                        .monospacedDigit()
                }
            }

            SwiftUI.Section("Closed lid") {
                settingToggle(
                    "Require external power for closed-lid mode",
                    "Release closed-lid protection if the Mac switches to battery.",
                    icon: "powerplug",
                    value: power.requireExternalPowerForClosedLid
                ) { power.setRequireExternalPowerForClosedLid($0) }

                LabeledContent("Authorization") {
                    Text(manager.authorizationStatusText)
                        .foregroundStyle(.secondary)
                }

                if manager.authorizationInstalled {
                    Button("Remove Closed-Lid Authorization", role: .destructive) {
                        Task { await manager.removeClosedLidAuthorization() }
                    }
                } else {
                    Button("Install Closed-Lid Authorization") {
                        Task { await manager.installClosedLidAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            SwiftUI.Section {
                Label("Closed-lid workloads can generate significant heat. Keep the MacBook on a hard, ventilated surface — never in a bag, sleeve, drawer, or other enclosed space.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        SwiftUI.Form {
            SwiftUI.Section("System appearance") {
                LabeledContent("Appearance") {
                    Text("Follows macOS")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Liquid Glass") {
                    Text(nativeGlassStatus)
                        .foregroundStyle(.secondary)
                }
            }

            SwiftUI.Section {
                Text("On macOS 26 and later, MacVigil uses Apple's native Liquid Glass APIs for navigation and important interactive controls. Content areas use standard system materials, matching Apple's guidance instead of applying glass to every surface. Earlier macOS releases use standard materials and controls as a compatibility fallback.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        SwiftUI.Form {
            SwiftUI.Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacVigil")
                            .font(.title2.weight(.semibold))
                        Text("Version \(updater.currentVersion)")
                            .foregroundStyle(.secondary)
                        Text("Local work, uninterrupted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            SwiftUI.Section("Project") {
                Link("GitHub repository", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil")!)
                Link("Latest releases", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/releases")!)
                Text("MacVigil is currently distributed with ad-hoc signing rather than Developer ID notarization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var subtitle: String {
        switch currentSection {
        case .general: return "The settings you use most often."
        case .vigil: return "Fine-grained protection controls and safe live changes."
        case .jobGuard: return "Protect multiple jobs until the final selected job finishes."
        case .statistics: return "Recent local session, battery, thermal, and mode summaries."
        case .hotkeys: return "Control Vigil without opening the menu first."
        case .updates: return "Background update discovery and installation."
        case .power: return "Battery, thermal, and closed-lid safety."
        case .appearance: return "Native macOS presentation and adaptive Liquid Glass."
        case .about: return "Version and project information."
        }
    }

    private var nativeGlassStatus: String {
        if #available(macOS 26.0, *) {
            return "Native system Liquid Glass"
        }
        return "Standard material compatibility mode"
    }

    private var updateStatus: String {
        if let version = updater.availableVersion { return "Version \(version) is available." }
        if let status = updater.statusText { return status }
        if let date = updater.lastCheckAt { return "Last checked \(date.formatted(date: .omitted, time: .shortened))." }
        return "Automatic checks do not require opening the menu-bar panel."
    }

    private func settingToggle(
        _ title: String,
        _ detail: String,
        icon: String,
        value: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .padding(.vertical, 3)
    }

    private func optionToggle(_ title: String, _ detail: String, _ option: VigilOption) -> some View {
        Toggle(isOn: Binding(
            get: { optionValue(option) },
            set: { enabled in
                Task { _ = await manager.changeOptionLive(option, to: enabled) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .padding(.vertical, 3)
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
