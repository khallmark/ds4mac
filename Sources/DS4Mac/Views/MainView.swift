// MainView.swift — Primary layout for DS4Mac
// Hero+inspector layout with controller visualization on the left
// and a tabbed inspector panel on the right.

import SwiftUI
import DS4Protocol
import DS4Transport

struct MainView: View {
    enum InspectorTab: String, CaseIterable, Identifiable {
        case status = "Status"
        case led = "LED"
        case rumble = "Rumble"
        case data = "Data"
        case settings = "Settings"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .status:   return "info.circle"
            case .led:      return "lightbulb.fill"
            case .rumble:   return "waveform.path"
            case .data:     return "list.bullet.rectangle"
            case .settings: return "gear"
            }
        }
    }

    @Environment(DS4TransportManager.self) var manager
    @State private var inspectorTab: InspectorTab = .status

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Hero area (left)
                ScrollView {
                    VStack(spacing: 20) {
                        ControllerVisualizationView()
                        TouchpadVisualizationView()
                    }
                    .padding()
                }
                .frame(minWidth: 460)
                .frame(maxWidth: .infinity)

                Divider()

                // Inspector panel (right)
                InspectorView(tab: $inspectorTab)
                    .frame(width: 300)
            }

            StatusBarView()
        }
        .frame(minWidth: 800, minHeight: 550)
    }
}
