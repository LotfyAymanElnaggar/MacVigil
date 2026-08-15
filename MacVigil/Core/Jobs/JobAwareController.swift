import Foundation
import AppKit
import Darwin

@MainActor
final class JobAwareController: ObservableObject {
    @Published var pidText = ""
    @Published var commandText = ""
    @Published private(set) var isWatching = false
    @Published private(set) var watchedPID: Int32?
    @Published private(set) var jobTitle: String?
    @Published private(set) var statusText: String?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastError: String?
    @Published private(set) var logURL: URL?

    private let manager: VigilManager
    private var pollTimer: Timer?
    private var launchedProcess: Process?
    private var savedDuration: SessionDuration?
    private var savedCustomMinutes: Int?

    init(manager: VigilManager) {
        self.manager = manager
    }

    var displayStatus: String {
        guard isWatching else { return lastResult ?? "Not watching a job" }
        if let pid = watchedPID, let title = jobTitle {
            return "\(title) · PID \(pid)"
        }
        return jobTitle ?? "Watching job"
    }

    func watchPID() async {
        lastError = nil
        lastResult = nil

        guard !isWatching else {
            lastError = "A Job Guard is already active."
            return
        }

        let trimmed = pidText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawPID = Int32(trimmed), rawPID > 1 else {
            lastError = "Enter a valid process ID greater than 1."
            return
        }

        guard Self.processExists(rawPID) else {
            lastError = "PID \(rawPID) is not running."
            return
        }

        guard await prepareVigilForJob() else { return }

        watchedPID = rawPID
        jobTitle = "Watching process"
        isWatching = true
        statusText = "Vigil will remain active until PID \(rawPID) exits."
        startPollingPID(rawPID)
    }

    func runCommand() async {
        lastError = nil
        lastResult = nil

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
            FileManager.default.createFile(atPath: log.path, contents: nil)
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
            statusText = "Running until the command finishes."
        } catch {
            try? await manager.stopLiveSession()
            restoreSavedDurationPreference()
            lastError = "Could not launch the command: \(error.localizedDescription)"
        }
    }

    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        launchedProcess = nil
        isWatching = false
        watchedPID = nil
        jobTitle = nil
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
        statusText = "Job Guard detached because Vigil was stopped."
        restoreSavedDurationPreference()
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

    private func startPollingPID(_ pid: Int32) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard self.manager.isActive else {
                    self.handleVigilStoppedExternally()
                    return
                }

                if !Self.processExists(pid) {
                    await self.finishJob(result: "PID \(pid) exited. Vigil released.")
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
        await finishJob(result: "Command finished (\(reasonText) \(exitCode)). Vigil released.")
    }

    private func finishJob(result: String) async {
        pollTimer?.invalidate()
        pollTimer = nil
        launchedProcess = nil
        isWatching = false
        watchedPID = nil
        jobTitle = nil
        lastResult = result
        statusText = result

        if manager.isActive {
            await manager.stopLiveSession()
        }
        restoreSavedDurationPreference()
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
}
