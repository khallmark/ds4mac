// MainView.swift — Primary navigation layout for DS4Mac
// NavigationSplitView with sidebar sections for each feature area.

import SwiftUI
import DS4Protocol
import DS4Transport

struct MainView: View {
    @EnvironmentObject var manager: DS4TransportManager

    enum Section: String, CaseIterable, Identifiable {
        case status = "Status"
        case controller = "Controller"
        case touchpad = "Touchpad"
        case monitor = "Monitor"
        case lightBar = "Light Bar"
        case rumble = "Rumble"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .status:     return "gamecontroller"
            case .controller: return "gamecontroller.fill"
            case .touchpad:   return "hand.point.up"
            case .monitor:    return "waveform"
            case .lightBar:   return "lightbulb.fill"
            case .rumble:     return "waveform.path"
            case .settings:   return "gear"
            }
        }
    }

    @State private var selectedSection: Section? = .status

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .navigationTitle("DS4Mac")
        } detail: {
            switch selectedSection {
            case .status:
                ControllerStatusView()
            case .controller:
                ControllerVisualizationView()
            case .touchpad:
                TouchpadVisualizationView()
            case .monitor:
                MonitorView()
            case .lightBar:
                LightBarView()
            case .rumble:
                RumbleView()
            case .settings:
                SettingsView()
            case nil:
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
