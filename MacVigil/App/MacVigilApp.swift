import SwiftUI
import AppKit

final class MacVigilAppDelegate: NSObject, NSApplicationDelegate {
    weak var manager: VigilManager?

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
        _manager = StateObject(wrappedValue: manager)
        _updater = StateObject(wrappedValue: UpdateManager())
        _jobs = StateObject(wrappedValue: JobAwareController(manager: manager))
    }

    var body: some Scene {
        MenuBarExtra {
            PolishedMenuBarView(manager: manager, updater: updater, jobs: jobs)
                .onAppear {
                    appDelegate.manager = manager
                }
        } label: {
            Image(systemName: updater.hasUpdate ? "arrow.down.circle.fill" : (manager.isActive ? "bolt.shield.fill" : "bolt.shield"))
                .accessibilityLabel(updater.hasUpdate ? "MacVigil update available" : "MacVigil")
        }
        .menuBarExtraStyle(.window)
    }
}
