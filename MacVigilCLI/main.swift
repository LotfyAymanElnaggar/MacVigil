import Foundation

private struct SavedWorkflow: Codable {
    struct Command: Codable {
        var command: String
        var cwd: String?
        var environment: [String: String]
    }

    var name: String
    var ports: [Int]
    var commands: [Command]
    var protectSuggested: Bool
}

private final class CLITransport {
    private let center = DistributedNotificationCenter.default()

    func send(_ request: MacVigilCLIRequest, autoLaunch: Bool = true) -> MacVigilCLIResponse? {
        if let response = sendOnce(request, timeout: 0.45) {
            return response
        }

        guard autoLaunch else { return nil }
        launchMacVigil()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let response = sendOnce(request, timeout: 0.55) {
                return response
            }
        }
        return nil
    }

    private func sendOnce(_ request: MacVigilCLIRequest, timeout: TimeInterval) -> MacVigilCLIResponse? {
        guard let data = try? JSONEncoder().encode(request),
              let payload = String(data: data, encoding: .utf8) else { return nil }

        var result: MacVigilCLIResponse?
        let observer = center.addObserver(
            forName: MacVigilCLIProtocol.responseName,
            object: nil,
            queue: .main
        ) { notification in
            guard let responsePayload = notification.userInfo?[MacVigilCLIProtocol.payloadKey] as? String,
                  let responseData = responsePayload.data(using: .utf8),
                  let response = try? JSONDecoder().decode(MacVigilCLIResponse.self, from: responseData),
                  response.id == request.id else { return }
            result = response
        }

        center.post(
            name: MacVigilCLIProtocol.requestName,
            object: nil,
            userInfo: [MacVigilCLIProtocol.payloadKey: payload],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(timeout)
        while result == nil && Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.04)))
        }

        center.removeObserver(observer)
        return result
    }

    private func launchMacVigil() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-b", "com.lotfy.macvigil"]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        try? open.run()
        open.waitUntilExit()

        if open.terminationStatus != 0, let appURL = bundledAppURL() {
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallback.arguments = [appURL.path]
            fallback.standardOutput = FileHandle.nullDevice
            fallback.standardError = FileHandle.nullDevice
            try? fallback.run()
            fallback.waitUntilExit()
        }
    }

    private func bundledAppURL() -> URL? {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        for _ in 0..<5 {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

private enum WorkflowStore {
    static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacVigil", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("workflows.json")
    }

    static func load() -> [SavedWorkflow] {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode([SavedWorkflow].self, from: data) else { return [] }
        return value
    }

    static func save(_ workflows: [SavedWorkflow]) throws {
        let data = try JSONEncoder.pretty.encode(workflows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

@main
struct MacVigilCLI {
    private static let transport = CLITransport()

    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printHelp()
            exit(0)
        }
        args.removeFirst()

        switch command {
        case "help", "--help", "-h":
            printHelp()

        case "version", "--version", "-v":
            if let response = transport.send(MacVigilCLIRequest(action: "ping")) {
                print("macvigil \(response.values["version"] ?? "unknown")")
            } else {
                print("macvigil CLI")
            }

        case "status":
            let json = args.contains("--json")
            guard let response = transport.send(MacVigilCLIRequest(action: "status")) else {
                fail("Could not reach MacVigil. Install and launch MacVigil.app first.")
            }
            if json, let data = try? JSONEncoder.pretty.encode(response), let text = String(data: data, encoding: .utf8) {
                print(text)
            } else {
                printResponse(response)
            }
            exit(response.ok ? 0 : 1)

        case "start":
            var options: [String: String] = [:]
            while !args.isEmpty {
                let value = args.removeFirst()
                switch value {
                case "--mode":
                    guard !args.isEmpty else { fail("--mode requires a value") }
                    options["mode"] = args.removeFirst()
                case "--duration":
                    guard !args.isEmpty else { fail("--duration requires a value") }
                    options["duration"] = args.removeFirst()
                default:
                    fail("Unknown start option: \(value)")
                }
            }
            execute(MacVigilCLIRequest(action: "start", options: options))

        case "stop":
            execute(MacVigilCLIRequest(action: "stop"))

        case "mode":
            guard let mode = args.first else { fail("Usage: macvigil mode <compute|closed-lid|full-awake>") }
            execute(MacVigilCLIRequest(action: "mode", arguments: [mode]))

        case "watch-pid":
            guard !args.isEmpty else { fail("Usage: macvigil watch-pid <pid> [pid ...]") }
            execute(MacVigilCLIRequest(action: "watch-pid", arguments: args))

        case "watch-port":
            guard !args.isEmpty else { fail("Usage: macvigil watch-port <port> [port ...]") }
            execute(MacVigilCLIRequest(action: "watch-port", arguments: args))

        case "protect-suggested":
            execute(MacVigilCLIRequest(action: "protect-suggested"))

        case "detach-all":
            execute(MacVigilCLIRequest(action: "detach-all"))

        case "run":
            runCommand(args)

        case "workflow":
            workflowCommand(args)

        case "install":
            installCLI()

        case "uninstall":
            uninstallCLI()

        default:
            fail("Unknown command: \(command)\n\nRun `macvigil help` for usage.")
        }
    }

    private static func execute(_ request: MacVigilCLIRequest) -> Never {
        guard let response = transport.send(request) else {
            fail("Could not reach MacVigil. Install and launch MacVigil.app first.")
        }
        printResponse(response)
        exit(response.ok ? 0 : 1)
    }

    private static func runCommand(_ rawArgs: [String]) -> Never {
        var args = rawArgs
        var cwd: String?
        var environment: [String: String] = [:]
        var commandParts: [String] = []

        while !args.isEmpty {
            let value = args.removeFirst()
            if value == "--" {
                commandParts.append(contentsOf: args)
                args.removeAll()
                break
            }
            if value == "--cwd" {
                guard !args.isEmpty else { fail("--cwd requires a directory") }
                cwd = NSString(string: args.removeFirst()).expandingTildeInPath
                continue
            }
            if value == "--env" {
                guard !args.isEmpty else { fail("--env requires KEY=VALUE") }
                let pair = args.removeFirst()
                guard let split = pair.firstIndex(of: "=") else { fail("Invalid environment value: \(pair)") }
                let key = String(pair[..<split])
                let val = String(pair[pair.index(after: split)...])
                guard validEnvironmentKey(key) else { fail("Invalid environment key: \(key)") }
                environment[key] = val
                continue
            }
            commandParts.append(value)
            commandParts.append(contentsOf: args)
            args.removeAll()
        }

        guard !commandParts.isEmpty else {
            fail("Usage: macvigil run [--cwd DIR] [--env KEY=VALUE] -- <command>")
        }

        guard let ping = transport.send(MacVigilCLIRequest(action: "ping")), ping.ok else {
            fail("Could not start or reach MacVigil before launching the command.")
        }

        if let cwd {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
                fail("Working directory does not exist: \(cwd)")
            }
        }

        let command = commandParts.map(shellToken).joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true) }
        var processEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { processEnvironment[$0.key] = $0.value }
        process.environment = processEnvironment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            fail("Could not launch command: \(error.localizedDescription)")
        }

        let title = commandParts.joined(separator: " ")
        let watchRequest = MacVigilCLIRequest(
            action: "watch-pid",
            arguments: [String(process.processIdentifier)],
            options: ["title": title]
        )
        if let response = transport.send(watchRequest), response.ok {
            fputs("MacVigil: protecting PID \(process.processIdentifier) until it exits.\n", stderr)
        } else {
            fputs("MacVigil warning: the command is running, but Job Guard could not attach to PID \(process.processIdentifier).\n", stderr)
        }

        process.waitUntilExit()
        exit(process.terminationStatus)
    }

    private static func workflowCommand(_ rawArgs: [String]) -> Never {
        var args = rawArgs
        guard let subcommand = args.first else {
            fail("Usage: macvigil workflow <list|show|save|run|delete> ...")
        }
        args.removeFirst()

        switch subcommand {
        case "list":
            let workflows = WorkflowStore.load()
            if workflows.isEmpty {
                print("No saved workflows.")
            } else {
                for workflow in workflows {
                    print("\(workflow.name) · \(workflow.ports.count) port(s) · \(workflow.commands.count) command(s)\(workflow.protectSuggested ? " · suggested workloads" : "")")
                }
            }
            exit(0)

        case "show":
            guard let name = args.first else { fail("Usage: macvigil workflow show <name>") }
            guard let workflow = WorkflowStore.load().first(where: { $0.name == name }) else { fail("Workflow not found: \(name)") }
            if let data = try? JSONEncoder.pretty.encode(workflow), let text = String(data: data, encoding: .utf8) { print(text) }
            exit(0)

        case "delete":
            guard let name = args.first else { fail("Usage: macvigil workflow delete <name>") }
            var workflows = WorkflowStore.load()
            let before = workflows.count
            workflows.removeAll { $0.name == name }
            guard workflows.count != before else { fail("Workflow not found: \(name)") }
            do { try WorkflowStore.save(workflows) } catch { fail("Could not save workflows: \(error.localizedDescription)") }
            print("Deleted workflow '\(name)'.")
            exit(0)

        case "save":
            guard let name = args.first else { fail("Usage: macvigil workflow save <name> [options]") }
            args.removeFirst()
            var ports: [Int] = []
            var commands: [String] = []
            var cwd: String?
            var environment: [String: String] = [:]
            var suggested = false

            while !args.isEmpty {
                let value = args.removeFirst()
                switch value {
                case "--port":
                    guard let raw = args.first, let port = Int(raw), (1...65535).contains(port) else { fail("--port requires a TCP port") }
                    args.removeFirst()
                    ports.append(port)
                case "--command":
                    guard !args.isEmpty else { fail("--command requires a command string") }
                    commands.append(args.removeFirst())
                case "--cwd":
                    guard !args.isEmpty else { fail("--cwd requires a directory") }
                    cwd = NSString(string: args.removeFirst()).expandingTildeInPath
                case "--env":
                    guard !args.isEmpty else { fail("--env requires KEY=VALUE") }
                    let pair = args.removeFirst()
                    guard let split = pair.firstIndex(of: "=") else { fail("Invalid environment value: \(pair)") }
                    let key = String(pair[..<split])
                    let val = String(pair[pair.index(after: split)...])
                    guard validEnvironmentKey(key) else { fail("Invalid environment key: \(key)") }
                    environment[key] = val
                case "--suggested":
                    suggested = true
                default:
                    fail("Unknown workflow option: \(value)")
                }
            }

            guard !ports.isEmpty || !commands.isEmpty || suggested else {
                fail("A workflow needs at least one --port, --command, or --suggested item.")
            }

            let workflow = SavedWorkflow(
                name: name,
                ports: Array(Set(ports)).sorted(),
                commands: commands.map { .init(command: $0, cwd: cwd, environment: environment) },
                protectSuggested: suggested
            )
            var workflows = WorkflowStore.load().filter { $0.name != name }
            workflows.append(workflow)
            do { try WorkflowStore.save(workflows) } catch { fail("Could not save workflow: \(error.localizedDescription)") }
            print("Saved workflow '\(name)'.")
            exit(0)

        case "run":
            guard let name = args.first else { fail("Usage: macvigil workflow run <name>") }
            guard let workflow = WorkflowStore.load().first(where: { $0.name == name }) else { fail("Workflow not found: \(name)") }
            var failures: [String] = []

            if workflow.protectSuggested {
                if let response = transport.send(MacVigilCLIRequest(action: "protect-suggested")), !response.ok {
                    failures.append(response.message)
                }
            }
            if !workflow.ports.isEmpty {
                let response = transport.send(MacVigilCLIRequest(action: "watch-port", arguments: workflow.ports.map(String.init)))
                if response?.ok != true { failures.append(response?.message ?? "Could not add workflow ports.") }
            }
            for item in workflow.commands {
                var options: [String: String] = [:]
                if let cwd = item.cwd { options["cwd"] = cwd }
                let response = transport.send(MacVigilCLIRequest(
                    action: "run-command",
                    arguments: [item.command],
                    options: options,
                    environment: item.environment
                ))
                if response?.ok != true { failures.append(response?.message ?? "Could not launch workflow command.") }
            }

            if failures.isEmpty {
                print("Started workflow '\(name)' in Job Guard.")
                if let status = transport.send(MacVigilCLIRequest(action: "status")) { printResponse(status) }
                exit(0)
            }
            fail("Workflow started with errors:\n" + failures.map { "- \($0)" }.joined(separator: "\n"))

        default:
            fail("Unknown workflow command: \(subcommand)")
        }
    }

    private static func installCLI() -> Never {
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let target = "/usr/local/bin/macvigil"
        let command = "/bin/mkdir -p /usr/local/bin && /bin/ln -sf \(shellQuote(source)) \(shellQuote(target))"
        let script = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"
        let result = runProcess("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else { fail(result.stderr.isEmpty ? "Could not install CLI." : result.stderr) }
        print("Installed macvigil at \(target)")
        exit(0)
    }

    private static func uninstallCLI() -> Never {
        let target = "/usr/local/bin/macvigil"
        let destination = URL(fileURLWithPath: target)
        if FileManager.default.fileExists(atPath: target),
           let attrs = try? FileManager.default.attributesOfItem(atPath: target),
           let type = attrs[.type] as? FileAttributeType,
           type != .typeSymbolicLink {
            fail("Refusing to remove \(target) because it is not a symbolic link.")
        }
        let command = "/bin/rm -f \(shellQuote(destination.path))"
        let script = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"
        let result = runProcess("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else { fail(result.stderr.isEmpty ? "Could not uninstall CLI." : result.stderr) }
        print("Removed \(target)")
        exit(0)
    }

    private static func printResponse(_ response: MacVigilCLIResponse) {
        print(response.message)
        response.lines.forEach { print($0) }
        if !response.ok { fputs("\n", stderr) }
    }

    private static func validEnvironmentKey(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    private static func shellToken(_ value: String) -> String {
        shellQuote(value)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("macvigil: \(message)\n", stderr)
        exit(1)
    }

    private static func printHelp() {
        print("""
        macvigil — control MacVigil from Terminal

        Usage:
          macvigil status [--json]
          macvigil start [--mode compute|closed-lid|full-awake] [--duration 30m|2h|150m|infinity]
          macvigil stop
          macvigil mode <compute|closed-lid|full-awake>
          macvigil run [--cwd DIR] [--env KEY=VALUE] -- <command>
          macvigil watch-pid <pid> [pid ...]
          macvigil watch-port <port> [port ...]
          macvigil protect-suggested
          macvigil detach-all

          macvigil workflow list
          macvigil workflow show <name>
          macvigil workflow save <name> [--port N] [--command CMD] [--cwd DIR] [--env KEY=VALUE] [--suggested]
          macvigil workflow run <name>
          macvigil workflow delete <name>

          macvigil install
          macvigil uninstall

        `run` inherits your terminal input/output and returns the command's exit status.
        `watch-pid`, `watch-port`, workflow commands, and GUI jobs all join the same Job Guard collection.
        Mode changes never replace Job Guard lifetime ownership.
        """)
    }
}
