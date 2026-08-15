import Foundation
import AppKit
import Darwin

@MainActor
final class JobAwareController: ObservableObject {
    struct ProcessCandidate: Identifiable {
        let pid: Int32
        let name: String
        let path: String
        let cpuPercent: Double
        let icon: NSImage?
        let isApplication: Bool

        var id: Int32 { pid }
        var cpuText: String {
            guard cpuPercent >= 0.05 else { return "" }
            return String(format: "%.1f%%", cpuPercent)
        }
    }

    @Published var pidText = ""
    @Published var commandText = ""
    @Published var processSearchText = ""

    @Published private(set) var processes: [ProcessCandidate] = []
    @Published private(set) var isRefreshingProcesses = false
    @Published private(set) var commandHistory: [String]

    @Published private(set) var isWatching = false
    @Published private(set) var watchedPID: Int32?
    @Published private(set) var jobTitle: String?
    @Published private(set) var statusText: String?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastError: String?
    @Published private(set) var logURL: URL?
    @Published private(set) var jobStartedAt: Date?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var lastFinishedDuration: Int?

    private let manager: VigilManager
    private var pollTimer: Timer?
    private var launchedProcess: Process?
    private var savedDuration: SessionDuration?
    private var savedCustomMinutes: Int?

    private let commandHistoryKey = "MacVigil.jobs.commandHistory"

    init(manager: VigilManager) {
        self.manager = manager
        commandHistory = UserDefaults.standard.stringArray(forKey: commandHistoryKey) ?? []
    }

    var displayStatus: String {
        guard isWatching else { return lastResult ?? "Not watching a job" }
        if let pid = watchedPID, let title = jobTitle {
            return "\(title) · PID \(pid)"
        }
        return jobTitle ?? "Watching job"
    }

    var elapsedText: String {
        Self.durationText(elapsedSeconds)
    }

    var lastDurationText: String? {
        guard let lastFinishedDuration else { return nil }
        return Self.durationText(lastFinishedDuration)
    }

    var filteredProcesses: [ProcessCandidate] {
        let query = processSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return processes }
        return processes.filter {
            $0.name.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            String($0.pid).contains(query)
        }
    }

    func refreshProcesses() async {
        guard !isRefreshingProcesses else { return }
        isRefreshingProcesses = true
        defer { isRefreshingProcesses = false }

        let runningApps = NSWorkspace.shared.runningApplications
        var appByPID: [Int32: NSRunningApplication] = [:]
        for app in runningApps {
            appByPID[app.processIdentifier] = app
        }

        let result = await ShellRunner.run("/bin/ps", ["-axo", "pid=,pcpu=,comm="])
        var candidates: [ProcessCandidate] = []
        var seen = Set<Int32>()

        if result.succeeded {
            for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                guard fields.count == 3,
                      let pid = Int32(fields[0]),
                      pid > 1,
                      pid != getpid(),
                      !seen.contains(pid) else { continue }

                let cpu = Double(fields[1]) ?? 0
                let path = String(fields[2])
                let app = appByPID[pid]
                let fallbackName = URL(fileURLWithPath: path).lastPathComponent
                let name = app?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = (name?.isEmpty == false ? name! : fallbackName)

                candidates.append(ProcessCandidate(
                    pid: pid,
                    name: resolvedName.isEmpty ? "Process \(pid)" : resolvedName,
                    path: path,
                    cpuPercent: cpu,
                    icon: app?.icon,
                    isApplication: app != nil
                ))
                seen.insert(pid)
            }
        }

        // If ps ever fails, the picker still remains useful for normal apps.
        for app in runningApps where app.processIdentifier > 1 && app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            guard !seen.contains(pid) else { continue }
            let name = app.localizedName ?? app.bundleIdentifier ?? "Process \(pid)"
            candidates.append(ProcessCandidate(
                pid: pid,
                name: name,
                path: app.bundleURL?.path ?? app.executableURL?.path ?? "",
                cpuPercent: 0,
                icon: app.icon,
                isApplication: true
            ))
            seen.insert(pid)
        }

        processes = candidates.sorted { lhs, rhs in
            if lhs.isApplication != rhs.isApplication { return lhs.isApplication && !rhs.isApplication }
            if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.05 { return lhs.cpuPercent > rhs.cpuPercent }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func watchProcess(_ process: ProcessCandidate) async {
        pidText = String(process.pid)
        await beginWatching(pid: process.pid, title: process.name)
    }

    func watchPID() async {
        lastError = nil
        lastResult = nil

        let trimmed = pidText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawPID = Int32(trimmed), rawPID > 1 else {
            lastError = "Enter a valid process ID greater than 1."
            return
        }

        let known = processes.first(where: { $0.pid == rawPID })
        await beginWatching(pid: rawPID, title: known?.name ?? "Process \(rawPID)")
    }

    func runCommand() async {
        lastError = nil
        lastResult = nil
        lastExitCode = nil

        guard !isWatching else {
            lastError = "A Job Guard is already active."
            return
        }

        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            lastError = "Enter a command to run."
            return
        }

        guard await prepareVigilForJob() else { return }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVigilJobs", isDirectory: true)
        let log = workspace.appendingPathComponent("job-\(UUID().uuidString).log")

        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            _ = FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = handle

            process.terminationHandler = { [weak self] finished in
                try? handle.close()
                Task { @MainActor [weak self] in
                    await self?.commandDidFinish(
                        pid: finished.processIdentifier,
                        exitCode: finished.terminationStatus,
                        reason: finished.terminationReason
                    )
                }
            }

            try process.run()
            launchedProcess = process
            watchedPID = process.processIdentifier
            jobTitle = command
            logURL = log
            isWatching = true
            jobStartedAt = Date()
            elapsedSeconds = 0
            statusText = "Running until the command finishes."
            recordCommand(command)
            startStatusTimer(pid: process.processIdentifier, monitorExit: false)
        } catch {
            try? await manager.stopLiveSession()
            restoreSavedDurationPreference()
            lastError = "Could not launch the command: \(error.localizedDescription)"
        }
    }

    func useCommandFromHistory(_ command: String) {
        commandText = command
    }

    func clearCommandHistory() {
        commandHistory = []
        UserDefaults.standard.removeObject(forKey: commandHistoryKey)
    }

    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        launchedProcess = nil
        isWatching = false
        watchedPID = nil
        jobTitle = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        statusText = "Job Guard detached. Vigil keeps its current state."
        restoreSavedDurationPreference()
    }

    func openLog() {
        guard let logURL else { return }
        NSWorkspace.shared.open(logURL)
    }

    func handleVigilStoppedExternally() {
        guard isWatching else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        launchedProcess = nil
        isWatching = false
        watchedPID = nil
        jobTitle = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        statusText = "Job Guard detached because Vigil was stopped."
        restoreSavedDurationPreference()
    }

    private func beginWatching(pid: Int32, title: String) async {
        lastError = nil
        lastResult = nil
        lastExitCode = nil

        guard !isWatching else {
            lastError = "A Job Guard is already active."
            return
        }

        guard Self.processExists(pid) else {
            lastError = "PID \(pid) is not running."
            return
        }

        guard await prepareVigilForJob() else { return }

        watchedPID = pid
        jobTitle = title
        logURL = nil
        isWatching = true
        jobStartedAt = Date()
        elapsedSeconds = 0
        statusText = "Vigil will remain active until \(title) exits."
        startStatusTimer(pid: pid, monitorExit: true)
    }

    private func prepareVigilForJob() async -> Bool {
        savedDuration = manager.selectedDuration
        savedCustomMinutes = manager.customMinutes

        if manager.isActive {
            let ok = await manager.changeDurationLive(.indefinite)
            guard ok, manager.isActive else {
                lastError = manager.lastError ?? "Could not switch the active Vigil session to job-aware duration."
                restoreSavedDurationPreference()
                return false
            }
        } else {
            manager.selectedDuration = .indefinite
            await manager.startFreshSession()
            guard manager.isActive else {
                lastError = manager.lastError ?? "Could not start Vigil for this job."
                restoreSavedDurationPreference()
                return false
            }
        }

        return true
    }

    private func startStatusTimer(pid: Int32, monitorExit: Bool) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let started = self.jobStartedAt {
                    self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
                }

                guard self.manager.isActive else {
                    self.handleVigilStoppedExternally()
                    return
                }

                if monitorExit && !Self.processExists(pid) {
                    await self.finishJob(result: "\(self.jobTitle ?? "Process") exited. Vigil released.")
                }
            }
        }
        pollTimer?.tolerance = 0.15
    }

    private func commandDidFinish(
        pid: Int32,
        exitCode: Int32,
        reason: Process.TerminationReason
    ) async {
        guard isWatching, watchedPID == pid else { return }

        let reasonText = reason == .exit ? "exit" : "signal"
        await finishJob(
            result: "Command finished (\(reasonText) \(exitCode)). Vigil released.",
            exitCode: exitCode
        )
    }

    private func finishJob(result: String, exitCode: Int32? = nil) async {
        pollTimer?.invalidate()
        pollTimer = nil

        let duration: Int
        if let started = jobStartedAt {
            duration = max(0, Int(Date().timeIntervalSince(started)))
        } else {
            duration = elapsedSeconds
        }

        launchedProcess = nil
        isWatching = false
        watchedPID = nil
        jobTitle = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        lastExitCode = exitCode
        lastFinishedDuration = duration
        lastResult = result
        statusText = result

        if manager.isActive {
            await manager.stopLiveSession()
        }
        restoreSavedDurationPreference()
        await refreshProcesses()
    }

    private func recordCommand(_ command: String) {
        var history = commandHistory.filter { $0 != command }
        history.insert(command, at: 0)
        if history.count > 8 {
            history = Array(history.prefix(8))
        }
        commandHistory = history
        UserDefaults.standard.set(history, forKey: commandHistoryKey)
    }

    private func restoreSavedDurationPreference() {
        if let savedDuration {
            manager.selectedDuration = savedDuration
        }
        if let savedCustomMinutes {
            manager.customMinutes = savedCustomMinutes
        }
        manager.savePreferences()
        self.savedDuration = nil
        self.savedCustomMinutes = nil
    }

    private static func processExists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func durationText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
