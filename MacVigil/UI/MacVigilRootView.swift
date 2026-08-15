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
                        Text("\(jobs.activeJobCount) job\(jobs.activeJobCount == 1 ? "" : "s") · \(jobs.elapsedText)")
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

            if jobs.isWatching && jobs.hasLogs {
                Button { jobs.openLog() } label: { Image(systemName: "doc.text") }
                    .buttonStyle(.borderless)
                    .help("Open a Job Guard log")
            }

            if jobs.isWatching {
                Button { jobs.detachAll() } label: { Image(systemName: "link.badge.minus") }
                    .buttonStyle(.borderless)
                    .help("Detach all jobs; leave Vigil running")
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

            Button(jobs.isWatching ? "Manage" : (jobs.detectedWorkloadCount > 0 ? "Review" : "Choose Jobs")) {
                openJobGuard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Job Guard")
        }
    }

    private var jobGuardSubtitle: String {
        if jobs.isWatching { return jobs.displayStatus }
        if let lastResult = jobs.lastResult { return lastResult }
        if jobs.detectedWorkloadCount > 0 { return jobs.detectionSummary }
        return "Protect processes, commands, or listening ports until all finish."
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
        case port
        case command
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if jobs.isWatching {
                    activeJobsCard
                }

                detectedWorkloadsCard
                portWatcherCard
                processPickerCard
                runCommandCard

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
                    Text("Job Guard owns the session lifetime. Add processes, commands, and TCP ports to the same session and change protection modes at any time. Vigil releases only when the final protected item finishes naturally. Detaching never kills a process or command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 660)
        .frame(minHeight: 760)
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
                Text("Protect the work until all selected work is done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("JOB GUARD ACTIVE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(jobs.activeJobCount == 1 ? "1 protected item" : "\(jobs.activeJobCount) protected items")
                        .font(.headline)
                    Text("Vigil releases after the last running item finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14))
                        .foregroundStyle(Color.green)
                        .clipShape(Capsule())
                    Text(jobs.elapsedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            let running = jobs.protectedJobs.filter { $0.state == .running }
            let completed = jobs.protectedJobs.filter { $0.state != .running }

            if !running.isEmpty {
                Text("RUNNING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 5) {
                    ForEach(running) { job in
                        protectedJobRow(job)
                    }
                }
            }

            if !completed.isEmpty {
                Text("RECENT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                VStack(spacing: 5) {
                    ForEach(completed.suffix(6)) { job in
                        protectedJobRow(job)
                    }
                }
            }

            HStack {
                Text("Add more processes, commands, or ports below while this session is active.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Detach All") { jobs.detachAll() }
                    .buttonStyle(.bordered)
                    .help("Stop monitoring all jobs without killing them or stopping Vigil")
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

    private func protectedJobRow(_ job: JobAwareController.ProtectedJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.state == .running ? job.kind.systemImage : job.state.systemImage)
                .foregroundStyle(job.state == .running ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.subheadline.weight(job.state == .running ? .semibold : .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let port = job.port {
                        Text("TCP \(port)").monospacedDigit()
                        if job.pid > 0 {
                            Text("•")
                            Text("PID \(job.pid)").monospacedDigit()
                        }
                    } else {
                        Text("PID \(job.pid)").monospacedDigit()
                    }
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

            Spacer()

            Text(job.state.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(job.state == .running ? Color.green : Color.secondary)

            if job.logURL != nil {
                Button { jobs.openLog(for: job) } label: { Image(systemName: "doc.text") }
                    .buttonStyle(.borderless)
                    .help("Open this job's log")
            }

            if job.state == .running {
                Button("Detach") { jobs.detachJob(job.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Detach this item without terminating its workload")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(job.state == .running ? 0.035 : 0.018))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var detectedWorkloadsCard: some View {
        let suggestions = Array(jobs.suggestedProcesses.prefix(6))

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(jobs.isWatching ? "Add suggested workloads" : "Suggested workloads", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if jobs.protectableWorkloadCount > 0 {
                    Button("Protect Suggested (\(min(12, jobs.protectableWorkloadCount)))") {
                        Task { await jobs.protectSuggestedWorkloads() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Text(jobs.detectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Nothing obvious to protect right now. You can still choose any process or port below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text(jobs.isWatching
                     ? "Add any of these workloads to the current Job Guard session, or protect all detected workloads at once."
                     : "MacVigil only suggests likely local workloads. You remain in control of what is protected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 3) {
                    ForEach(suggestions) { process in
                        suggestedProcessRow(process)
                    }
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
        processButton(process, prominent: true)
    }

    private var portWatcherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(jobs.isWatching ? "Add a listening port" : "Protect a local server", systemImage: "network")
                    .font(.headline)
                Spacer()
                if jobs.activePortCount > 0 {
                    Text("\(jobs.activePortCount) watched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Keep Vigil active while a TCP service is listening. Useful for dev servers such as ports 3000, 5173, 8000, or 8080. The port watcher releases when the listener disappears.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Port, for example 3000", text: $jobs.portText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .port)
                    .onSubmit {
                        guard !jobs.portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Task { await jobs.watchPort() }
                    }
                Button(jobs.isWatching ? "Add Port" : "Watch Port") {
                    Task { await jobs.watchPort() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobs.portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var processPickerCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(jobs.isWatching ? "Add running processes" : "All running processes", systemImage: "list.bullet.rectangle")
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

            Text("Select as many processes as needed. Finishing one does not release Vigil while another protected item is still running.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by app, workload type, process, or PID", text: $jobs.processSearchText)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)
                if !jobs.processSearchText.isEmpty {
                    Button { jobs.processSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
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
                        processButton(process, prominent: false)
                    }

                    if jobs.filteredProcesses.isEmpty && !jobs.isRefreshingProcesses {
                        Text("No matching processes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                    Button(jobs.isWatching ? "Add PID" : "Watch PID") {
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

    private func processButton(_ process: JobAwareController.ProcessCandidate, prominent: Bool) -> some View {
        let alreadyProtected = jobs.isProtected(pid: process.pid)

        return Button {
            Task { await jobs.watchProcess(process) }
        } label: {
            HStack(spacing: 10) {
                processIcon(process)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(process.name)
                            .font(.subheadline.weight(prominent ? .semibold : .medium))
                            .lineLimit(1)
                        if let kind = process.workloadKind {
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

                Spacer()

                if alreadyProtected {
                    Label("Protected", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green)
                } else {
                    Text(jobs.isWatching ? "Add" : "Protect")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, prominent ? 7 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProcessRowButtonStyle())
        .disabled(alreadyProtected)
        .help(alreadyProtected ? "Already protected" : "Keep Vigil active until this process exits")
    }

    private func processIcon(_ process: JobAwareController.ProcessCandidate) -> some View {
        Group {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().scaledToFit()
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
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            Text("Run a non-interactive shell command in the project folder you choose. Each command gets its own log. Add multiple commands and Vigil remains active until the last protected item finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(URL(fileURLWithPath: jobs.workingDirectoryPath).lastPathComponent.isEmpty ? jobs.workingDirectoryPath : URL(fileURLWithPath: jobs.workingDirectoryPath).lastPathComponent,
                      systemImage: "folder")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(jobs.workingDirectoryPath)
                Spacer()
                Button("Choose Folder…") { jobs.chooseWorkingDirectory() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Home") { jobs.resetWorkingDirectory() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

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
                Button(jobs.isWatching ? "Add Command" : "Run with Vigil") {
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
                Text("Last Job Guard session")
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let duration = jobs.lastDurationText {
                    Text("Protected for \(duration)")
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
