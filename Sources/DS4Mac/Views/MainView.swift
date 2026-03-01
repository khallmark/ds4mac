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
        case trackpad = "Trackpad"
        case data = "Data"
        case settings = "Settings"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .status:   return "info.circle"
            case .led:      return "lightbulb.fill"
            case .rumble:   return "waveform.path"
            case .trackpad: return "hand.point.up.braille"
            case .data:     return "list.bullet.rectangle"
            case .settings: return "gear"
            }
        }
    }

    @Environment(DS4TransportManager.self) var manager
    @Environment(\.openWindow) private var openWindow
    @State private var inspectorTab: InspectorTab = .status

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Hero area (left) — controller photo fills available space
                DS4ControllerView()
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Inspector panel (right)
                InspectorView(tab: $inspectorTab)
                    .frame(width: 350)
            }

            StatusBarView()
        }
        .frame(width: 960, height: 640)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "overlay-debug")
                } label: {
                    Label("Calibrate", systemImage: "slider.horizontal.3")
                }
                .help("Open Overlay Position Debug Panel")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "space-combat")
                } label: {
                    Label("Space Combat", systemImage: "gamecontroller")
                }
                .help("Open Space Combat Mini-Game")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "gyroscope-3d")
                } label: {
                    Label("3D View", systemImage: "rotate.3d")
                }
                .help("Open 3D Gyroscope Visualization")
            }
        }
    }
}
