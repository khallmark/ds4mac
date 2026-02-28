// DS4MacApp.swift — SwiftUI companion app entry point for DS4Mac
// Phase 3: Controller configuration UI + DriverKit system extension management

import SwiftUI
import DS4Protocol
import DS4Transport

@main
struct DS4MacApp: App {
    @State private var manager = DS4TransportManager(transport: DS4USBTransport())
    @State private var extensionManager = ExtensionManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(manager)
                .environment(extensionManager)
        }
    }
}
