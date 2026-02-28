// StatusBarView.swift — Bottom status bar showing connection info at a glance

import SwiftUI
import DS4Protocol
import DS4Transport

struct StatusBarView: View {
    @EnvironmentObject var manager: DS4TransportManager

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                // Connection status dot + text
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .connected = manager.connectionState, let info = manager.deviceInfo {
                    statusDivider

                    // Device model name
                    Text(info.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusDivider

                    // Connection type
                    Text(info.connectionType.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    statusDivider

                    // Battery
                    batteryIndicator
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(.bar)
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch manager.connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    private var statusText: String {
        switch manager.connectionState {
        case .connected:      return "Connected"
        case .connecting:     return "Connecting..."
        case .disconnected:   return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    // MARK: - Battery

    @ViewBuilder
    private var batteryIndicator: some View {
        let battery = manager.inputState.battery
        Image(systemName: batteryIcon(battery))
            .font(.caption)
            .foregroundStyle(batteryColor(battery))
        Text("\(battery.percentage)%")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func batteryIcon(_ battery: DS4BatteryState) -> String {
        if battery.cableConnected { return "battery.100.bolt" }
        let pct = battery.percentage
        if pct > 75 { return "battery.100" }
        if pct > 50 { return "battery.75" }
        if pct > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(_ battery: DS4BatteryState) -> Color {
        if battery.cableConnected { return .green }
        return battery.percentage > 20 ? .primary : .red
    }

    // MARK: - Divider

    private var statusDivider: some View {
        Text("|")
            .font(.caption)
            .foregroundStyle(.quaternary)
    }
}
