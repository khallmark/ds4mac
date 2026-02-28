// LightBarView.swift — RGB light bar controls with color preview and presets

import SwiftUI
import DS4Protocol
import DS4Transport

struct LightBarView: View {
    @EnvironmentObject var manager: DS4TransportManager

    @State private var red: Double = 0
    @State private var green: Double = 0
    @State private var blue: Double = 64

    var body: some View {
        VStack(spacing: 20) {
            colorPreview
            slidersSection
            presetsSection

            if manager.connectionState != .connected {
                Text("Connect a controller to apply changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .disabled(manager.connectionState != .connected)
    }

    // MARK: - Color Preview

    @ViewBuilder
    private var colorPreview: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(red: red / 255, green: green / 255, blue: blue / 255))
            .frame(height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Sliders

    @ViewBuilder
    private var slidersSection: some View {
        GroupBox("Color Channels") {
            VStack(spacing: 12) {
                colorSlider(label: "Red", value: $red, color: .red)
                colorSlider(label: "Green", value: $green, color: .green)
                colorSlider(label: "Blue", value: $blue, color: .blue)

                Button("Apply") {
                    manager.setLEDColor(
                        red: UInt8(red),
                        green: UInt8(green),
                        blue: UInt8(blue)
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private func colorSlider(label: String, value: Binding<Double>, color: Color) -> some View {
        HStack {
            Text(label)
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
            Slider(value: value, in: 0...255, step: 1)
                .tint(color)
            Text("\(Int(value.wrappedValue))")
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetsSection: some View {
        GroupBox("Presets") {
            HStack(spacing: 12) {
                presetButton("Red", r: 255, g: 0, b: 0)
                presetButton("Green", r: 0, g: 255, b: 0)
                presetButton("Blue", r: 0, g: 0, b: 255)
                presetButton("White", r: 255, g: 255, b: 255)
                presetButton("Off", r: 0, g: 0, b: 0)
                presetButton("PS Blue", r: 0, g: 0, b: 64)
            }
            .padding(.vertical, 4)
        }
    }

    private func presetButton(_ label: String, r: Double, g: Double, b: Double) -> some View {
        Button(label) {
            red = r; green = g; blue = b
            manager.setLEDColor(red: UInt8(r), green: UInt8(g), blue: UInt8(b))
        }
        .buttonStyle(.bordered)
    }
}
