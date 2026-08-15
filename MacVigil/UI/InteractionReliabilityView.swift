import SwiftUI
import AppKit

struct MacVigilInteractiveRootView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController

    var body: some View {
        VStack(spacing: 0) {
            MacVigilRootView(manager: manager, updater: updater, jobs: jobs)
            Divider()
            PowerIntelligenceBar(power: power)
                .background(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if manager.isActive || updater.hasUpdate {
                VStack(spacing: 0) {
                    Divider()
                    ReliableCriticalActions(manager: manager, updater: updater)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                }
            }
        }
    }
}

struct ReliableCriticalActions: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager

    @Environment(\.openWindow) private var openWindow
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 8) {
            if manager.isActive {
                Button {
                    stopVigil()
                } label: {
                    Label(isStopping ? "Stopping Vigil…" : "Stop Vigil", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(isStopping || updater.isInstalling)
                .help("Stop Vigil and restore normal macOS sleep behavior. Protected jobs are not terminated.")
                .keyboardShortcut(".", modifiers: [.command])
            }

            if updater.hasUpdate {
                Button {
                    requestUpdate()
                } label: {
                    Label(updateButtonTitle, systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(updater.isInstalling || isStopping)
                .help(manager.isActive
                      ? "Open a normal window to stop Vigil and install the update"
                      : "Download, verify, install, and restart MacVigil")
            }
        }
    }

    private var updateButtonTitle: String {
        if updater.isInstalling { return "Updating…" }
        if let version = updater.availableVersion { return "Update to \(version)" }
        return "Update Now"
    }

    private func stopVigil() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await manager.stopLiveSession()
            isStopping = false
        }
    }

    private func requestUpdate() {
        if manager.isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "update-confirmation")
        } else {
            Task { await updater.installAvailableUpdate() }
        }
    }
}

struct ReliableJobGuardWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var showManualPID = false

    private enum Field: Hashable {
        case search
        case pid
        case command
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if manager.isActive || updater.hasUpdate {
                    criticalActionsCard
                }

                if jobs.isWatching {
                    activeJobsCard
                }

                suggestedWorkloadsCard
                processPickerCard
                commandCard
                feedback

                if !jobs.isWatching, let last = jobs.lastResult {
                    lastJobCard(last)
                }

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Job Guard owns the session lifetime. Add or detach jobs independently; Vigil releases only when the final protected job finishes naturally. Detaching or stopping Vigil never terminates the underlying jobs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 650)
        .frame(minHeight: 740)
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
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var criticalActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vigil controls")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ReliableCriticalActions(manager: manager, updater: updater)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("JOB GUARD ACTIVE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(jobs.activeJobCount == 1 ? "1 protected job" : "\(jobs.activeJobCount) protected jobs")
                        .font(.headline)
                    Text("Vigil releases after the last running job finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
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

            VStack(spacing: 6) {
                ForEach(jobs.protectedJobs) { job in
                    protectedJobRow(job)
                }
            }

            HStack {
                Text("Add more work below while this session is active.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Detach All") { jobs.detachAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!jobs.isWatching)
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
                .frame(width: 22)

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

            VStack(alignment: .trailing, spacing: 6) {
                Text(job.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(job.state == .running ? Color.green : Color.secondary)

                HStack(spacing: 6) {
                    if job.logURL != nil {
                        Button("Log") { jobs.openLog(for: job) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                    }
                    if job.state == .running {
                        Button("Detach") { jobs.detachJob(job.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.orange)
                            .fixedSize()
                            .help("Detach only this job. The process keeps running.")
                    }
                }
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(job.state == .running ? 0.045 : 0.020))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var suggestedWorkloadsCard: some View {
        let suggestions = Array(jobs.suggestedProcesses.prefix(6))
        VStack(alignment: .leading, spacing: 10) {
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
                    .padding(.vertical, 4)
            } else {
                Text(jobs.isWatching
                     ? "Choose another workload to add it to the same Job Guard session."
                     : "Suggestions are local and opt-in. Add only the work you want MacVigil to protect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(suggestions) { process in
                        processRow(process, showCategory: true)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 3) {
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
                HStack(spacing: 8) {
                    TextField("PID, for example 43127", text: $jobs.pidText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .pid)
                        .onSubmit { addManualPID() }
                    Button("Add PID") { addManualPID() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 8)
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
                Button("Protected") { }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                    .fixedSize()
            } else {
                Button("Add") {
                    Task { await jobs.watchProcess(process) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    private var commandCard: some View {
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
                    .fixedSize()
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
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var feedback: some View {
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

    private func addManualPID() {
        guard !jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.watchPID() }
    }

    private func runCommand() {
        guard !jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await jobs.runCommand() }
    }
}

struct UpdateConfirmationWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Update MacVigil")
                        .font(.title2.weight(.semibold))
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if manager.isActive {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Vigil is currently active", systemImage: "bolt.shield.fill")
                        .font(.headline)
                    Text("Installing an update restarts MacVigil. The current Vigil session must stop first, so normal macOS sleep behavior is restored before the app is replaced.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(manager.configurationName)
                        Spacer()
                        Text(remainingText).monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .padding(.top, 3)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let error = localError ?? updater.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working || updater.isInstalling)

            HStack(spacing: 10) {
                Button("View Release") { updater.openReleasePage() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button(manager.isActive ? "Keep Vigil Running" : "Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 470, height: manager.isActive ? 350 : 280)
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
