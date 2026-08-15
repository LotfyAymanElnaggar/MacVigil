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

    init() {
        let manager = VigilManager()
        _manager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            LiveMenuBarView(manager: manager)
                .onAppear {
                    appDelegate.manager = manager
                }
        } label: {
            Image(systemName: manager.isActive ? "bolt.shield.fill" : "bolt.shield")
                .accessibilityLabel("MacVigil")
        }
        .menuBarExtraStyle(.window)
    }
}
