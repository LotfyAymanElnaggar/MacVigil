import SwiftUI
import AppKit

struct MacVigilRootView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var updater: UpdateManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            PolishedMenuBarView(manager: manager, updater: updater)

            Divider()

            jobGuardBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .frame(width: 448, height: 782)
        .onChange(of: manager.isActive) { active in
            if !active {
                jobs.handleVigilStoppedExternally()
            }
        }
    }

    private var jobGuardBar: some View {
        HStack(spacing: 10) {
            Image(systemName: jobs.isWatching ? "briefcase.fill" : "briefcase")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(jobs.isWatching ? Color.accentColor : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(jobs.isWatching ? "Job Guard active" : "Job Guard")
                    .font(.caption.weight(.semibold))

                Text(jobs.isWatching ? jobs.displayStatus : (jobs.lastResult ?? "Keep Vigil active until a PID or command finishes."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(jobs.isWatching ? "Manage" : "Configure") {
                openJobGuard()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Job Guard in a dedicated window")
        }
        .contentShape(Rectangle())
        .onTapGesture { openJobGuard() }
    }

    private func openJobGuard() {
        // Job Guard intentionally lives in its own regular window. Presenting
        // text fields as a sheet from a MenuBarExtra window can lose key focus
        // and dismiss immediately on some macOS versions.
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "job-guard")
    }
}

struct JobGuardWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var jobs: JobAwareController

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var hoveringPID = false
    @State private var hoveringCommand = false

    private enum Field: Hashable {
        case pid
        case command
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Job Guard", systemImage: "briefcase.fill")
                            .font(.title3.weight(.semibold))
                        Text("Protect the work until the work is done.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                }

                if jobs.isWatching {
                    activeJobCard
                } else {
                    watchPIDCard
                    runCommandCard
                }

                if let error = jobs.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let status = jobs.statusText {
                    Label(status, systemImage: jobs.isWatching ? "bolt.shield.fill" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Starting Job Guard changes the active duration to ‘until the job finishes’. Your selected timer is restored as the preference after Job Guard ends. Mode and protection options can still be changed live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(minHeight: 520)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var activeJobCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Watching now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(jobs.displayStatus)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("ACTIVE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14))
                    .foregroundStyle(Color.green)
                    .clipShape(Capsule())
            }

            HStack {
                if jobs.logURL != nil {
                    Button("Open Log") { jobs.openLog() }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Button("Detach") {
                    jobs.detach()
                }
                .buttonStyle(.bordered)
                .help("Stop watching this job but leave the current Vigil session running")
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var watchPIDCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Watch a running process", systemImage: "number")
                .font(.headline)

            Text("Enter a PID. MacVigil will keep Vigil active until that process exits, then release protection automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("PID, for example 43127", text: $jobs.pidText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .pid)
                    .onSubmit {
                        guard !jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Task { await jobs.watchPID() }
                    }

                Button("Watch PID") {
                    Task { await jobs.watchPID() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobs.pidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(hoveringPID ? 0.05 : 0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(hoveringPID ? 0.35 : 0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hoveringPID = value }
        }
    }

    private var runCommandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Run a command", systemImage: "terminal")
                .font(.headline)

            Text("Run a non-interactive shell command from your home directory. Output is captured to a log. Vigil ends when the command exits.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("npm test  ·  python train.py  ·  make build", text: $jobs.commandText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .command)
                .onSubmit {
                    guard !jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await jobs.runCommand() }
                }

            HStack {
                Text("Runs with /bin/zsh -lc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Run with Vigil") {
                    Task { await jobs.runCommand() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobs.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(hoveringCommand ? 0.05 : 0.025))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(hoveringCommand ? 0.35 : 0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hoveringCommand = value }
        }
    }
}
