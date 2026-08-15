import Foundation
import Combine
import AppKit
import UserNotifications

@MainActor
final class PowerIntelligenceController: ObservableObject {
    struct SessionSummary: Identifiable, Codable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        let durationSeconds: Int
        let configuration: String
        let startBattery: Int?
        let endBattery: Int?
        let peakThermal: String

        var batteryDelta: Int? {
            guard let startBattery, let endBattery else { return nil }
            return endBattery - startBattery
        }
    }

    @Published private(set) var batteryPercent: Int?
    @Published private(set) var onBatteryPower = false
    @Published private(set) var powerSourceText = "Checking…"
    @Published private(set) var thermalStatus = "Nominal"
    @Published private(set) var estimatedMinutesToReserve: Int?
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var statusText: String?
    @Published private(set) var thermalWarningActive = false

    @Published private(set) var activeSessionStartedAt: Date?
    @Published private(set) var activeSessionStartBattery: Int?
    @Published private(set) var activeSessionPeakThermal = "Nominal"
    @Published private(set) var activeSessionElapsedSeconds = 0
    @Published private(set) var recentSessions: [SessionSummary] = []

    @Published var requireExternalPowerForClosedLid: Bool

    private let manager: VigilManager
    private let externalPowerOnlyKey = "MacVigil.power.requireExternalPowerForClosedLid"
    private let sessionHistoryKey = "MacVigil.power.sessionHistory"

    private var monitoringStarted = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastManagerActive = false
    private var activeSessionConfiguration = ""
    private var activePeakThermalRank = 0
    private var lastWarnedThermalRank = 0
    private var policyStopInFlight = false

    init(manager: VigilManager) {
        self.manager = manager
        let defaults = UserDefaults.standard
        requireExternalPowerForClosedLid = defaults.bool(forKey: externalPowerOnlyKey)

        if let data = defaults.data(forKey: sessionHistoryKey),
           let decoded = try? JSONDecoder().decode([SessionSummary].self, from: data) {
            recentSessions = decoded
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    var estimatedReserveText: String {
        if !onBatteryPower { return "On power adapter" }
        guard let batteryPercent else { return "Battery unavailable" }
        if batteryPercent <= manager.lowBatteryCutoff { return "At reserve" }
        guard let estimatedMinutesToReserve else { return "Calculating…" }
        return "~\(Self.durationText(estimatedMinutesToReserve * 60)) to \(manager.lowBatteryCutoff)%"
    }

    var activeSessionElapsedText: String {
        Self.durationText(activeSessionElapsedSeconds)
    }

    func startBackgroundMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true
        prepareNotificationAuthorization()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sampleNow()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sampleNow()
            }
        }
        timer?.tolerance = 0.5

        Task { @MainActor [weak self] in
            await self?.sampleNow()
        }
    }

    func setRequireExternalPowerForClosedLid(_ enabled: Bool) {
        requireExternalPowerForClosedLid = enabled
        UserDefaults.standard.set(enabled, forKey: externalPowerOnlyKey)
        statusText = enabled
            ? "Closed-lid protection will stop if the Mac switches to battery power."
            : "Closed-lid protection may continue on battery, subject to the battery reserve."

        if enabled {
            Task { @MainActor [weak self] in
                await self?.sampleNow()
            }
        }
    }

    func clearSessionHistory() {
        recentSessions = []
        UserDefaults.standard.removeObject(forKey: sessionHistoryKey)
        statusText = "Session history cleared."
    }

    func sampleNow() async {
        let batteryResult = await ShellRunner.run("/usr/bin/pmset", ["-g", "batt"])
        updateBatteryState(from: batteryResult.stdout)
        updateThermalState()
        updateSessionState()
        lastSampleAt = Date()
        await enforceExternalPowerPolicyIfNeeded()
    }

    private func updateBatteryState(from text: String) {
        onBatteryPower = text.localizedCaseInsensitiveContains("Battery Power")
        powerSourceText = onBatteryPower ? "Battery" : "Power adapter"
        batteryPercent = Self.firstIntegerMatch(pattern: #"\b(\d{1,3})%"#, text: text)

        guard onBatteryPower,
              let batteryPercent,
              batteryPercent > manager.lowBatteryCutoff,
              let minutesToEmpty = Self.remainingMinutes(from: text),
              batteryPercent > 0 else {
            estimatedMinutesToReserve = nil
            return
        }

        let usableFraction = Double(batteryPercent - manager.lowBatteryCutoff) / Double(batteryPercent)
        estimatedMinutesToReserve = max(0, Int((Double(minutesToEmpty) * usableFraction).rounded()))
    }

    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let rank: Int

        switch state {
        case .nominal:
            thermalStatus = "Nominal"
            rank = 0
        case .fair:
            thermalStatus = "Fair"
            rank = 1
        case .serious:
            thermalStatus = "Serious"
            rank = 2
        case .critical:
            thermalStatus = "Critical"
            rank = 3
        @unknown default:
            thermalStatus = "Unknown"
            rank = 0
        }

        thermalWarningActive = manager.isActive && rank >= 2

        if manager.isActive, rank >= 2, rank > lastWarnedThermalRank {
            let body = rank >= 3
                ? "macOS reports critical thermal pressure. Reduce the workload or improve ventilation immediately."
                : "macOS reports serious thermal pressure. Check ventilation and workload intensity."
            postNotification(title: "MacVigil thermal warning", body: body)
            statusText = body
            lastWarnedThermalRank = rank
        } else if rank < 2 {
            lastWarnedThermalRank = 0
        }

        if manager.isActive, rank > activePeakThermalRank {
            activePeakThermalRank = rank
            activeSessionPeakThermal = thermalStatus
        }
    }

    private func updateSessionState() {
        if manager.isActive && !lastManagerActive {
            activeSessionStartedAt = Date()
            activeSessionStartBattery = batteryPercent
            activeSessionConfiguration = manager.configurationName
            activePeakThermalRank = Self.thermalRank(thermalStatus)
            activeSessionPeakThermal = thermalStatus
            activeSessionElapsedSeconds = 0
        }

        if manager.isActive, let started = activeSessionStartedAt {
            activeSessionElapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
        }

        if !manager.isActive && lastManagerActive {
            finishSessionSummary()
        }

        lastManagerActive = manager.isActive
    }

    private func finishSessionSummary() {
        guard let started = activeSessionStartedAt else { return }
        let ended = Date()
        let summary = SessionSummary(
            id: UUID(),
            startedAt: started,
            endedAt: ended,
            durationSeconds: max(0, Int(ended.timeIntervalSince(started))),
            configuration: activeSessionConfiguration.isEmpty ? "Vigil" : activeSessionConfiguration,
            startBattery: activeSessionStartBattery,
            endBattery: batteryPercent,
            peakThermal: activeSessionPeakThermal
        )

        recentSessions.insert(summary, at: 0)
        if recentSessions.count > 12 {
            recentSessions = Array(recentSessions.prefix(12))
        }
        persistSessionHistory()

        activeSessionStartedAt = nil
        activeSessionStartBattery = nil
        activeSessionElapsedSeconds = 0
        activeSessionConfiguration = ""
        activePeakThermalRank = 0
        activeSessionPeakThermal = "Nominal"
    }

    private func persistSessionHistory() {
        if let encoded = try? JSONEncoder().encode(recentSessions) {
            UserDefaults.standard.set(encoded, forKey: sessionHistoryKey)
        }
    }

    private func enforceExternalPowerPolicyIfNeeded() async {
        guard requireExternalPowerForClosedLid,
              manager.isActive,
              manager.closedLidProtectionRequested,
              onBatteryPower else {
            policyStopInFlight = false
            return
        }

        guard !policyStopInFlight else { return }
        policyStopInFlight = true
        let message = "Closed-lid protection stopped because this Mac switched to battery power and External Power Only is enabled."
        statusText = message
        postNotification(title: "MacVigil stopped closed-lid protection", body: message)
        await manager.stopLiveSession()
        policyStopInFlight = false
    }

    private func prepareNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macvigil-power-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func firstIntegerMatch(pattern: String, text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func remainingMinutes(from text: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+):(\d+)\s+remaining"#, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let hoursRange = Range(match.range(at: 1), in: text),
              let minutesRange = Range(match.range(at: 2), in: text),
              let hours = Int(text[hoursRange]),
              let minutes = Int(text[minutesRange]) else { return nil }
        return (hours * 60) + minutes
    }

    private static func thermalRank(_ status: String) -> Int {
        switch status {
        case "Critical": return 3
        case "Serious": return 2
        case "Fair": return 1
        default: return 0
        }
    }

    static func durationText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }
}
