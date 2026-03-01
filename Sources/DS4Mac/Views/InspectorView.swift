// InspectorView.swift — Right-side inspector panel with tab-based content switching
// Contains its own tab picker at the top and scrollable content below.

import SwiftUI

struct InspectorView: View {
    @Binding var tab: MainView.InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker built into the inspector header
            Picker("Inspector", selection: $tab) {
                ForEach(MainView.InspectorTab.allCases) { t in
                    Image(systemName: t.systemImage)
                        .tag(t)
                        .help(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.rawValue)
                        .font(.title3.bold())
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    switch tab {
                    case .status:
                        ControllerStatusView()
                    case .led:
                        LightBarView()
                    case .rumble:
                        RumbleView()
                    case .trackpad:
                        TrackpadView()
                    case .data:
                        MonitorView()
                    case .settings:
                        SettingsView()
                    }
                }
                .padding(.bottom)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}
