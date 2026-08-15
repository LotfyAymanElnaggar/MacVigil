import Foundation
import Combine

@MainActor
final class CLIInstallManager: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var isWorking = false
    @Published private(set) var statusText: String?
    @Published private(set) var lastError: String?

    let installPath = "/usr/local/bin/macvigil"

    var bundledCLIPath: String? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("macvigil", isDirectory: false)
            .path
    }

    func refresh() {
        lastError = nil
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: installPath) else {
            installed = false
            return
        }
        installed = normalized(target) == normalized(bundledCLIPath ?? "")
        if FileManager.default.fileExists(atPath: installPath) && !installed {
            statusText = "A different macvigil command already exists at \(installPath)."
        }
    }

    func install() async {
        guard !isWorking else { return }
        lastError = nil
        statusText = nil

        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            lastError = "Move MacVigil to Applications before installing the CLI so the command does not point to a temporary DMG path."
            return
        }
        guard let source = bundledCLIPath, FileManager.default.isExecutableFile(atPath: source) else {
            lastError = "The bundled macvigil executable is missing. Reinstall MacVigil from the release DMG."
            return
        }

        if FileManager.default.fileExists(atPath: installPath),
           (try? FileManager.default.destinationOfSymbolicLink(atPath: installPath)) == nil {
            lastError = "Refusing to replace \(installPath) because it is not a symbolic link."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let command = "/bin/mkdir -p /usr/local/bin && /bin/ln -sf \(shellQuote(source)) \(shellQuote(installPath))"
        let result = await ShellRunner.runAdministratorCommand(command)
        refresh()

        if result.succeeded && installed {
            statusText = "Installed macvigil at \(installPath)."
        } else {
            lastError = "Could not install the CLI. \(ShellRunner.cleanError(result))"
        }
    }

    func remove() async {
        guard !isWorking else { return }
        lastError = nil
        statusText = nil

        guard FileManager.default.fileExists(atPath: installPath) else {
            installed = false
            statusText = "The CLI is not installed."
            return
        }
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: installPath),
              normalized(target).contains("MacVigil.app/Contents/MacOS/macvigil") else {
            lastError = "Refusing to remove \(installPath) because it does not point to a MacVigil app bundle."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let result = await ShellRunner.runAdministratorCommand("/bin/rm -f \(shellQuote(installPath))")
        refresh()
        if result.succeeded && !FileManager.default.fileExists(atPath: installPath) {
            installed = false
            statusText = "Removed \(installPath)."
        } else {
            lastError = "Could not remove the CLI. \(ShellRunner.cleanError(result))"
        }
    }

    private func normalized(_ path: String) -> String {
        NSString(string: path).standardizingPath
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
