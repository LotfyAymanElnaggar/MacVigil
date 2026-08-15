import SwiftUI
import AppKit

/// Keeps the two most important actions reachable with large, explicit hit
/// targets even when the menu-bar panel is crowded or the pointer is moving.
struct MacVigilInteractiveRootView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController
    @ObservedObject var power: PowerIntelligenceController

    @Environment(\.openWindow) private var openWindow
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 0) {
            MacVigilRootView(manager: manager, updater: updater, jobs: jobs)

            Divider()

            PowerIntelligenceBar(power: power)
                .background(.ultraThinMaterial)
        }
        .overlay(alignment: .bottom) {
            if manager.isActive || updater.hasUpdate {
                quickActions
                    .padding(.horizontal, 14)
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: manager.isActive)
        .animation(.easeOut(duration: 0.16), value: updater.hasUpdate)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            if manager.isActive {
                Button {
                    guard !isStopping else { return }
                    isStopping = true
                    Task {
                        await manager.stopLiveSession()
                        isStopping = false
                    }
                } label: {
                    Label(isStopping ? "Stopping…" : "Stop Vigil", systemImage: "stop.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .disabled(isStopping || updater.isInstalling)
                .help("Stop Vigil and restore normal macOS sleep behavior")
                .keyboardShortcut(".", modifiers: [.command])
            }

            if updater.hasUpdate {
                Button {
                    requestUpdate()
                } label: {
                    Label(updateButtonTitle, systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(updater.isInstalling || isStopping)
                .help(manager.isActive ? "Review stopping Vigil and installing the update" : "Download, verify, install, and restart MacVigil")
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 8, y: 3)
    }

    private var updateButtonTitle: String {
        if updater.isInstalling { return "Updating…" }
        if let version = updater.availableVersion { return "Update to \(version)" }
        return "Update Now"
    }

    private func requestUpdate() {
        if manager.isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "update-confirmation")
        } else {
            Task { await updater.installAvailableUpdate() }
        }
    }
}

/// A real macOS window is used for the stop-and-update decision. This avoids
/// relying on an alert attached to the transient MenuBarExtra window.
struct UpdateConfirmationWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Update MacVigil")
                        .font(.title2.weight(.semibold))
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if manager.isActive {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Vigil is currently active", systemImage: "bolt.shield.fill")
                        .font(.headline)
                    Text("Installing an update restarts MacVigil. The current Vigil session must stop first, so normal macOS sleep behavior is restored before the app is replaced.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text(manager.configurationName)
                        Spacer()
                        Text(remainingText)
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .padding(.top, 3)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let error = localError ?? updater.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if working || updater.isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(updater.statusText ?? (manager.isActive ? "Stopping Vigil…" : "Preparing update…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                beginUpdate()
            } label: {
                Label(primaryButtonTitle, systemImage: manager.isActive ? "stop.circle.fill" : "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working || updater.isInstalling)

            HStack(spacing: 10) {
                Button("View Release") {
                    updater.openReleasePage()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(manager.isActive ? "Keep Vigil Running" : "Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 470, height: manager.isActive ? 340 : 270)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var versionLine: String {
        if let version = updater.availableVersion {
            return "MacVigil \(updater.currentVersion) → \(version)"
        }
        return "Install the latest available release"
    }

    private var primaryButtonTitle: String {
        if working || updater.isInstalling { return "Updating…" }
        return manager.isActive ? "Stop Vigil & Update" : "Update Now"
    }

    private var remainingText: String {
        guard let remaining = manager.effectiveRemainingSeconds else { return "No timer" }
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds) }
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    private func beginUpdate() {
        guard !working else { return }
        working = true
        localError = nil

        Task {
            if manager.isActive {
                await manager.stopLiveSession()
                guard !manager.isActive else {
                    localError = "Vigil could not be stopped safely. The update was not started."
                    working = false
                    return
                }
            }

            await updater.installAvailableUpdate()

            // A successful install terminates the current app. If we are still
            // here and the updater reported an error, keep this normal window
            // open so the user can retry or open the release page.
            if let error = updater.lastError {
                localError = error
                working = false
            }
        }
    }
}
