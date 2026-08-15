import SwiftUI
import AppKit
import UserNotifications

final class MacVigilAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var manager: VigilManager?
    weak var updater: UpdateManager?
    weak var jobs: JobAwareController?
    weak var power: PowerIntelligenceController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor [weak self] in
            guard let self,
                  let manager = self.manager,
                  let updater = self.updater else { return }

            manager.loadPreferences()
            await manager.prepareOnLaunch()
            updater.startBackgroundMonitoring(isVigilActive: { [weak manager] in
                manager?.isActive ?? false
            })
            self.power?.startBackgroundMonitoring()

            // Build the first local Job Guard suggestion set without waiting
            // for the menu or Job Guard window to be opened.
            await self.jobs?.refreshProcesses()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    init() {
        let manager = VigilManager()
        let updater = UpdateManager()
        let jobs = JobAwareController(manager: manager)
        let power = PowerIntelligenceController(manager: manager)

        _manager = StateObject(wrappedValue: manager)
        _updater = StateObject(wrappedValue: updater)
        _jobs = StateObject(wrappedValue: jobs)
        _power = StateObject(wrappedValue: power)

        appDelegate.manager = manager
        appDelegate.updater = updater
        appDelegate.jobs = jobs
        appDelegate.power = power
    }

    var body: some Scene {
        MenuBarExtra {
            MacVigilRootView(manager: manager, updater: updater, jobs: jobs)
                .onAppear {
                    appDelegate.manager = manager
                    appDelegate.updater = updater
                    appDelegate.jobs = jobs
                    appDelegate.power = power
                }
        } label: {
            Image(systemName: updater.hasUpdate ? "arrow.down.circle.fill" : (manager.isActive ? "bolt.shield.fill" : "bolt.shield"))
                .accessibilityLabel(updater.hasUpdate ? "MacVigil update available" : "MacVigil")
        }
        .menuBarExtraStyle(.window)

        Window("Job Guard", id: "job-guard") {
            JobGuardWindowView(manager: manager, jobs: jobs)
                .onAppear {
                    appDelegate.manager = manager
                    appDelegate.updater = updater
                    appDelegate.jobs = jobs
                    appDelegate.power = power
                }
        }
        .defaultSize(width: 580, height: 680)
        .windowResizability(.contentSize)

        Window("Power Intelligence", id: "power-intelligence") {
            PowerIntelligenceView(manager: manager, power: power)
                .onAppear {
                    appDelegate.manager = manager
                    appDelegate.updater = updater
                    appDelegate.jobs = jobs
                    appDelegate.power = power
                }
        }
        .defaultSize(width: 520, height: 650)
        .windowResizability(.contentSize)
    }
}
