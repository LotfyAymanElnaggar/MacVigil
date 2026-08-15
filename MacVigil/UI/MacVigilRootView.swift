import SwiftUI
import AppKit

struct MacVigilRootView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            PolishedMenuBarView(manager: manager, updater: updater)

            Divider()

            jobGuardBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .frame(width: 448, height: 782)
        .onChange(of: manager.isActive) { active in
            if !active {
                jobs.handleVigilStoppedExternally()
                updater.vigilDidBecomeInactive()
            }
        }
    }

    private var jobGuardBar: some View {
        HStack(spacing: 9) {
            Image(systemName: jobs.isWatching ? "briefcase.fill" : (jobs.detectedWorkloadCount > 0 ? "sparkles" : "briefcase"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(jobs.isWatching || jobs.detectedWorkloadCount > 0 ? Color.accentColor : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(jobs.isWatching ? "Job Guard active" : "Job Guard")
                        .font(.caption.weight(.semibold))
                    if jobs.isWatching {
                        Text(jobs.elapsedText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if jobs.detectedWorkloadCount > 0 {
                        Text("\(jobs.detectedWorkloadCount) suggested")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(jobGuardSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if jobs.isWatching, jobs.logURL != nil {
                Button {
                    jobs.openLog()
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open Job Guard log")
            }

            if jobs.isWatching {
                Button {
                    jobs.detach()
                } label: {
                    Image(systemName: "link.badge.minus")
                }
                .buttonStyle(.borderless)
                .help("Stop watching this job; leave Vigil running")
            }

            Menu {
                Toggle("Launch MacVigil at Login", isOn: launchAtLoginBinding)

                Divider()

                Button(updater.isChecking ? "Checking for Updates…" : "Check for Updates") {
                    Task { await updater.checkForUpdates(userInitiated: true) }
                }
                .disabled(updater.isChecking || updater.isInstalling)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("MacVigil options")

            Button(jobs.isWatching ? "Manage" : (jobs.detectedWorkloadCount > 0 ? "Review" : "Choose Job")) {
                openJobGuard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Job Guard")
        }
        .contentShape(Rectangle())
        .onTapGesture { openJobGuard() }
    }

    private var jobGuardSubtitle: String {
        if jobs.isWatching { return jobs.displayStatus }
        if let lastResult = jobs.lastResult { return lastResult }
        if jobs.detectedWorkloadCount > 0 { return jobs.detectionSummary }
        return "Protect a running process or command until it finishes."
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { updater.launchAtLoginEnabled },
            set: { updater.setLaunchAtLogin($0) }
        )
    }

    private func openJobGuard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "job-guard")
    }
}

struct JobGuardWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var showManualPID = false
    @State private var hoveringCommand = false

    private enum Field: Hashable {
        case search
        case pid
        case command
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if jobs.isWatching {
                    activeJobCard
                } else {
                    detectedWorkloadsCard
                    processPickerCard
                    runCommandCard
                }

                if let error = jobs.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let status = jobs.statusText {
                    Label(status, systemImage: jobs.isWatching ? "bolt.shield.fill" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !jobs.isWatching, let last = jobs.lastResult {
                    lastJobCard(last)
                }

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Suggestions are detected locally from running processes and are never protected automatically. Job Guard keeps Vigil active only after you choose a process or command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 580)
        .frame(minHeight: 680)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task { await jobs.refreshProcesses() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Label("Job Guard", systemImage: "briefcase.fill")
                    .font(.title3.weight(.semibold))
                Text("Protect the work until the work is done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var activeJobCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROTECTING NOW")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(jobs.displayStatus)
                        .font(.headline)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("ACTIVE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14))
                    .foregroundStyle(Color.green)
                    .clipShape(Capsule())
            }

            Divider()

            HStack {
                Label(jobs.elapsedText, systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                Spacer()
                if let pid = jobs.watchedPID {
                    Text("PID \(pid)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if jobs.logURL != nil {
                    Button("Open Log") { jobs.openLog() }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Button("Detach Job Guard") {
                    jobs.detach()
                }
                .buttonStyle(.bordered)
                .help("Stop watching this job but leave the current Vigil session running")
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var detectedWorkloadsCard: some View {
        let suggestions = Array(jobs.suggestedProcesses.prefix(6))

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Suggested workloads", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(jobs.detectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if suggestions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Nothing obvious to protect right now. You can still choose any process below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("MacVigil recognized these as likely long-running local-development workloads. Review and choose one to protect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 3) {
                    ForEach(suggestions) { process in
                        suggestedProcessRow(process)
                    }
                }

                if jobs.suggestedProcesses.count > suggestions.count {
                    Text("+ \(jobs.suggestedProcesses.count - suggestions.count) more detected below")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(suggestions.isEmpty ? 0.035 : 0.07))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(suggestions.isEmpty ? 0.14 : 0.26), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func suggestedProcessRow(_ process: JobAwareController.ProcessCandidate) -> some View {
        Button {
            Task { await jobs.watchProcess(process) }
        } label: {
            HStack(spacing: 10) {
                processIcon(process)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let kind = process.workloadKind {
                            Label(kind.title, systemImage: kind.systemImage)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("PID \(process.pid)")
                            .monospacedDigit()
                        if !process.cpuText.isEmpty {
                            Text("•")
                            Text("CPU \(process.cpuText)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Protect")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProcessRowButtonStyle())
        .help("Keep Vigil active until \(process.name) exits")
    }

    private var processPickerCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("All running processes", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await jobs.refreshProcesses() }
                } label: {
                    Label(jobs.isRefreshingProcesses ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(jobs.isRefreshingProcesses)
            }

            Text("Pick any app or process. MacVigil releases protection automatically when it exits.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by app, workload type, process, or PID", text: $jobs.processSearchText)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)
                if !jobs.processSearchText.isEmpty {
                    Button {
                        jobs.processSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(jobs.filteredProcesses.prefix(80))) { process in
                        processRow(process)
                    }

                    if jobs.filteredProcesses.isEmpty && !jobs.isRefreshingProcesses {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text("No matching processes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                }
            }
            .frame(height: 220)

            DisclosureGroup(isExpanded: $showManualPID) {
                HStack(spacing: 8) {
                    TextField("PID, for example 43127", text: $jobs.pidText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .pid)
                        .onSubmit {
                            guard !jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            Task { await jobs.watchPID() }
                        }

                    Button("Watch PID") {
                        Task { await jobs.watchPID() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 7)
            } label: {
                Text("Enter a PID manually")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func processRow(_ process: JobAwareController.ProcessCandidate) -> some View {
        Button {
            Task { await jobs.watchProcess(process) }
        } label: {
            HStack(spacing: 10) {
                processIcon(process)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let kind = process.workloadKind {
                            Text(kind.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("PID \(process.pid)")
                            .monospacedDigit()
                        if !process.cpuText.isEmpty {
                            Text("•")
                            Text("CPU \(process.cpuText)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: process.workloadKind == nil ? "shield.lefthalf.filled" : "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProcessRowButtonStyle())
        .help("Keep Vigil active until \(process.name) exits")
    }

    private func processIcon(_ process: JobAwareController.ProcessCandidate) -> some View {
        Group {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else if let kind = process.workloadKind {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var runCommandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Run a command", systemImage: "terminal")
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
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            Text("Run a non-interactive shell command from your home directory. Output is captured to a log and Vigil ends when the command exits.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("npm test  ·  python train.py  ·  make build", text: $jobs.commandText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .command)
                .onSubmit {
                    guard !jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await jobs.runCommand() }
                }

            HStack {
                Text("Runs with /bin/zsh -lc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Run with Vigil") {
                    Task { await jobs.runCommand() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(hoveringCommand ? 0.05 : 0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(hoveringCommand ? 0.35 : 0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hoveringCommand = value }
        }
    }

    private func lastJobCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: jobs.lastExitCode == nil || jobs.lastExitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(jobs.lastExitCode == nil || jobs.lastExitCode == 0 ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last job")
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let duration = jobs.lastDurationText {
                    Text("Ran for \(duration)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ProcessRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.13 : 0.001))
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
