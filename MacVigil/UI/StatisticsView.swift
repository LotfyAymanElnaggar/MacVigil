import SwiftUI

struct StatisticsWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    var body: some View {
        ScrollView {
            StatisticsDashboardView(manager: manager, power: power)
                .padding(22)
        }
        .frame(width: 760, height: 650)
        .background(.ultraThinMaterial)
    }
}

struct StatisticsDashboardView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    private struct DayBucket: Identifiable {
        let date: Date
        let seconds: Int
        var id: Date { date }
    }

    private struct ModeBucket: Identifiable {
        let name: String
        let seconds: Int
        let count: Int
        var id: String { name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Statistics")
                        .font(.title2.weight(.bold))
                    Text("A local summary of recent Vigil sessions. No telemetry leaves your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isActive {
                    Label("ACTIVE · \(power.activeSessionElapsedText)", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                metricCard("Protected time", duration(totalSeconds), "clock.fill")
                metricCard("Sessions", "\(sessionCount)", "number.circle.fill")
                metricCard("Average", sessionCount > 0 ? duration(totalCompletedSeconds / sessionCount) : "—", "equal.circle.fill")
                metricCard("Longest", longestSeconds > 0 ? duration(longestSeconds) : "—", "arrow.up.right.circle.fill")
            }

            MVGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Last 7 days")
                            .font(.headline)
                        Spacer()
                        Text("from retained session history")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    weeklyBars
                }
            }

            HStack(alignment: .top, spacing: 12) {
                MVGlassCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Protection modes")
                            .font(.headline)
                        if modeBuckets.isEmpty {
                            emptyState("No completed sessions yet.")
                        } else {
                            ForEach(modeBuckets) { bucket in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(bucket.name)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(duration(bucket.seconds))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: modeShare(bucket))
                                    Text("\(bucket.count) session\(bucket.count == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                MVGlassCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Battery & thermal")
                            .font(.headline)
                        statLine("Power source", power.powerSourceText)
                        statLine("Battery", power.batteryPercent.map { "\($0)%" } ?? "Unavailable")
                        statLine("Thermal", power.thermalStatus)
                        statLine("Reserve", "\(manager.lowBatteryCutoff)%")
                        if let delta = averageBatteryDelta {
                            Divider()
                            statLine("Avg. recorded battery change", delta > 0 ? "+\(delta)%" : "\(delta)%")
                            Text("Battery change is observational only; charging and workload intensity can affect it.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            MVGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent sessions")
                            .font(.headline)
                        Spacer()
                        if !power.recentSessions.isEmpty {
                            Button("Clear History", role: .destructive) {
                                power.clearSessionHistory()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if power.recentSessions.isEmpty {
                        emptyState("Completed Vigil sessions will appear here.")
                    } else {
                        ForEach(Array(power.recentSessions.prefix(12))) { session in
                            HStack(spacing: 10) {
                                Image(systemName: icon(for: session.configuration))
                                    .frame(width: 24)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.configuration)
                                        .font(.subheadline.weight(.semibold))
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(duration(session.durationSeconds))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    Text(sessionBatteryText(session))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            if session.id != power.recentSessions.prefix(12).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricCard(_ title: String, _ value: String, _ icon: String) -> some View {
        MVGlassCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weeklyBars: some View {
        let buckets = dayBuckets
        let maximum = max(1, buckets.map(\.seconds).max() ?? 1)

        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(buckets) { bucket in
                VStack(spacing: 6) {
                    Text(bucket.seconds > 0 ? shortDuration(bucket.seconds) : "")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(bucket.seconds > 0 ? 0.75 : 0.12))
                        .frame(height: max(5, 100 * CGFloat(bucket.seconds) / CGFloat(maximum)))
                    Text(bucket.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 138, alignment: .bottom)
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
    }

    private var totalCompletedSeconds: Int {
        power.recentSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var totalSeconds: Int {
        totalCompletedSeconds + (manager.isActive ? power.activeSessionElapsedSeconds : 0)
    }

    private var sessionCount: Int {
        power.recentSessions.count
    }

    private var longestSeconds: Int {
        max(power.recentSessions.map(\.durationSeconds).max() ?? 0, manager.isActive ? power.activeSessionElapsedSeconds : 0)
    }

    private var averageBatteryDelta: Int? {
        let values = power.recentSessions.compactMap(\.batteryDelta)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private var dayBuckets: [DayBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let seconds = power.recentSessions
                .filter { $0.startedAt >= day && $0.startedAt < next }
                .reduce(0) { $0 + $1.durationSeconds }
            let active = manager.isActive,
                         let started = power.activeSessionStartedAt,
                         started >= day,
                         started < next
                ? power.activeSessionElapsedSeconds
                : 0
            return DayBucket(date: day, seconds: seconds + active)
        }
    }

    private var modeBuckets: [ModeBucket] {
        let grouped = Dictionary(grouping: power.recentSessions, by: \.configuration)
        return grouped.map { name, sessions in
            ModeBucket(
                name: name,
                seconds: sessions.reduce(0) { $0 + $1.durationSeconds },
                count: sessions.count
            )
        }
        .sorted { lhs, rhs in lhs.seconds > rhs.seconds }
        .prefix(4)
        .map { $0 }
    }

    private func modeShare(_ bucket: ModeBucket) -> Double {
        let total = max(1, totalCompletedSeconds)
        return Double(bucket.seconds) / Double(total)
    }

    private func duration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe < 60 { return "\(safe)s" }
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    private func shortDuration(_ seconds: Int) -> String {
        if seconds >= 3600 { return String(format: "%.1fh", Double(seconds) / 3600.0) }
        return "\(max(1, seconds / 60))m"
    }

    private func icon(for configuration: String) -> String {
        if configuration.localizedCaseInsensitiveContains("Closed") { return "leaf.fill" }
        if configuration.localizedCaseInsensitiveContains("Full") { return "bolt.fill" }
        if configuration.localizedCaseInsensitiveContains("Compute") { return "cpu.fill" }
        return "shield.fill"
    }

    private func sessionBatteryText(_ session: PowerIntelligenceController.SessionSummary) -> String {
        guard let start = session.startBattery, let end = session.endBattery else {
            return "Peak thermal: \(session.peakThermal)"
        }
        let delta = end - start
        let deltaText = delta > 0 ? "+\(delta)%" : "\(delta)%"
        return "Battery \(deltaText) · Peak \(session.peakThermal)"
    }
}
