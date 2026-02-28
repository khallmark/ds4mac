// RumbleView.swift — Rumble motor controls with heavy/light sliders

import SwiftUI
import DS4Protocol
import DS4Transport

struct RumbleView: View {
    @EnvironmentObject var manager: DS4TransportManager

    @State private var heavy: Double = 0
    @State private var light: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            if manager.connectionState != .connected {
                ContentUnavailableView(
                    "No Controller Connected",
                    systemImage: "gamecontroller",
                    description: Text("Connect a DualShock 4 to test rumble motors.")
                )
            } else {
                motorsSection
                testSection
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Rumble")
    }

    // MARK: - Motor Sliders

    @ViewBuilder
    private var motorsSection: some View {
        GroupBox("Motor Intensity") {
            VStack(spacing: 12) {
                HStack {
                    Text("Heavy (Left)")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $heavy, in: 0...255, step: 1)
                    Text("\(Int(heavy))")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Light (Right)")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $light, in: 0...255, step: 1)
                    Text("\(Int(light))")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                Button("Apply") {
                    manager.setRumble(heavy: UInt8(heavy), light: UInt8(light))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Test Buttons

    @ViewBuilder
    private var testSection: some View {
        GroupBox("Quick Test") {
            HStack(spacing: 12) {
                Button("Light Tap") {
                    manager.setRumble(heavy: 0, light: 128)
                    stopAfterDelay()
                }

                Button("Heavy Thud") {
                    manager.setRumble(heavy: 200, light: 0)
                    stopAfterDelay()
                }

                Button("Full Blast") {
                    manager.setRumble(heavy: 255, light: 255)
                    stopAfterDelay()
                }

                Button("Stop") {
                    manager.setRumble(heavy: 0, light: 0)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 4)
        }
    }

    private func stopAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            manager.setRumble(heavy: 0, light: 0)
        }
    }
}
