import Foundation

/// Receives local commands from the bundled `macvigil` client and executes them
/// against the single in-process VigilManager / Job Guard state machine.
///
/// Distributed notifications are used only as a local control transport. The
/// payload is JSON encoded into a String so the notification userInfo remains a
/// property-list-safe value. No network listener is opened.
@MainActor
final class CLIControlServer {
    private weak var manager: VigilManager?
    private weak var jobs: JobAwareController?
    private let center = DistributedNotificationCenter.default()
    private var observer: NSObjectProtocol?

    init(manager: VigilManager, jobs: JobAwareController) {
        self.manager = manager
        self.jobs = jobs
    }

    func start() {
        guard observer == nil else { return }
        observer = center.addObserver(
            forName: MacVigilCLIProtocol.requestName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payload = notification.userInfo?[MacVigilCLIProtocol.payloadKey] as? String,
                  let data = payload.data(using: .utf8),
                  let request = try? JSONDecoder().decode(MacVigilCLIRequest.self, from: data) else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let response = await self.handle(request)
                self.post(response)
            }
        }
    }

    func stop() {
        if let observer {
            center.removeObserver(observer)
            self.observer = nil
        }
    }

    private func post(_ response: MacVigilCLIResponse) {
        guard let data = try? JSONEncoder().encode(response),
              let payload = String(data: data, encoding: .utf8) else { return }
        center.post(
            name: MacVigilCLIProtocol.responseName,
            object: nil,
            userInfo: [MacVigilCLIProtocol.payloadKey: payload],
            deliverImmediately: true
        )
    }

    private func handle(_ request: MacVigilCLIRequest) async -> MacVigilCLIResponse {
        guard let manager, let jobs else {
            return failure(request, "MacVigil runtime is still starting.")
        }

        switch request.action {
        case "ping":
            return success(request, "MacVigil is running.", values: ["version": appVersion])

        case "status":
            return statusResponse(request, manager: manager, jobs: jobs)

        case "start":
            if let modeValue = request.options["mode"] {
                guard let mode = runtimeProfile(modeValue) else {
                    return failure(request, "Unknown mode '\(modeValue)'. Use compute, closed-lid, or full-awake.")
                }
                let changed = await manager.changeModeLive(mode)
                guard changed else {
                    return failure(request, manager.lastError ?? "MacVigil could not apply \(mode.title) safely.")
                }
            }

            if let durationValue = request.options["duration"] {
                guard let parsed = duration(durationValue) else {
                    return failure(request, "Invalid duration '\(durationValue)'. Try 30m, 2h, 150m, or infinity.")
                }
                let changed = await manager.changeDurationLive(parsed.duration, customMinutes: parsed.customMinutes)
                guard changed else {
                    return failure(request, "The current session owner controls its lifetime, so the duration cannot be replaced.")
                }
            }

            if manager.isActive {
                return success(request, "Vigil is already active.", lines: statusLines(manager: manager, jobs: jobs))
            }

            if manager.closedLidProtectionRequested && !manager.hasAcknowledgedClosedLidSafety {
                return failure(request, "Closed-Lid Eco needs its first-use safety acknowledgement in the MacVigil UI before it can be started from Terminal.")
            }

            await manager.startFreshSession()
            guard manager.isActive else {
                return failure(request, manager.lastError ?? "Vigil did not start.")
            }
            return success(request, "Vigil started.", lines: statusLines(manager: manager, jobs: jobs))

        case "stop":
            if manager.isActive {
                await manager.stopLiveSession()
                jobs.handleVigilStoppedExternally()
            }
            return success(request, "Vigil stopped. Running workloads were not terminated.")

        case "mode":
            guard let value = request.arguments.first ?? request.options["mode"],
                  let mode = runtimeProfile(value) else {
                return failure(request, "Choose a mode: compute, closed-lid, or full-awake.")
            }
            let changed = await manager.changeModeLive(mode)
            guard changed else {
                return failure(request, manager.lastError ?? "MacVigil could not apply \(mode.title) safely.")
            }
            return success(request, "Mode set to \(mode.title).", lines: statusLines(manager: manager, jobs: jobs))

        case "watch-pid":
            guard !request.arguments.isEmpty else {
                return failure(request, "Provide at least one PID.")
            }
            var added = 0
            var errors: [String] = []
            for value in request.arguments {
                guard let pid = Int32(value), pid > 1 else {
                    errors.append("\(value): invalid PID")
                    continue
                }
                jobs.pidText = String(pid)
                await jobs.watchPID()
                if let error = jobs.lastError {
                    errors.append("PID \(pid): \(error)")
                } else {
                    added += 1
                }
            }
            guard added > 0 else {
                return failure(request, errors.joined(separator: "\n"))
            }
            var lines = ["Added \(added) process\(added == 1 ? "" : "es") to Job Guard."]
            lines.append(contentsOf: errors.map { "Warning: \($0)" })
            lines.append(contentsOf: statusLines(manager: manager, jobs: jobs))
            return success(request, "Job Guard updated.", lines: lines)

        case "watch-port":
            guard !request.arguments.isEmpty else {
                return failure(request, "Provide at least one TCP port.")
            }
            var added = 0
            var errors: [String] = []
            for value in request.arguments {
                guard let port = Int(value), (1...65535).contains(port) else {
                    errors.append("\(value): invalid TCP port")
                    continue
                }
                jobs.portText = String(port)
                await jobs.watchPort()
                if let error = jobs.lastError {
                    errors.append("Port \(port): \(error)")
                } else {
                    added += 1
                }
            }
            guard added > 0 else {
                return failure(request, errors.joined(separator: "\n"))
            }
            var lines = ["Added \(added) port watch\(added == 1 ? "" : "es") to Job Guard."]
            lines.append(contentsOf: errors.map { "Warning: \($0)" })
            lines.append(contentsOf: statusLines(manager: manager, jobs: jobs))
            return success(request, "Job Guard updated.", lines: lines)

        case "protect-suggested":
            await jobs.refreshProcesses()
            await jobs.protectSuggestedWorkloads()
            if let error = jobs.lastError {
                return failure(request, error)
            }
            return success(request, jobs.statusText ?? "Suggested workloads reviewed.", lines: statusLines(manager: manager, jobs: jobs))

        case "detach-all":
            jobs.detachAll()
            return success(request, "Job Guard detached. Underlying workloads keep running.", lines: statusLines(manager: manager, jobs: jobs))

        default:
            return failure(request, "Unknown CLI action '\(request.action)'.")
        }
    }

    private func statusResponse(
        _ request: MacVigilCLIRequest,
        manager: VigilManager,
        jobs: JobAwareController
    ) -> MacVigilCLIResponse {
        success(
            request,
            manager.isActive ? "Vigil is active." : "Vigil is idle.",
            lines: statusLines(manager: manager, jobs: jobs),
            values: [
                "active": manager.isActive ? "true" : "false",
                "mode": manager.configurationName,
                "owner": ownerName(manager.sessionOwner),
                "jobs": String(jobs.activeJobCount)
            ]
        )
    }

    private func statusLines(manager: VigilManager, jobs: JobAwareController) -> [String] {
        var lines = [
            "State: \(manager.isActive ? "ACTIVE" : "IDLE")",
            "Mode: \(manager.configurationName)",
            "Owner: \(ownerName(manager.sessionOwner))"
        ]

        if manager.isActive {
            if let seconds = manager.effectiveRemainingSeconds {
                lines.append("Remaining: \(Self.durationText(Int(seconds)))")
            } else {
                lines.append("Remaining: infinity")
            }
        }

        if jobs.isWatching {
            lines.append("Job Guard: \(jobs.activeJobCount) active item\(jobs.activeJobCount == 1 ? "" : "s")")
            for job in jobs.activeJobs.prefix(20) {
                if let port = job.port {
                    lines.append("  - Port \(port) · listening · \(jobs.elapsedText(for: job))")
                } else {
                    lines.append("  - PID \(job.pid) · \(job.title) · \(jobs.elapsedText(for: job))")
                }
            }
        }

        return lines
    }

    private func runtimeProfile(_ raw: String) -> RuntimeProfile? {
        switch raw.lowercased() {
        case "compute", "compute-guard", "computeguard": return .computeGuard
        case "closed-lid", "closedlid", "closed-lid-eco", "eco": return .closedLidEco
        case "full", "full-awake", "fullawake": return .fullAwake
        default: return nil
        }
    }

    private func duration(_ raw: String) -> (duration: SessionDuration, customMinutes: Int?)? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["infinity", "infinite", "indefinite", "inf", "∞"].contains(value) {
            return (.indefinite, nil)
        }
        if value == "15m" { return (.fifteenMinutes, nil) }
        if value == "30m" { return (.thirtyMinutes, nil) }
        if value == "1h" || value == "60m" { return (.oneHour, nil) }
        if value == "2h" || value == "120m" { return (.twoHours, nil) }

        if value.hasSuffix("m"), let minutes = Int(value.dropLast()), (1...1440).contains(minutes) {
            return (.custom, minutes)
        }
        if value.hasSuffix("h"), let hours = Double(value.dropLast()), hours > 0, hours <= 24 {
            return (.custom, max(1, Int((hours * 60).rounded())))
        }
        if let minutes = Int(value), (1...1440).contains(minutes) {
            return (.custom, minutes)
        }
        return nil
    }

    private func ownerName(_ owner: VigilSessionOwner?) -> String {
        switch owner {
        case .jobGuard: return "Job Guard"
        case .commandLine: return "CLI"
        case .user: return "Timer"
        case nil: return "None"
        }
    }

    private func success(
        _ request: MacVigilCLIRequest,
        _ message: String,
        lines: [String] = [],
        values: [String: String] = [:]
    ) -> MacVigilCLIResponse {
        MacVigilCLIResponse(id: request.id, ok: true, message: message, lines: lines, values: values)
    }

    private func failure(_ request: MacVigilCLIRequest, _ message: String) -> MacVigilCLIResponse {
        MacVigilCLIResponse(id: request.id, ok: false, message: message)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static func durationText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
