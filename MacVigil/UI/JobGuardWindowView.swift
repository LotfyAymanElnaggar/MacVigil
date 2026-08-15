import SwiftUI
import AppKit

struct ImprovedJobGuardWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var showManualPID = false

    private enum Field: Hashable {
        case search
        case pid
        case port
        case command
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if manager.isActive || updater.hasUpdate {
                        GroupBox("Vigil controls") {
                            ReliableCriticalActions(manager: manager, updater: updater)
                                .padding(.top, 4)
                        }
                    }

                    if jobs.isWatching {
                        activeJobsSection
                    }

                    suggestedSection
                    processSection
                    manualProtectionSection
                    commandSection
                    feedbackSection

                    if !jobs.isWatching, let last = jobs.lastResult {
                        lastSessionSection(last)
                    }

                    Label(
                        "Job Guard owns the session lifetime. Vigil releases only when the final protected process, port, or command finishes naturally. Detach never terminates the underlying workload.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
        }
        .frame(width: 760, height: 780)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task { await jobs.refreshProcesses() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Job Guard")
                    .font(.title2.weight(.semibold))
                Text("Protect processes, local ports, and commands until all selected work is done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if jobs.isWatching {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(jobs.activeJobCount) protected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(jobs.elapsedText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var activeJobsSection: some View {
        GroupBox("Protected work") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(jobs.displayStatus, systemImage: "bolt.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Detach All") { jobs.detachAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Stop monitoring all protected items without killing them")
                }

                Divider()

                ForEach(jobs.activeJobs) { job in
                    protectedJobRow(job)
                    if job.id != jobs.activeJobs.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func protectedJobRow(_ job: JobAwareController.ProtectedJob) -> some View {
        HStack(spacing: 11) {
            Image(systemName: job.kind.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let port = job.port {
                    Text("TCP \(port) · listener PID \(job.pid) · \(jobs.elapsedText(for: job))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("PID \(job.pid) · \(jobs.elapsedText(for: job))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if job.logURL != nil {
                Button("Log") { jobs.openLog(for: job) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button("Detach") { jobs.detachJob(job.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .help("Detach this item without terminating it")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var suggestedSection: some View {
        let suggestions = Array(jobs.unprotectedSuggestedProcesses.prefix(8))

        GroupBox("Suggested workloads") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(jobs.detectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if jobs.protectableWorkloadCount > 0 {
                        Button("Protect Suggested") {
                            Task { await jobs.protectSuggestedWorkloads() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                if suggestions.isEmpty {
                    Text("Nothing obvious to protect right now. Detection is local and heuristic; you can still choose any process, PID, port, or command below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                } else {
                    ForEach(suggestions) { process in
                        processRow(process, showCategory: true)
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var processSection: some View {
        GroupBox("Running processes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by app, process, workload type, or PID", text: $jobs.processSearchText)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .search)
                    if !jobs.processSearchText.isEmpty {
                        Button("Clear") { jobs.processSearchText = "" }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                    Button {
                        Task { await jobs.refreshProcesses() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(jobs.isRefreshingProcesses)
                    .help("Refresh process list")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if jobs.isRefreshingProcesses && jobs.processes.isEmpty {
                    VStack(spacing: 9) {
                        ProgressView()
                        Text("Loading running processes…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else if jobs.filteredProcesses.isEmpty {
                    Text(jobs.processSearchText.isEmpty ? "No processes are available right now." : "No processes match this search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(jobs.filteredProcesses.prefix(100))) { process in
                                processRow(process, showCategory: true)
                            }
                        }
                    }
                    .frame(height: 250)
                }

                DisclosureGroup(isExpanded: $showManualPID) {
                    HStack(spacing: 8) {
                        TextField("PID, for example 43127", text: $jobs.pidText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .pid)
                            .onSubmit { addManualPID() }
                        Button("Add PID") { addManualPID() }
                            .buttonStyle(.borderedProminent)
                            .disabled(jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Enter a PID manually")
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var manualProtectionSection: some View {
        GroupBox("Watch a local TCP port") {
            VStack(alignment: .leading, spacing: 9) {
                Text("Use this for local development servers and runtimes. The port must already have a TCP listener when it is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Port, for example 3000 or 11434", text: $jobs.portText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .port)
                        .onSubmit { addPort() }
                    Button(jobs.isWatching ? "Add Port" : "Protect Port") { addPort() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(jobs.portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commandSection: some View {
        GroupBox(jobs.isWatching ? "Add a command" : "Run a command") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Working directory")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(jobs.workingDirectoryPath)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 10)
                    Button("Choose Folder…") { jobs.chooseWorkingDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Home") { jobs.resetWorkingDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if !jobs.commandHistory.isEmpty {
                    HStack {
                        Text("Commands are non-interactive and run with /bin/zsh -lc. Output is retained in an individual temporary log.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Menu("Recent") {
                            ForEach(jobs.commandHistory, id: \.self) { command in
                                Button(command) { jobs.useCommandFromHistory(command) }
                            }
                            Divider()
                            Button("Clear History", role: .destructive) { jobs.clearCommandHistory() }
                        }
                    }
                } else {
                    Text("Commands are non-interactive and run with /bin/zsh -lc. Output is retained in an individual temporary log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("npm test  ·  python train.py  ·  make build", text: $jobs.commandText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .command)
                    .onSubmit { runCommand() }

                Button {
                    runCommand()
                } label: {
                    Label(jobs.isWatching ? "Add Command to Job Guard" : "Run with Vigil", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
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
    }

    private func lastSessionSection(_ text: String) -> some View {
        GroupBox("Last Job Guard session") {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: jobs.lastExitCode == nil || jobs.lastExitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(jobs.lastExitCode == nil || jobs.lastExitCode == 0 ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
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
            .padding(.top, 4)
        }
    }

    private func processRow(_ process: JobAwareController.ProcessCandidate, showCategory: Bool) -> some View {
        let protected = jobs.isProtected(pid: process.pid)

        return HStack(spacing: 10) {
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

            if protected {
                Label("Protected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Add") {
                    Task { await jobs.watchProcess(process) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .frame(width: 26, height: 26)
    }

    private func addManualPID() {
        guard !jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.watchPID() }
    }

    private func addPort() {
        guard !jobs.portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.watchPort() }
    }

    private func runCommand() {
        guard !jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.runCommand() }
    }
}
