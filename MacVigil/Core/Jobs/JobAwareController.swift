import Foundation
import AppKit
import Darwin

@MainActor
final class JobAwareController: ObservableObject {
    enum WorkloadKind: String, CaseIterable {
        case aiAgent
        case localAI
        case build
        case containers
        case devServer
        case transfer

        var title: String {
            switch self {
            case .aiAgent: return "AI agent"
            case .localAI: return "Local AI"
            case .build: return "Build / test"
            case .containers: return "Containers"
            case .devServer: return "Dev server"
            case .transfer: return "Transfer"
            }
        }

        var systemImage: String {
            switch self {
            case .aiAgent: return "sparkles"
            case .localAI: return "brain.head.profile"
            case .build: return "hammer"
            case .containers: return "shippingbox"
            case .devServer: return "network"
            case .transfer: return "arrow.left.arrow.right"
            }
        }

        var sortPriority: Int {
            switch self {
            case .aiAgent: return 0
            case .localAI: return 1
            case .build: return 2
            case .containers: return 3
            case .devServer: return 4
            case .transfer: return 5
            }
        }
    }

    enum ProtectedJobKind: Equatable {
        case process
        case command

        var title: String {
            switch self {
            case .process: return "Process"
            case .command: return "Command"
            }
        }

        var systemImage: String {
            switch self {
            case .process: return "gearshape.2"
            case .command: return "terminal"
            }
        }
    }

    enum ProtectedJobState: Equatable {
        case running
        case finished
        case detached

        var title: String {
            switch self {
            case .running: return "Running"
            case .finished: return "Finished"
            case .detached: return "Detached"
            }
        }

        var systemImage: String {
            switch self {
            case .running: return "bolt.shield.fill"
            case .finished: return "checkmark.circle.fill"
            case .detached: return "link.badge.minus"
            }
        }
    }

    struct ProtectedJob: Identifiable {
        let id: UUID
        let kind: ProtectedJobKind
        let pid: Int32
        let title: String
        let startedAt: Date
        let logURL: URL?
        var state: ProtectedJobState
        var finishedAt: Date?
        var exitCode: Int32?
        var result: String?

        var elapsedSeconds: Int {
            let end = finishedAt ?? Date()
            return max(0, Int(end.timeIntervalSince(startedAt)))
        }
    }

    struct ProcessCandidate: Identifiable {
        let pid: Int32
        let name: String
        let path: String
        let cpuPercent: Double
        let icon: NSImage?
        let isApplication: Bool
        let workloadKind: WorkloadKind?

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
    @Published private(set) var protectedJobs: [ProtectedJob] = []

    @Published private(set) var statusText: String?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastError: String?
    @Published private(set) var jobStartedAt: Date?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var lastFinishedDuration: Int?

    private let manager: VigilManager
    private var pollTimer: Timer?
    private var launchedProcesses: [UUID: Process] = [:]
    private var savedDuration: SessionDuration?
    private var savedCustomMinutes: Int?
    private var guardSessionID: UUID?

    private let commandHistoryKey = "MacVigil.jobs.commandHistory"

    init(manager: VigilManager) {
        self.manager = manager
        commandHistory = UserDefaults.standard.stringArray(forKey: commandHistoryKey) ?? []
    }

    var activeJobs: [ProtectedJob] {
        protectedJobs.filter { $0.state == .running }
    }

    var activeJobCount: Int { activeJobs.count }
    var isWatching: Bool { activeJobCount > 0 }
    var hasLogs: Bool { activeJobs.contains { $0.logURL != nil } }

    // Compatibility conveniences used by compact UI and diagnostics.
    var watchedPID: Int32? { activeJobCount == 1 ? activeJobs.first?.pid : nil }
    var jobTitle: String? { activeJobCount == 1 ? activeJobs.first?.title : nil }
    var logURL: URL? { activeJobs.compactMap(\.logURL).first }

    var displayStatus: String {
        guard isWatching else { return lastResult ?? "Not watching a job" }
        if activeJobCount == 1, let job = activeJobs.first {
            return "\(job.title) · PID \(job.pid)"
        }
        return "\(activeJobCount) jobs protected · Vigil ends after the last one"
    }

    var elapsedText: String { Self.durationText(elapsedSeconds) }

    var lastDurationText: String? {
        guard let lastFinishedDuration else { return nil }
        return Self.durationText(lastFinishedDuration)
    }

    func elapsedText(for job: ProtectedJob) -> String {
        Self.durationText(job.elapsedSeconds)
    }

    func isProtected(pid: Int32) -> Bool {
        activeJobs.contains { $0.pid == pid }
    }

    var filteredProcesses: [ProcessCandidate] {
        let query = processSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return processes }
        return processes.filter {
            $0.name.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.workloadKind?.title.lowercased().contains(query) == true ||
            String($0.pid).contains(query)
        }
    }

    var suggestedProcesses: [ProcessCandidate] {
        processes
            .filter { $0.workloadKind != nil }
            .sorted { lhs, rhs in
                let leftPriority = lhs.workloadKind?.sortPriority ?? Int.max
                let rightPriority = rhs.workloadKind?.sortPriority ?? Int.max
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.05 { return lhs.cpuPercent > rhs.cpuPercent }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var detectedWorkloadCount: Int { suggestedProcesses.count }

    var detectionSummary: String {
        let count = detectedWorkloadCount
        if count == 0 { return "No obvious developer workloads detected right now." }
        return count == 1 ? "1 likely workload detected." : "\(count) likely workloads detected."
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
                let displayName = resolvedName.isEmpty ? "Process \(pid)" : resolvedName

                candidates.append(ProcessCandidate(
                    pid: pid,
                    name: displayName,
                    path: path,
                    cpuPercent: cpu,
                    icon: app?.icon,
                    isApplication: app != nil,
                    workloadKind: Self.detectWorkload(name: displayName, path: path, cpuPercent: cpu)
                ))
                seen.insert(pid)
            }
        }

        for app in runningApps where app.processIdentifier > 1 && app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            guard !seen.contains(pid) else { continue }
            let name = app.localizedName ?? app.bundleIdentifier ?? "Process \(pid)"
            let path = app.bundleURL?.path ?? app.executableURL?.path ?? ""
            candidates.append(ProcessCandidate(
                pid: pid,
                name: name,
                path: path,
                cpuPercent: 0,
                icon: app.icon,
                isApplication: true,
                workloadKind: Self.detectWorkload(name: name, path: path, cpuPercent: 0)
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
        await addWatchedProcess(pid: process.pid, title: process.name)
    }

    func watchPID() async {
        lastError = nil
        let trimmed = pidText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawPID = Int32(trimmed), rawPID > 1 else {
            lastError = "Enter a valid process ID greater than 1."
            return
        }

        let known = processes.first(where: { $0.pid == rawPID })
        await addWatchedProcess(pid: rawPID, title: known?.name ?? "Process \(rawPID)")
    }

    func runCommand() async {
        lastError = nil
        lastExitCode = nil

        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            lastError = "Enter a command to run."
            return
        }

        let startingNewGuard = !isWatching
        guard await prepareVigilForFirstJobIfNeeded() else { return }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVigilJobs", isDirectory: true)
        let id = UUID()
        let log = workspace.appendingPathComponent("job-\(id.uuidString).log")

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
                        id: id,
                        pid: finished.processIdentifier,
                        exitCode: finished.terminationStatus,
                        reason: finished.terminationReason
                    )
                }
            }

            try process.run()
            launchedProcesses[id] = process
            protectedJobs.append(ProtectedJob(
                id: id,
                kind: .command,
                pid: process.processIdentifier,
                title: command,
                startedAt: Date(),
                logURL: log,
                state: .running,
                finishedAt: nil,
                exitCode: nil,
                result: nil
            ))
            recordCommand(command)
            statusText = activeJobCount == 1
                ? "Running until the command finishes."
                : "Command added. \(activeJobCount) jobs are now protected."
            commandText = ""
            ensurePollTimer()
        } catch {
            if startingNewGuard {
                await abortNewGuardAfterFailedAdd()
            }
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

    func detachJob(_ id: UUID) {
        guard let index = protectedJobs.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        protectedJobs[index].state = .detached
        protectedJobs[index].finishedAt = Date()
        protectedJobs[index].result = "Detached from Job Guard."

        if isWatching {
            statusText = "Job detached. \(activeJobCount) protected job\(activeJobCount == 1 ? "" : "s") remain."
        } else {
            endOwnershipWithoutStoppingVigil(message: "Job Guard detached. Vigil keeps its current state.")
        }
    }

    func detach() {
        detachAll()
    }

    func detachAll() {
        guard isWatching else { return }
        let now = Date()
        for index in protectedJobs.indices where protectedJobs[index].state == .running {
            protectedJobs[index].state = .detached
            protectedJobs[index].finishedAt = now
            protectedJobs[index].result = "Detached from Job Guard."
        }
        endOwnershipWithoutStoppingVigil(message: "All jobs detached. Vigil keeps its current state.")
    }

    func openLog() {
        guard let url = activeJobs.compactMap(\.logURL).first ?? protectedJobs.reversed().compactMap(\.logURL).first else { return }
        NSWorkspace.shared.open(url)
    }

    func openLog(for job: ProtectedJob) {
        guard let url = job.logURL else { return }
        NSWorkspace.shared.open(url)
    }

    func handleVigilStoppedExternally() {
        guard isWatching else { return }
        guard !manager.isLiveReconfiguring else {
            statusText = "Job Guard remains attached while the protection mode changes."
            return
        }

        let now = Date()
        for index in protectedJobs.indices where protectedJobs[index].state == .running {
            protectedJobs[index].state = .detached
            protectedJobs[index].finishedAt = now
            protectedJobs[index].result = "Protection stopped manually; the job was not terminated."
        }
        stopPollTimer()
        if let owner = currentOwner {
            manager.releaseSessionOwnership(owner)
        }
        guardSessionID = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        statusText = "Job Guard detached because Vigil was stopped. Running jobs were not terminated."
        restoreSavedDurationPreference()
    }

    private var currentOwner: VigilSessionOwner? {
        guard let guardSessionID else { return nil }
        return .jobGuard(guardSessionID)
    }

    private func addWatchedProcess(pid: Int32, title: String) async {
        lastError = nil
        lastExitCode = nil

        guard !isProtected(pid: pid) else {
            lastError = "PID \(pid) is already protected by Job Guard."
            return
        }
        guard Self.processExists(pid) else {
            lastError = "PID \(pid) is not running."
            return
        }
        guard await prepareVigilForFirstJobIfNeeded() else { return }

        protectedJobs.append(ProtectedJob(
            id: UUID(),
            kind: .process,
            pid: pid,
            title: title,
            startedAt: Date(),
            logURL: nil,
            state: .running,
            finishedAt: nil,
            exitCode: nil,
            result: nil
        ))
        statusText = activeJobCount == 1
            ? "Vigil will remain active until \(title) exits."
            : "\(title) added. \(activeJobCount) jobs are now protected."
        ensurePollTimer()
    }

    private func prepareVigilForFirstJobIfNeeded() async -> Bool {
        if isWatching { return true }

        // Starting a new Job Guard collection replaces old finished/detached rows.
        protectedJobs.removeAll()
        lastResult = nil
        lastFinishedDuration = nil

        savedDuration = manager.selectedDuration
        savedCustomMinutes = manager.customMinutes
        let sessionID = UUID()
        let owner = VigilSessionOwner.jobGuard(sessionID)

        if manager.isActive {
            if let existingOwner = manager.sessionOwner, existingOwner != .user {
                lastError = "The active Vigil session is already owned by \(existingOwner.title)."
                restoreSavedDurationPreference()
                return false
            }

            // Convert a normal active timer into job-owned indefinite duration
            // before claiming ownership. Once claimed, user duration changes are
            // blocked until Job Guard releases or detaches.
            let ok = await manager.changeDurationLive(.indefinite)
            guard ok, manager.isActive else {
                lastError = "Could not switch the active Vigil session to job-aware duration."
                restoreSavedDurationPreference()
                return false
            }
            guard manager.claimSessionOwnership(owner) else {
                lastError = "Could not claim the active Vigil session for Job Guard."
                restoreSavedDurationPreference()
                return false
            }
        } else {
            manager.selectedDuration = .indefinite
            await manager.startFreshSession(owner: owner)
            guard manager.isActive, manager.sessionOwner == owner else {
                lastError = "Could not start Vigil for Job Guard."
                restoreSavedDurationPreference()
                return false
            }
        }

        guardSessionID = sessionID
        jobStartedAt = Date()
        elapsedSeconds = 0
        return true
    }

    private func ensurePollTimer() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollTick()
            }
        }
        pollTimer?.tolerance = 0.15
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTick() async {
        if let started = jobStartedAt {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
        }

        guard isWatching else {
            stopPollTimer()
            return
        }

        guard manager.isActive else {
            handleVigilStoppedExternally()
            return
        }

        let exited = activeJobs
            .filter { $0.kind == .process && !Self.processExists($0.pid) }
            .map(\.id)

        for id in exited {
            await finishJob(id: id, result: "Process exited.")
        }
    }

    private func commandDidFinish(
        id: UUID,
        pid: Int32,
        exitCode: Int32,
        reason: Process.TerminationReason
    ) async {
        launchedProcesses[id] = nil
        guard let job = protectedJobs.first(where: { $0.id == id }), job.state == .running, job.pid == pid else { return }
        let reasonText = reason == .exit ? "exit" : "signal"
        await finishJob(
            id: id,
            result: "Command finished (\(reasonText) \(exitCode)).",
            exitCode: exitCode
        )
    }

    private func finishJob(id: UUID, result: String, exitCode: Int32? = nil) async {
        guard let index = protectedJobs.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        let title = protectedJobs[index].title
        let finishedAt = Date()
        protectedJobs[index].state = .finished
        protectedJobs[index].finishedAt = finishedAt
        protectedJobs[index].exitCode = exitCode
        protectedJobs[index].result = result
        lastExitCode = exitCode

        if isWatching {
            statusText = "\(title) finished. \(activeJobCount) protected job\(activeJobCount == 1 ? "" : "s") remain."
            return
        }

        stopPollTimer()
        let totalDuration = jobStartedAt.map { max(0, Int(finishedAt.timeIntervalSince($0))) } ?? elapsedSeconds
        lastFinishedDuration = totalDuration
        lastResult = "All protected jobs finished. Vigil released."
        statusText = lastResult

        while manager.isLiveReconfiguring {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if let owner = currentOwner, manager.sessionOwner == owner {
            if manager.isActive {
                await manager.stopLiveSession()
            } else {
                manager.releaseSessionOwnership(owner)
            }
        }

        guardSessionID = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        restoreSavedDurationPreference()
        await refreshProcesses()
    }

    private func abortNewGuardAfterFailedAdd() async {
        if let owner = currentOwner, manager.sessionOwner == owner {
            if manager.isActive {
                await manager.stopLiveSession()
            } else {
                manager.releaseSessionOwnership(owner)
            }
        }
        guardSessionID = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        restoreSavedDurationPreference()
    }

    private func endOwnershipWithoutStoppingVigil(message: String) {
        stopPollTimer()
        if let owner = currentOwner {
            manager.releaseSessionOwnership(owner)
        }
        guardSessionID = nil
        jobStartedAt = nil
        elapsedSeconds = 0
        statusText = message
        restoreSavedDurationPreference()
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

    private static func detectWorkload(name: String, path: String, cpuPercent: Double) -> WorkloadKind? {
        let nameValue = name.lowercased()
        let combined = "\(name) \(path)".lowercased()

        if containsAny(combined, [
            "claude", "codex", "aider", "opencode", "cline", "roo-code", "continue"
        ]) {
            return .aiAgent
        }

        if containsAny(combined, [
            "ollama", "lm studio", "lm-studio", "lmstudio", "llama-server", "llama-cli",
            "mlx_lm", "mlx-lm", "koboldcpp", "localai"
        ]) {
            return .localAI
        }

        if containsAny(combined, [
            "xcodebuild", "swiftc", "cargo", "rustc", "gradle", "gradlew", "mvn", "ninja", "cmake"
        ]) || ["make"].contains(nameValue) {
            return .build
        }

        if containsAny(combined, [
            "docker", "com.docker", "colima", "podman", "containerd", "orbstack", "lima"
        ]) {
            return .containers
        }

        if containsAny(combined, [
            "uvicorn", "gunicorn", "jupyter", "vite", "next-server", "webpack", "redis-server",
            "postgres", "mongod"
        ]) || ["bun", "deno"].contains(nameValue) || (nameValue == "node" && cpuPercent >= 0.2) {
            return .devServer
        }

        if containsAny(combined, ["rsync", "rclone"]) || ["scp", "sftp"].contains(nameValue) {
            return .transfer
        }

        return nil
    }

    private static func containsAny(_ value: String, _ patterns: [String]) -> Bool {
        patterns.contains { value.contains($0) }
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
