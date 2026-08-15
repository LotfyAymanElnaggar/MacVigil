import SwiftUI

struct StatisticsWindowView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    var body: some View {
        ScrollView {
            StatisticsDashboardView(manager: manager, power: power)
                .padding(22)
        }
        .frame(width: 820, height: 700)
    }
}

struct StatisticsDashboardView: View {
    @ObservedObject var manager: VigilManager
    @ObservedObject var power: PowerIntelligenceController

    private enum TimeRange: String, CaseIterable, Identifiable {
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case all = "All"

        var id: String { rawValue }
        var dayCount: Int? {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .all: return nil
            }
        }
    }

    private struct DayBucket: Identifiable {
        let date: Date
        let seconds: Int
        var id: Date { date }
    }

    private struct NamedBucket: Identifiable {
        let name: String
        let seconds: Int
        let count: Int
        var id: String { name }
    }

    @State private var timeRange: TimeRange = .sevenDays
    @State private var modeFilter = "All modes"
    @State private var ownerFilter = "All owners"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            filters

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                metricCard("Protected time", duration(totalSeconds), "clock.fill")
                metricCard("Sessions", "\(filteredSessions.count)", "number.circle.fill")
                metricCard("Average", filteredSessions.isEmpty ? "—" : duration(totalCompletedSeconds / filteredSessions.count), "equal.circle.fill")
                metricCard("Longest", longestSeconds > 0 ? duration(longestSeconds) : "—", "arrow.up.right.circle.fill")
            }

            GroupBox("Activity") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(activityCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    activityBars
                }
                .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("Protection modes") {
                    bucketList(modeBuckets, empty: "No matching completed sessions.")
                }
                .frame(maxWidth: .infinity)

                GroupBox("Session owners") {
                    bucketList(ownerBuckets, empty: "No matching completed sessions.")
                }
                .frame(maxWidth: .infinity)

                GroupBox("Battery & thermal") {
                    VStack(alignment: .leading, spacing: 9) {
                        statLine("Power source", power.powerSourceText)
                        statLine("Battery", power.batteryPercent.map { "\($0)%" } ?? "Unavailable")
                        statLine("Thermal", power.thermalStatus)
                        statLine("Reserve", "\(manager.lowBatteryCutoff)%")
                        if let delta = averageBatteryDelta {
                            Divider()
                            statLine("Avg. battery change", delta > 0 ? "+\(delta)%" : "\(delta)%")
                        }
                        Text("Battery change is observational only. Charging state and workload intensity also affect it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent sessions")
                            .font(.headline)
                        Spacer()
                        Button("Export CSV") { power.exportSessionHistoryCSV() }
                            .buttonStyle(.bordered)
                            .disabled(power.recentSessions.isEmpty)
                        if !power.recentSessions.isEmpty {
                            Button("Clear History", role: .destructive) {
                                power.clearSessionHistory()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if filteredSessions.isEmpty {
                        emptyState("No sessions match the current filters.")
                    } else {
                        ForEach(Array(filteredSessions.prefix(20))) { session in
                            sessionRow(session)
                            if session.id != filteredSessions.prefix(20).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            if let status = power.statusText {
                Label(status, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Statistics")
                    .font(.title2.weight(.semibold))
                Text("Local Vigil history. Nothing is uploaded as statistics telemetry.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if manager.isActive {
                Label("\(power.activeSessionOwnerLabel) · \(power.activeSessionElapsedText)", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Range", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 235)

            Picker("Mode", selection: $modeFilter) {
                ForEach(modeOptions, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 180)

            Picker("Owner", selection: $ownerFilter) {
                ForEach(ownerOptions, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 150)

            Spacer()
            Text("\(power.recentSessions.count) stored")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ icon: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activityBars: some View {
        let buckets = dayBuckets
        let maximum = max(1, buckets.map(\.seconds).max() ?? 1)

        return HStack(alignment: .bottom, spacing: buckets.count > 14 ? 3 : 9) {
            ForEach(buckets) { bucket in
                VStack(spacing: 5) {
                    if buckets.count <= 10 {
                        Text(bucket.seconds > 0 ? shortDuration(bucket.seconds) : "")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(height: 14)
                    }
                    RoundedRectangle(cornerRadius: buckets.count > 14 ? 2 : 5, style: .continuous)
                        .fill(Color.accentColor.opacity(bucket.seconds > 0 ? 0.72 : 0.10))
                        .frame(height: max(4, 100 * CGFloat(bucket.seconds) / CGFloat(maximum)))
                    if buckets.count <= 10 || Calendar.current.component(.day, from: bucket.date) % 5 == 0 {
                        Text(bucket.date.formatted(buckets.count <= 10 ? .dateTime.weekday(.narrow) : .dateTime.day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 142, alignment: .bottom)
    }

    @ViewBuilder
    private func bucketList(_ buckets: [NamedBucket], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if buckets.isEmpty {
                emptyState(empty)
            } else {
                ForEach(buckets.prefix(5)) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bucket.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(duration(bucket.seconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: bucketShare(bucket))
                        Text("\(bucket.count) session\(bucket.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func sessionRow(_ session: PowerIntelligenceController.SessionSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: session.configuration))
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.configuration)
                        .font(.subheadline.weight(.semibold))
                    Text(session.ownerLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
    }

    private var modeOptions: [String] {
        ["All modes"] + Array(Set(power.recentSessions.map(\.configuration))).sorted()
    }

    private var ownerOptions: [String] {
        ["All owners"] + Array(Set(power.recentSessions.map(\.ownerLabel))).sorted()
    }

    private var rangeSessions: [PowerIntelligenceController.SessionSummary] {
        guard let days = timeRange.dayCount,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return power.recentSessions
        }
        return power.recentSessions.filter { $0.startedAt >= cutoff }
    }

    private var filteredSessions: [PowerIntelligenceController.SessionSummary] {
        rangeSessions.filter { session in
            (modeFilter == "All modes" || session.configuration == modeFilter) &&
            (ownerFilter == "All owners" || session.ownerLabel == ownerFilter)
        }
    }

    private var activeMatchesFilters: Bool {
        guard manager.isActive else { return false }
        return (modeFilter == "All modes" || manager.configurationName == modeFilter) &&
               (ownerFilter == "All owners" || power.activeSessionOwnerLabel == ownerFilter)
    }

    private var totalCompletedSeconds: Int {
        filteredSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var totalSeconds: Int {
        totalCompletedSeconds + (activeMatchesFilters ? power.activeSessionElapsedSeconds : 0)
    }

    private var longestSeconds: Int {
        max(filteredSessions.map(\.durationSeconds).max() ?? 0, activeMatchesFilters ? power.activeSessionElapsedSeconds : 0)
    }

    private var averageBatteryDelta: Int? {
        let values = filteredSessions.compactMap(\.batteryDelta)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private var activityCaption: String {
        switch timeRange {
        case .sevenDays: return "Protected time by day for the last week."
        case .thirtyDays: return "Protected time by day for the last 30 days."
        case .all: return "The most recent 30 days are charted; summary metrics use all retained history."
        }
    }

    private var dayBuckets: [DayBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let count = timeRange == .sevenDays ? 7 : 30

        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
            let seconds = filteredSessions
                .filter { $0.startedAt >= day && $0.startedAt < next }
                .reduce(0) { $0 + $1.durationSeconds }

            let activeSeconds: Int
            if activeMatchesFilters,
               let started = power.activeSessionStartedAt,
               started >= day,
               started < next {
                activeSeconds = power.activeSessionElapsedSeconds
            } else {
                activeSeconds = 0
            }

            return DayBucket(date: day, seconds: seconds + activeSeconds)
        }
    }

    private var modeBuckets: [NamedBucket] {
        buckets(grouping: filteredSessions, key: \.configuration)
    }

    private var ownerBuckets: [NamedBucket] {
        buckets(grouping: filteredSessions, key: \.ownerLabel)
    }

    private func buckets(
        grouping sessions: [PowerIntelligenceController.SessionSummary],
        key: KeyPath<PowerIntelligenceController.SessionSummary, String>
    ) -> [NamedBucket] {
        let grouped = Dictionary(grouping: sessions) { $0[keyPath: key] }
        return grouped.map { name, values in
            NamedBucket(name: name, seconds: values.reduce(0) { $0 + $1.durationSeconds }, count: values.count)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private func bucketShare(_ bucket: NamedBucket) -> Double {
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
