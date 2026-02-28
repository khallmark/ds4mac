// DS4MacApp.swift — SwiftUI companion app entry point for DS4Mac
// Phase 3: Controller configuration UI + DriverKit system extension management

import SwiftUI
import AppKit
import DS4Protocol
import DS4Transport

@main
struct DS4MacApp: App {
    @StateObject private var manager = DS4TransportManager(transport: DS4USBTransport())
    @StateObject private var extensionManager = ExtensionManager()

    init() {
        // SPM-built executables aren't app bundles, so macOS won't show
        // the window unless we explicitly activate as a regular GUI app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(manager)
                .environmentObject(extensionManager)
        }
    }
}
