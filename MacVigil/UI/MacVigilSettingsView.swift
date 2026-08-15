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
        case cli = "CLI"
        case updates = "Updates"
        case power = "Power & Safety"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .vigil: return "bolt.shield"
            case .jobGuard: return "briefcase"
            case .statistics: return "chart.bar.xaxis"
            case .hotkeys: return "keyboard"
            case .cli: return "terminal"
            case .updates: return "arrow.triangle.2.circlepath"
            case .power: return "battery.100percent.bolt"
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
        .onDisappear {
            hotkeys.cancelRecording()
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("MacVigil")
        .navigationSplitViewColumnWidth(min: 195, ideal: 220, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusFooter
        }
    }

    private var statusFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isActive ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(manager.isActive ? "Vigil active" : "Vigil idle")
                        .font(.caption.weight(.semibold))
                    Text(manager.isActive ? manager.configurationName : "Normal sleep behavior")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if hotkeys.enabled {
                    Text(spacedShortcutKeys(hotkeys.startStopKeys))
                        .font(.caption2.monospaced().weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    toggleVigil()
                } label: {
                    Image(systemName: manager.isActive ? "stop.fill" : "play.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(manager.isActive ? Color.red : Color.accentColor)
                .help(manager.isActive ? "Stop Vigil" : "Start Vigil")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private var detail: some View {
        selectedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(currentSection.rawValue)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch currentSection {
        case .general: general
        case .vigil: vigil
        case .jobGuard: jobGuard
        case .statistics:
            ScrollView {
                StatisticsDashboardView(manager: manager, power: power, showsHeader: false)
                    .padding(18)
            }
            .scrollIndicators(.visible)
        case .hotkeys: hotkeySettings
        case .cli: cliGuide
        case .updates: updates
        case .power: powerSafety
        case .about: about
        }
    }

    private var general: some View {
        settingsForm {
            SwiftUI.Section("Vigil now") {
                LabeledContent("Status") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(manager.isActive ? "Active" : "Idle")
                            .fontWeight(.semibold)
                            .foregroundStyle(manager.isActive ? Color.green : Color.secondary)
                        if manager.isActive {
                            Text("\(manager.configurationName) · \(settingsRemainingText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Button {
                    toggleVigil()
                } label: {
                    Label(manager.isActive ? "Stop Vigil" : "Start Vigil", systemImage: manager.isActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(manager.isActive ? .red : .accentColor)
                .help(manager.isActive ? "Stop protection and restore normal macOS sleep behavior" : "Start Vigil with the selected mode and duration")

                if let error = manager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
                HStack(spacing: 8) {
                    settingsModeButton(.computeGuard)
                    settingsModeButton(.closedLidEco)
                    settingsModeButton(.fullAwake)
                }
                .padding(.vertical, 2)
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
                .accessibilityValue(formatDurationWords(Int(durationMinutes.rounded())))

                LabeledContent("Custom duration") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDurationWords(Int(durationMinutes.rounded())))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(formatMinutes(Int(durationMinutes.rounded())))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
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
    }

    private var vigil: some View {
        settingsForm {
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
    }

    private var jobGuard: some View {
        settingsForm {
            SwiftUI.Section("Multi-job protection") {
                LabeledContent("Status") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(jobs.isWatching
                             ? "\(jobs.activeJobCount) protected job\(jobs.activeJobCount == 1 ? "" : "s")"
                             : "Idle")
                            .fontWeight(.semibold)
                            .foregroundStyle(jobs.isWatching ? Color.green : Color.secondary)
                        if jobs.isWatching {
                            Text(jobs.displayStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Text("Job Guard keeps one Vigil session alive while any selected process, port, or command is still running. Protection releases only after the final protected item finishes naturally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                settingsActionButton(jobs.isWatching ? "Manage Protected Work" : "Open Job Guard", prominent: true) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "job-guard")
                }
            }

            SwiftUI.Section("What Job Guard can protect") {
                Label("Running processes and PIDs", systemImage: "gearshape.2")
                Label("Local TCP listeners such as ports 3000, 5173, 8000, or 11434", systemImage: "network")
                Label("Commands launched from a selected project directory", systemImage: "terminal")
                Label("Suggested local AI, build, server, container, and transfer workloads", systemImage: "sparkles")
            }

            SwiftUI.Section("Session ownership") {
                Text("Changing modes or individual protection options changes only the power profile. Job Guard remains attached and continues to own when the session ends. Detaching a job never kills the process.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeySettings: some View {
        settingsForm {
            SwiftUI.Section {
                settingToggle(
                    "Enable global hotkeys",
                    "Hotkeys work even when the MacVigil menu is closed.",
                    icon: "keyboard",
                    value: hotkeys.enabled
                ) { hotkeys.setEnabled($0) }
            }

            SwiftUI.Section("Shortcuts") {
                ForEach(hotkeys.shortcuts) { shortcut in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                                .font(.body)
                            Text(shortcut.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if hotkeys.recordingID == shortcut.id {
                            Text("Press shortcut…")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text(spacedShortcutKeys(shortcut.keys))
                                .font(.body.monospaced().weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        Button(hotkeys.recordingID == shortcut.id ? "Cancel" : "Change") {
                            if hotkeys.recordingID == shortcut.id {
                                hotkeys.cancelRecording()
                            } else {
                                hotkeys.beginRecording(id: shortcut.id)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button {
                            hotkeys.resetShortcut(id: shortcut.id)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset this shortcut")
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Text("Click Change, then press the new key combination. MacVigil rejects duplicate shortcuts and reports system registration conflicts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All") { hotkeys.resetAllShortcuts() }
                        .buttonStyle(.bordered)
                }
            }

            if let status = hotkeys.lastActionText {
                SwiftUI.Section("Status") {
                    Label(status, systemImage: hotkeys.recordingID == nil ? "info.circle" : "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SwiftUI.Section {
                Text("Closed-Lid Eco safety and authorization rules still apply when a hotkey is used. Mode hotkeys change the profile underneath the current session without detaching Job Guard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { hotkeys.cancelRecording() }
    }

    private var cliGuide: some View {
        settingsForm {
            SwiftUI.Section("Install the command") {
                Label("Move MacVigil.app to /Applications first, then use the CLI menu in this Settings window toolbar and choose Install macvigil CLI.", systemImage: "terminal")
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Installed command") {
                    Text("/usr/local/bin/macvigil")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }

                Text("The command is a symbolic link to the universal helper inside MacVigil.app. Administrator approval is requested only to create or remove that link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SwiftUI.Section("Everyday commands") {
                cliCommandRow("Check status", "macvigil status")
                cliCommandRow("Machine-readable status", "macvigil status --json")
                cliCommandRow("Start Compute Guard for two hours", "macvigil start --mode compute --duration 2h")
                cliCommandRow("Change mode live", "macvigil mode full-awake")
                cliCommandRow("Stop protection", "macvigil stop")
            }

            SwiftUI.Section("Protect terminal work") {
                cliCommandRow("Run and protect a command", "macvigil run -- npm test")
                cliCommandRow("Use a project directory", "macvigil run --cwd ~/Projects/app -- npm run build")
                cliCommandRow("Watch a PID", "macvigil watch-pid 43127")
                cliCommandRow("Watch local ports", "macvigil watch-port 3000 5173")
                cliCommandRow("Protect detected workloads", "macvigil protect-suggested")
            }

            SwiftUI.Section("Saved workflow example") {
                Text("""
                macvigil workflow save local-stack \\
                  --port 3000 \\
                  --port 11434 \\
                  --command "npm run dev" \\
                  --cwd ~/Projects/app

                macvigil workflow run local-stack
                """)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(.vertical, 4)

                Button("Copy example") {
                    copyCLICommand("macvigil workflow save local-stack --port 3000 --port 11434 --command \"npm run dev\" --cwd ~/Projects/app\nmacvigil workflow run local-stack")
                }
                .buttonStyle(.bordered)
            }

            SwiftUI.Section("How CLI control works") {
                Text("The CLI talks only to the local running MacVigil app and joins the same Vigil session and Job Guard collection as the GUI. It does not start a second power-management runtime and it does not expose an HTTP or TCP control server.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Closed-Lid Eco authorization, battery reserve, thermal safety, and the first-use ventilation acknowledgement still apply to CLI-started protection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updates: some View {
        settingsForm {
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
                    settingsActionButton(updater.isChecking ? "Checking…" : "Check Now") {
                        Task { await updater.checkForUpdates(userInitiated: true) }
                    }
                    .disabled(updater.isChecking || updater.isInstalling)

                    if updater.hasUpdate {
                        settingsActionButton(updater.isInstalling ? "Updating…" : "Update Now", prominent: true) {
                            if manager.isActive {
                                openWindow(id: "update-confirmation")
                            } else {
                                Task { await updater.installAvailableUpdate() }
                            }
                        }
                        .disabled(updater.isInstalling)
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var powerSafety: some View {
        settingsForm {
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
                    .controlSize(.large)
                } else {
                    settingsActionButton("Install Closed-Lid Authorization", prominent: true) {
                        Task { await manager.installClosedLidAuthorization() }
                    }
                }
            }

            SwiftUI.Section {
                Label("Closed-lid workloads can generate significant heat. Keep the MacBook on a hard, ventilated surface — never in a bag, sleeve, drawer, or other enclosed space.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var about: some View {
        settingsForm {
            SwiftUI.Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MacVigil")
                            .font(.title2.weight(.semibold))
                        Text("Version \(updater.currentVersion)")
                            .foregroundStyle(.secondary)
                        Text("Local work, uninterrupted.")
                            .font(.headline)
                        Text("Keep your work running. Not your screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            SwiftUI.Section("What MacVigil is for") {
                Text("MacVigil is an energy-aware runtime continuity utility for long-running local work: AI coding agents, local models, builds and tests, development servers, transfers, rendering, research, backups, and remote Mac workflows.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("A Vigil session has one lifetime owner—such as a timer or Job Guard—while its protection mode can change independently underneath it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SwiftUI.Section("Privacy & local data") {
                Label("No statistics telemetry is uploaded. Session history, saved workflows, preferences, and hotkeys stay local on this Mac.", systemImage: "hand.raised.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Text("GitHub is contacted only for update checks and release downloads when those features are enabled or requested.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SwiftUI.Section("Safety & distribution") {
                Text("Closed-lid protection is experimental and can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid work in a bag, sleeve, drawer, or other enclosed space.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Brightness 0 is not a guarantee that the physical display panel is electrically powered off. Mandatory macOS battery, thermal, shutdown, and Lock Screen behavior remains in control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("MacVigil is currently distributed with ad-hoc signing rather than Developer ID signing and notarization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Project") {
                Link("GitHub repository", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil")!)
                Link("Latest releases", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/releases")!)
                Link("Report an issue", destination: URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/issues")!)
            }
        }
    }

    private var updateStatus: String {
        if let version = updater.availableVersion { return "Version \(version) is available." }
        if let status = updater.statusText { return status }
        if let date = updater.lastCheckAt { return "Last checked \(date.formatted(date: .omitted, time: .shortened))." }
        return "Automatic checks do not require opening the menu-bar panel."
    }

    private var settingsRemainingText: String {
        guard let remaining = manager.effectiveRemainingSeconds else { return "No timer" }
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        return "\(minutes)m left"
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        SwiftUI.Form {
            content()
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func settingsActionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private func settingsModeButton(_ profile: RuntimeProfile) -> some View {
        let button = Button {
            Task { _ = await manager.changeModeLive(profile) }
        } label: {
            Label(profile.title, systemImage: modeIcon(profile))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .controlSize(.large)

        if matches(profile) {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func modeIcon(_ profile: RuntimeProfile) -> String {
        switch profile {
        case .computeGuard: return "cpu"
        case .closedLidEco: return "leaf"
        case .fullAwake: return "sun.max"
        }
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

    @ViewBuilder
    private func durationButton(_ title: String, _ duration: SessionDuration, _ custom: Int? = nil) -> some View {
        let selected = duration == .custom && custom != nil
            ? manager.selectedDuration == .custom && manager.customMinutes == custom
            : manager.selectedDuration == duration

        let button = Button(title) {
            if let custom { durationMinutes = Double(custom) }
            Task { _ = await manager.changeDurationLive(duration, customMinutes: custom) }
        }
        .frame(maxWidth: .infinity)
        .controlSize(.regular)
        .disabled(manager.isActive && manager.sessionOwner?.controlsLifetime == true)

        if selected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func cliCommandRow(_ title: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copyCLICommand(command)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command")
            }
        }
        .padding(.vertical, 3)
    }

    private func copyCLICommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func toggleVigil() {
        Task {
            if manager.isActive {
                await manager.stopLiveSession()
            } else {
                await manager.startFreshSession()
            }
        }
    }

    private func spacedShortcutKeys(_ raw: String) -> String {
        let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isWhitespace {
                index = trimmed.index(after: index)
                continue
            }
            guard modifierSymbols.contains(character) else { break }
            parts.append(String(character))
            index = trimmed.index(after: index)
        }

        if index < trimmed.endIndex {
            let key = String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { parts.append(key) }
        }

        return parts.isEmpty ? raw : parts.joined(separator: " ")
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
}
