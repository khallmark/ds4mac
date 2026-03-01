// DS4MacApp.swift — SwiftUI companion app entry point for DS4Mac
// Phase 3: Controller configuration UI + DriverKit system extension management

import SwiftUI
import DS4Protocol
import DS4Transport

@main
struct DS4MacApp: App {
    @State private var manager = DS4TransportManager(transport: DS4USBTransport())
    @State private var extensionManager = ExtensionManager()
    @State private var calibration = DS4LayoutCalibration()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(manager)
                .environment(extensionManager)
                .environment(calibration)
        }
        .windowResizability(.contentSize)

        Window("3D Gyroscope", id: "gyroscope-3d") {
            GyroscopeWindow()
                .environment(manager)
        }
        .defaultSize(width: 800, height: 600)

        Window("Overlay Debug", id: "overlay-debug") {
            OverlayDebugPanel()
                .environment(calibration)
        }
        .defaultSize(width: 310, height: 600)
    }
}
