import SwiftUI
import AppKit
import UserNotifications

final class MacVigilAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var manager: VigilManager?
    weak var updater: UpdateManager?
    weak var jobs: JobAwareController?
    weak var power: PowerIntelligenceController?
    weak var hotkeys: GlobalHotkeyManager?
    private var cliServer: CLIControlServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor [weak self] in
            guard let self,
                  let manager = self.manager,
                  let updater = self.updater else { return }

            manager.loadPreferences()
            await manager.prepareOnLaunch()
            updater.startBackgroundMonitoring(isVigilActive: { [weak manager] in
                guard let manager else { return false }
                return manager.isActive || manager.isLiveReconfiguring
            })
            self.power?.startBackgroundMonitoring()
            self.hotkeys?.start()
            await self.jobs?.refreshProcesses()

            if let jobs = self.jobs {
                let server = CLIControlServer(manager: manager, jobs: jobs)
                server.start()
                self.cliServer = server
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cliServer?.stop()
        hotkeys?.stop()
        manager?.handleAppTermination()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor [weak self] in
            self?.updater?.handleNotificationAction(action)
        }
        completionHandler()
    }
}

@main
struct MacVigilApp: App {
    @NSApplicationDelegateAdaptor(MacVigilAppDelegate.self) private var appDelegate
    @StateObject private var manager: VigilManager
    @StateObject private var updater: UpdateManager
    @StateObject private var jobs: JobAwareController
    @StateObject private var power: PowerIntelligenceController
    @StateObject private var hotkeys: GlobalHotkeyManager

    init() {
        let manager = VigilManager()
        let updater = UpdateManager()
        let jobs = JobAwareController(manager: manager)
        let power = PowerIntelligenceController(manager: manager)
        let hotkeys = GlobalHotkeyManager(manager: manager)

        _manager = StateObject(wrappedValue: manager)
        _updater = StateObject(wrappedValue: updater)
        _jobs = StateObject(wrappedValue: jobs)
        _power = StateObject(wrappedValue: power)
        _hotkeys = StateObject(wrappedValue: hotkeys)

        appDelegate.manager = manager
        appDelegate.updater = updater
        appDelegate.jobs = jobs
        appDelegate.power = power
        appDelegate.hotkeys = hotkeys
    }

    var body: some Scene {
        MenuBarExtra {
            LiquidGlassMenuView(
                manager: manager,
                updater: updater,
                jobs: jobs,
                power: power,
                hotkeys: hotkeys
            )
            .onAppear { refreshDelegateReferences() }
        } label: {
            Image(systemName: updater.hasUpdate ? "arrow.down.circle.fill" : (manager.isActive ? "bolt.shield.fill" : "bolt.shield"))
                .accessibilityLabel(updater.hasUpdate ? "MacVigil update available" : "MacVigil")
        }
        .menuBarExtraStyle(.window)

        Window("MacVigil Settings", id: "settings") {
            MacVigilSettingsContainer(
                manager: manager,
                updater: updater,
                jobs: jobs,
                power: power,
                hotkeys: hotkeys
            )
            .onAppear { refreshDelegateReferences() }
        }
        .defaultSize(width: 930, height: 680)
        .windowResizability(.contentSize)

        Window("MacVigil Statistics", id: "statistics") {
            StatisticsWindowView(manager: manager, power: power)
                .onAppear { refreshDelegateReferences() }
        }
        .defaultSize(width: 760, height: 650)
        .windowResizability(.contentSize)

        Window("Job Guard", id: "job-guard") {
            ReliableJobGuardWindowView(manager: manager, updater: updater, jobs: jobs)
                .onAppear { refreshDelegateReferences() }
        }
        .defaultSize(width: 650, height: 740)
        .windowResizability(.contentSize)

        Window("Power Intelligence", id: "power-intelligence") {
            PowerIntelligenceView(manager: manager, power: power)
                .onAppear { refreshDelegateReferences() }
        }
        .defaultSize(width: 520, height: 650)
        .windowResizability(.contentSize)

        Window("Update MacVigil", id: "update-confirmation") {
            UpdateConfirmationWindowView(manager: manager, updater: updater)
                .onAppear { refreshDelegateReferences() }
        }
        .defaultSize(width: 470, height: 350)
        .windowResizability(.contentSize)
    }

    private func refreshDelegateReferences() {
        appDelegate.manager = manager
        appDelegate.updater = updater
        appDelegate.jobs = jobs
        appDelegate.power = power
        appDelegate.hotkeys = hotkeys
    }
}
