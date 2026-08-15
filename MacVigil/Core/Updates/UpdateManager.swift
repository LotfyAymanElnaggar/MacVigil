import Foundation
import Combine
import CryptoKit
import AppKit
import UserNotifications

@MainActor
final class UpdateManager: ObservableObject {
    @Published var automaticChecksEnabled: Bool
    @Published var automaticInstallEnabled: Bool
    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusText: String?
    @Published private(set) var lastError: String?

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let downloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case digest
        }
    }

    private let automaticChecksKey = "MacVigil.update.automaticChecks"
    private let automaticInstallKey = "MacVigil.update.automaticInstall"
    private let lastNotifiedVersionKey = "MacVigil.update.lastNotifiedVersion"
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/LotfyAymanElnaggar/MacVigil/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/releases/latest")!

    private var availableAsset: Asset?
    private var releasePageURL: URL?
    private var periodicTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        automaticChecksEnabled = defaults.object(forKey: automaticChecksKey) == nil
            ? true
            : defaults.bool(forKey: automaticChecksKey)
        automaticInstallEnabled = defaults.bool(forKey: automaticInstallKey)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var hasUpdate: Bool { availableVersion != nil }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(automaticChecksEnabled, forKey: automaticChecksKey)
        defaults.set(automaticInstallEnabled, forKey: automaticInstallKey)
    }

    func startPeriodicChecks() {
        periodicTimer?.invalidate()
        guard automaticChecksEnabled else { return }

        periodicTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.automaticChecksEnabled else { return }
                await self.checkForUpdates(userInitiated: false)
            }
        }
        periodicTimer?.tolerance = 5 * 60
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        lastError = nil
        if userInitiated { statusText = "Checking GitHub…" }
        defer { isChecking = false }

        do {
            var request = URLRequest(url: latestReleaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacVigil/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            guard Self.isVersion(version, newerThan: currentVersion) else {
                availableVersion = nil
                availableAsset = nil
                releasePageURL = release.htmlURL
                statusText = userInitiated ? "MacVigil \(currentVersion) is up to date." : nil
                return
            }

            guard let asset = release.assets.first(where: {
                $0.name.hasPrefix("MacVigil-") && $0.name.hasSuffix(".dmg")
            }) else {
                throw UpdateError.missingDMG
            }

            availableVersion = version
            availableAsset = asset
            releasePageURL = release.htmlURL
            statusText = "MacVigil \(version) is available."
            await notifyIfNeeded(version: version)
        } catch {
            if userInitiated {
                lastError = "Could not check for updates: \(error.localizedDescription)"
                statusText = nil
            }
        }
    }

    func installAvailableUpdate() async {
        guard !isInstalling else { return }
        guard let version = availableVersion,
              let asset = availableAsset else {
            await checkForUpdates(userInitiated: true)
            guard availableVersion != nil, availableAsset != nil else { return }
            await installAvailableUpdate()
            return
        }

        guard let digest = normalizedSHA256(asset.digest) else {
            lastError = "Automatic installation is unavailable because this release has no SHA-256 asset digest. Open the release and update manually."
            openReleasePage()
            return
        }

        isInstalling = true
        lastError = nil
        statusText = "Downloading MacVigil \(version)…"
        defer { isInstalling = false }

        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("MacVigilUpdate-\(UUID().uuidString)", isDirectory: true)
        let dmgURL = workspace.appendingPathComponent("MacVigil-\(version).dmg")
        let mountURL = workspace.appendingPathComponent("mount", isDirectory: true)
        let stagedAppURL = workspace.appendingPathComponent("MacVigil.app", isDirectory: true)

        do {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)

            var request = URLRequest(url: asset.downloadURL)
            request.setValue("MacVigil/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.invalidResponse
            }
            try fileManager.moveItem(at: temporaryURL, to: dmgURL)

            statusText = "Verifying download…"
            let data = try Data(contentsOf: dmgURL, options: .mappedIfSafe)
            let actualDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actualDigest.caseInsensitiveCompare(digest) == .orderedSame else {
                throw UpdateError.digestMismatch
            }

            statusText = "Preparing update…"
            let attach = await ShellRunner.run("/usr/bin/hdiutil", [
                "attach", dmgURL.path,
                "-nobrowse", "-readonly",
                "-mountpoint", mountURL.path
            ])
            guard attach.succeeded else { throw UpdateError.mountFailed }
            defer {
                Task { _ = await ShellRunner.run("/usr/bin/hdiutil", ["detach", mountURL.path, "-force"]) }
            }

            let mountedAppURL = mountURL.appendingPathComponent("MacVigil.app", isDirectory: true)
            guard fileManager.fileExists(atPath: mountedAppURL.path) else {
                throw UpdateError.invalidPackage
            }

            let mountedBundle = Bundle(url: mountedAppURL)
            let mountedVersion = mountedBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard mountedVersion == version else { throw UpdateError.versionMismatch }

            let copy = await ShellRunner.run("/usr/bin/ditto", [mountedAppURL.path, stagedAppURL.path])
            guard copy.succeeded else { throw UpdateError.stagingFailed }

            _ = await ShellRunner.run("/usr/bin/hdiutil", ["detach", mountURL.path, "-force"])

            let targetURL = Bundle.main.bundleURL.standardizedFileURL
            guard targetURL.pathExtension == "app" else { throw UpdateError.invalidInstallLocation }
            let parentURL = targetURL.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: parentURL.path) else {
                lastError = "MacVigil cannot replace the app at this location automatically. The release page has been opened so you can drag the new version into Applications."
                openReleasePage()
                return
            }

            try writeInstallerScript(
                workspace: workspace,
                stagedApp: stagedAppURL,
                targetApp: targetURL,
                parentPID: getpid()
            )

            statusText = "Update verified. Restarting MacVigil…"
            let scriptURL = workspace.appendingPathComponent("install-update.sh")
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            helper.arguments = ["/bin/sh", scriptURL.path]
            helper.standardInput = FileHandle.nullDevice
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try helper.run()

            try? await Task.sleep(nanoseconds: 250_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            lastError = "Update failed: \(error.localizedDescription)"
            statusText = nil
            try? fileManager.removeItem(at: workspace)
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releasePageURL ?? releasesPage)
    }

    private func notifyIfNeeded(version: String) async {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastNotifiedVersionKey) != version else { return }

        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "MacVigil \(version) is available"
            content.body = automaticInstallEnabled
                ? "It will install automatically when MacVigil is idle."
                : "Open MacVigil to update when you're ready."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "macvigil-update-\(version)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
            defaults.set(version, forKey: lastNotifiedVersionKey)
        } catch {
            // Update discovery must never fail because notification permission
            // was denied or local notification delivery was unavailable.
        }
    }

    private func normalizedSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let value = digest.lowercased().replacingOccurrences(of: "sha256:", with: "")
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return value
    }

    private func writeInstallerScript(
        workspace: URL,
        stagedApp: URL,
        targetApp: URL,
        parentPID: Int32
    ) throws {
        let scriptURL = workspace.appendingPathComponent("install-update.sh")
        let target = shellQuote(targetApp.path)
        let source = shellQuote(stagedApp.path)
        let work = shellQuote(workspace.path)
        let backup = shellQuote(targetApp.path + ".macvigil-backup")

        let script = """
        #!/bin/sh
        set -u
        while /bin/kill -0 \(parentPID) 2>/dev/null; do /bin/sleep 0.25; done
        /bin/rm -rf \(backup)
        if ! /bin/mv \(target) \(backup); then
          /usr/bin/open \(source)
          exit 1
        fi
        if /usr/bin/ditto \(source) \(target); then
          /bin/rm -rf \(backup)
          /usr/bin/open \(target)
          /bin/sleep 1
          /bin/rm -rf \(work)
          exit 0
        fi
        /bin/rm -rf \(target)
        /bin/mv \(backup) \(target)
        /usr/bin/open \(target)
        exit 1
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let count = max(lhs.count, rhs.count)

        for index in 0..<count {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case missingDMG
        case digestMismatch
        case mountFailed
        case invalidPackage
        case versionMismatch
        case stagingFailed
        case invalidInstallLocation

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "GitHub returned an invalid response."
            case .missingDMG: return "The GitHub release does not contain a MacVigil DMG."
            case .digestMismatch: return "The downloaded DMG did not match GitHub's SHA-256 digest."
            case .mountFailed: return "The downloaded DMG could not be mounted."
            case .invalidPackage: return "The DMG does not contain MacVigil.app."
            case .versionMismatch: return "The app inside the DMG does not match the advertised release version."
            case .stagingFailed: return "The new app could not be staged for installation."
            case .invalidInstallLocation: return "MacVigil is not running from an app bundle that can be updated."
            }
        }
    }
}
