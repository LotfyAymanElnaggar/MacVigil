import SwiftUI
import AppKit

struct PowerIntelligenceView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if power.thermalWarningActive {
                    warningCard
                }

                currentPowerCard
                closedLidPolicyCard

                if manager.isActive {
                    activeSessionCard
                }

                recentSessionsCard
                benchmarkCard

                if let status = power.statusText {
                    Label(status, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(minHeight: 610)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task { await power.sampleNow() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Label("Power Intelligence", systemImage: "bolt.heart.fill")
                    .font(.title3.weight(.semibold))
                Text("Battery, thermal pressure, and recent Vigil sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(power.thermalStatus == "Critical" ? Color.red : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Thermal pressure: \(power.thermalStatus)")
                    .font(.subheadline.weight(.semibold))
                Text("Check ventilation and workload intensity. macOS remains in control of mandatory thermal safety behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var currentPowerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Current power state", systemImage: "battery.75percent")
                .font(.headline)

            metricRow("Power source", power.powerSourceText)
            metricRow("Battery", power.batteryPercent.map { "\($0)%" } ?? "Unknown")
            metricRow("Battery reserve", "\(manager.lowBatteryCutoff)%")
            metricRow("Estimated reserve", power.estimatedReserveText)
            metricRow("Thermal pressure", power.thermalStatus)

            if let sampled = power.lastSampleAt {
                Text("Updated \(sampled.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var closedLidPolicyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Closed-lid power policy", systemImage: "powerplug")
                .font(.headline)

            Toggle(
                "Require external power",
                isOn: Binding(
                    get: { power.requireExternalPowerForClosedLid },
                    set: { power.setRequireExternalPowerForClosedLid($0) }
                )
            )
            .toggleStyle(.switch)

            Text("When enabled, MacVigil will stop an active closed-lid Vigil if the Mac switches to battery power. This is useful for sustained builds, local AI, and other hot workloads you only want to run closed-lid while plugged in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activeSessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Current Vigil session", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("ACTIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
            }

            metricRow("Configuration", manager.configurationName)
            metricRow("Elapsed", power.activeSessionElapsedText)
            metricRow("Starting battery", power.activeSessionStartBattery.map { "\($0)%" } ?? "Unknown")
            metricRow("Current battery", power.batteryPercent.map { "\($0)%" } ?? "Unknown")
            metricRow("Peak thermal", power.activeSessionPeakThermal)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.07))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent sessions", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !power.recentSessions.isEmpty {
                    Button("Clear") { power.clearSessionHistory() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            if power.recentSessions.isEmpty {
                Text("Completed Vigil sessions will appear here with duration, battery change, and peak thermal pressure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(power.recentSessions.prefix(6))) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.configuration)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(PowerIntelligenceController.durationText(session.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                            if let delta = session.batteryDelta {
                                Text("Battery \(delta > 0 ? "+" : "")\(delta)%")
                            }
                            Text("Peak \(session.peakThermal)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if session.id != power.recentSessions.prefix(6).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var benchmarkCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Repeatable power benchmarks")
                    .font(.subheadline.weight(.semibold))
                Text("Use the repository benchmark harness to compare equivalent configurations without turning estimates into marketing claims.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Guide") {
                if let url = URL(string: "https://github.com/LotfyAymanElnaggar/MacVigil/blob/main/docs/POWER-BENCHMARKS.md") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}
