import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }
}

enum ShellRunner {
    static func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                    let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: ShellResult(status: process.terminationStatus, stdout: stdout, stderr: stderr))
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
    }

    static func runAdministratorCommand(_ command: String) async -> ShellResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return await run("/usr/bin/osascript", ["-e", script])
    }

    static func cleanError(_ result: ShellResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "exit status \(result.status)" : stdout
    }
}
