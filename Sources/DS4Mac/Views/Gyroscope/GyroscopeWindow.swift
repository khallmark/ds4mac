// GyroscopeWindow.swift — 3D spaceship visualization driven by DS4 gyroscope
//
// Opens in a separate macOS window. A SceneKit scene shows a procedural
// spaceship whose orientation tracks the physical controller via complementary
// filter sensor fusion. Supports first-person (cockpit) and third-person
// (chase cam) perspectives with a toggle button.

import SwiftUI
import SceneKit
import DS4Protocol
import DS4Transport

struct GyroscopeWindow: View {
    @Environment(DS4TransportManager.self) var manager

    @State private var orientationFilter = OrientationFilter()
    @State private var sceneController = SpaceshipSceneController()
    @State private var isFirstPerson = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // SceneKit 3D view — fills the entire window
            SceneView(
                scene: sceneController.scene,
                pointOfView: isFirstPerson
                    ? sceneController.firstPersonCamera
                    : sceneController.thirdPersonCamera,
                options: [.rendersContinuously]
            )
            .ignoresSafeArea()

            // Overlay controls (top-right corner)
            controlsOverlay
                .padding()
        }
        .frame(minWidth: 500, minHeight: 350)
        .onChange(of: manager.calibrationData) { _, newCal in
            orientationFilter.calibrationData = newCal
        }
        .onChange(of: manager.inputState.imu) { _, newIMU in
            // Drive the sensor fusion filter at ~30 Hz (manager's throttle rate)
            orientationFilter.update(from: newIMU)
            sceneController.shipNode.simdOrientation = orientationFilter.orientation
        }
        .onAppear {
            orientationFilter.calibrationData = manager.calibrationData
        }
    }

    // MARK: - Overlay Controls

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Camera perspective toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFirstPerson.toggle()
                }
            } label: {
                Label(
                    isFirstPerson ? "Third Person" : "First Person",
                    systemImage: isFirstPerson ? "eye" : "airplane"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Reset orientation to neutral
            Button {
                orientationFilter.reset()
                sceneController.shipNode.simdOrientation = orientationFilter.orientation
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Live Euler angle readout
            eulerReadout
        }
    }

    @ViewBuilder
    private var eulerReadout: some View {
        let euler = orientationFilter.orientation.eulerAnglesZYX
        VStack(alignment: .trailing, spacing: 2) {
            Text("Pitch: \(formatDegrees(euler.x))")
            Text("Yaw:   \(formatDegrees(euler.y))")
            Text("Roll:  \(formatDegrees(euler.z))")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func formatDegrees(_ radians: Float) -> String {
        String(format: "%+6.1f\u{00B0}", radians * 180.0 / .pi)
    }
}
