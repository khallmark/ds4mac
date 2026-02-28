// DS4MacApp.swift — SwiftUI companion app entry point for DS4Mac
// Phase 2: Controller configuration UI with live monitoring

import SwiftUI
import DS4Protocol
import DS4Transport

@main
struct DS4MacApp: App {
    @StateObject private var manager = DS4TransportManager(transport: DS4USBTransport())

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(manager)
        }
    }
}
