import SwiftUI
import AppKit

struct PowerIntelligenceBar: View {
    @ObservedObject var power: PowerIntelligenceController

    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false

    var body: some View {
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "power-intelligence")
        } label: {
            HStack(spacing: 9) {
                Image(systemName: power.thermalWarningActive ? "exclamationmark.triangle.fill" : "bolt.heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(power.thermalWarningActive ? Color.orange : Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Power Intelligence")
                        .font(.caption.weight(.semibold))
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(Color.accentColor.opacity(hovering ? 0.07 : 0.001))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .help("Open Power Intelligence")
    }

    private var summary: String {
        let battery = power.batteryPercent.map { "\($0)%" } ?? "battery ?"
        if power.thermalWarningActive {
            return "\(battery) · thermal \(power.thermalStatus)"
        }
        if power.onBatteryPower {
            return "\(battery) · \(power.estimatedReserveText)"
        }
        return "\(battery) · power adapter · thermal \(power.thermalStatus.lowercased())"
    }
}
