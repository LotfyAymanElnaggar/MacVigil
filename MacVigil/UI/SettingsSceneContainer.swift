import SwiftUI

struct MacVigilSettingsContainer: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController
    @ObservedObject var hotkeys: GlobalHotkeyManager

    @StateObject private var cliInstaller = CLIInstallManager()

    var body: some View {
        MacVigilSettingsView(
            manager: manager,
            updater: updater,
            jobs: jobs,
            power: power,
            hotkeys: hotkeys
        )
        .toolbar {
            ToolbarItem {
                Menu {
                    Section("Command line") {
                        LabeledContent("Status") {
                            Text(cliInstaller.installed ? "Installed" : "Not installed")
                        }
                        LabeledContent("Path") {
                            Text(cliInstaller.installPath)
                                .font(.caption.monospaced())
                        }
                    }

                    if cliInstaller.installed {
                        Button("Remove macvigil CLI", role: .destructive) {
                            Task { await cliInstaller.remove() }
                        }
                        .disabled(cliInstaller.isWorking)
                    } else {
                        Button("Install macvigil CLI") {
                            Task { await cliInstaller.install() }
                        }
                        .disabled(cliInstaller.isWorking)
                    }

                    if let error = cliInstaller.lastError {
                        Divider()
                        Text(error)
                    } else if let status = cliInstaller.statusText {
                        Divider()
                        Text(status)
                    }
                } label: {
                    Label(cliInstaller.installed ? "CLI Installed" : "CLI", systemImage: "terminal")
                }
                .help("Install or remove the macvigil command-line client")
            }
        }
        .onAppear { cliInstaller.refresh() }
    }
}
