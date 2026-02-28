// ControllerStatusView.swift — Connection state, device info, connect/disconnect controls

import SwiftUI
import DS4Protocol
import DS4Transport

struct ControllerStatusView: View {
    @EnvironmentObject var manager: DS4TransportManager

    var body: some View {
        VStack(spacing: 20) {
            connectionStatusSection
            if let info = manager.deviceInfo {
                deviceInfoSection(info)
                batterySection
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusSection: some View {
        GroupBox("Connection") {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    Text(statusText)
                        .font(.headline)
                    Spacer()
                }

                if let error = manager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button(action: { manager.connect() }) {
                        Label("Connect", systemImage: "cable.connector")
                    }
                    .disabled(manager.connectionState == .connected ||
                              manager.connectionState == .connecting)

                    Button(action: { manager.disconnect() }) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(manager.connectionState == .disconnected)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Device Info

    @ViewBuilder
    private func deviceInfoSection(_ info: DS4DeviceInfo) -> some View {
        GroupBox("Device Info") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Model:").foregroundStyle(.secondary)
                    Text(info.modelName)
                }
                GridRow {
                    Text("Vendor ID:").foregroundStyle(.secondary)
                    Text("0x\(String(info.vendorID, radix: 16, uppercase: true))")
                        .monospaced()
                }
                GridRow {
                    Text("Product ID:").foregroundStyle(.secondary)
                    Text("0x\(String(info.productID, radix: 16, uppercase: true))")
                        .monospaced()
                }
                if let manufacturer = info.manufacturer {
                    GridRow {
                        Text("Manufacturer:").foregroundStyle(.secondary)
                        Text(manufacturer)
                    }
                }
                if let product = info.product {
                    GridRow {
                        Text("Product:").foregroundStyle(.secondary)
                        Text(product)
                    }
                }
                if let serial = info.serialNumber {
                    GridRow {
                        Text("Serial:").foregroundStyle(.secondary)
                        Text(serial).monospaced()
                    }
                }
                GridRow {
                    Text("Connection:").foregroundStyle(.secondary)
                    Text(info.connectionType.rawValue.uppercased())
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Battery

    @ViewBuilder
    private var batterySection: some View {
        GroupBox("Battery") {
            HStack {
                let battery = manager.inputState.battery
                Image(systemName: batteryIcon(battery))
                    .foregroundStyle(batteryColor(battery))
                Text("\(battery.percentage)%")
                    .font(.headline)
                Text(battery.cableConnected ? "Charging" : "Wireless")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

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
}
