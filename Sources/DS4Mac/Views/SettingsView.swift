// SettingsView.swift — App preferences and driver extension management
// Phase 3: Adds system extension install/uninstall UI alongside general settings.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var extensionManager: ExtensionManager
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("useFallbackTransport") private var useFallbackTransport = false

    var body: some View {
        Form {
            driverSection
            connectionSection
            aboutSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Driver Extension Section

    private var driverSection: some View {
        Section("System Extension") {
            HStack {
                Label("Driver Status", systemImage: driverStatusIcon)
                Spacer()
                Text(extensionManager.state.rawValue)
                    .foregroundStyle(driverStatusColor)
            }

            if let error = extensionManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Install Driver") {
                    extensionManager.activateDriver()
                }
                .disabled(extensionManager.state == .active
                          || extensionManager.state == .activating)

                Button("Uninstall Driver") {
                    extensionManager.deactivateDriver()
                }
                .disabled(extensionManager.state == .notInstalled
                          || extensionManager.state == .deactivating
                          || extensionManager.state == .unknown)
            }

            if extensionManager.state == .needsApproval {
                Button("Open System Settings") {
                    openSystemExtensionsSettings()
                }
                .foregroundStyle(.blue)
            }

            Toggle("Use fallback transport (IOHIDManager)", isOn: $useFallbackTransport)
                .help("When enabled, the app connects directly via IOHIDManager instead of through the system extension. Useful if the driver is not installed.")
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section("Connection") {
            Toggle("Auto-connect on launch", isOn: $autoConnect)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "0.2.0")
            LabeledContent("Phase", value: "3 — DriverKit Extension")
        }
    }

    // MARK: - Helpers

    private var driverStatusIcon: String {
        switch extensionManager.state {
        case .active:        return "checkmark.circle.fill"
        case .activating,
             .deactivating:  return "arrow.triangle.2.circlepath"
        case .needsApproval: return "exclamationmark.triangle.fill"
        case .failed:        return "xmark.circle.fill"
        case .notInstalled,
             .unknown:       return "circle.dashed"
        }
    }

    private var driverStatusColor: Color {
        switch extensionManager.state {
        case .active:        return .green
        case .activating,
             .deactivating:  return .orange
        case .needsApproval: return .yellow
        case .failed:        return .red
        case .notInstalled,
             .unknown:       return .secondary
        }
    }

    private func openSystemExtensionsSettings() {
        // macOS 15+: System Settings > General > Login Items & Extensions
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
