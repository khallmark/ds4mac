// SettingsView.swift — App preferences (display rate, auto-connect)

import SwiftUI

struct SettingsView: View {
    @AppStorage("autoConnect") private var autoConnect = false

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Auto-connect on launch", isOn: $autoConnect)
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Phase", value: "2 — App-Level Driver")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
