import SwiftUI
import AppKit

final class MacVigilAppDelegate: NSObject, NSApplicationDelegate {
    weak var manager: VigilManager?
    weak var updater: UpdateManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self,
                  let manager = self.manager,
                  let updater = self.updater else { return }

            manager.loadPreferences()
            await manager.prepareOnLaunch()
            updater.startBackgroundMonitoring(isVigilActive: { [weak manager] in
                manager?.isActive ?? false
            })
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.handleAppTermination()
    }
}

@main
struct MacVigilApp: App {
    @NSApplicationDelegateAdaptor(MacVigilAppDelegate.self) private var appDelegate
    @StateObject private var manager: VigilManager
    @StateObject private var updater: UpdateManager
    @StateObject private var jobs: JobAwareController

    init() {
        let manager = VigilManager()
        let updater = UpdateManager()

        _manager = StateObject(wrappedValue: manager)
        _updater = StateObject(wrappedValue: updater)
        _jobs = StateObject(wrappedValue: JobAwareController(manager: manager))

        appDelegate.manager = manager
        appDelegate.updater = updater
    }

    var body: some Scene {
        MenuBarExtra {
            MacVigilRootView(manager: manager, updater: updater, jobs: jobs)
                .onAppear {
                    appDelegate.manager = manager
                    appDelegate.updater = updater
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
                }
        }
        .defaultSize(width: 520, height: 560)
        .windowResizability(.contentSize)
    }
}
