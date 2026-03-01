// OverlayDebugPanel.swift — Floating debug window for live overlay position calibration.
// Provides sliders for each overlay element's x/y position with real-time preview.
// "Copy Swift Code" copies the current values as a DS4Layout.swift-ready snippet.

import SwiftUI

struct OverlayDebugPanel: View {
    @Environment(DS4LayoutCalibration.self) var cal
    @State private var copied = false

    var body: some View {
        @Bindable var cal = cal

        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Reset All") {
                    cal.reset()
                }

                Spacer()

                Button(copied ? "Copied!" : "Copy Swift Code") {
                    cal.copyToClipboard()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }
                .foregroundStyle(copied ? .green : .accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Position sliders
            ScrollView {
                VStack(spacing: 2) {
                    positionSection("Left Stick", point: $cal.leftStick)
                    positionSection("Right Stick", point: $cal.rightStick)
                    positionSection("D-Pad", point: $cal.dpad)
                    positionSection("Face Buttons", point: $cal.faceButtons)
                    positionSection("Light Bar", point: $cal.lightBar)
                    positionSection("L1", point: $cal.l1)
                    positionSection("R1", point: $cal.r1)
                    positionSection("L2", point: $cal.l2)
                    positionSection("R2", point: $cal.r2)
                    positionSection("Touchpad", point: $cal.touchpad)
                    sizeSection("Touchpad Size", size: $cal.touchpadSize)
                    positionSection("Center Btns", point: $cal.centerButtons)

                    Divider().padding(.vertical, 4)

                    Text("Button Spacing")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)

                    axisRow("dpad", value: $cal.dpadSpacing, range: 4...40)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)

                    axisRow("face", value: $cal.faceButtonSpacing, range: 4...40)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)

                    Divider().padding(.vertical, 4)

                    Text("Center Button Offsets")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)

                    offsetSection("Share", offset: $cal.shareOffset)
                    offsetSection("Options", offset: $cal.optionsOffset)
                    offsetSection("PS", offset: $cal.psOffset)
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 310, height: 600)
        .onAppear { cal.showAll = true }
        .onDisappear { cal.showAll = false }
    }

    // MARK: - Position Section (x/y sliders for a CGPoint)

    @ViewBuilder
    private func positionSection(_ label: String, point: Binding<CGPoint>) -> some View {
        DisclosureGroup {
            VStack(spacing: 4) {
                axisRow("x", value: Binding(
                    get: { point.wrappedValue.x },
                    set: { point.wrappedValue.x = $0 }
                ), range: 0...DS4Layout.canvasWidth)

                axisRow("y", value: Binding(
                    get: { point.wrappedValue.y },
                    set: { point.wrappedValue.y = $0 }
                ), range: 0...DS4Layout.canvasHeight)
            }
            .padding(.leading, 4)
        } label: {
            HStack {
                Text(label)
                    .font(.caption.bold())
                Spacer()
                Text("(\(Int(point.wrappedValue.x)), \(Int(point.wrappedValue.y)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Size Section (w/h sliders for a CGSize)

    @ViewBuilder
    private func sizeSection(_ label: String, size: Binding<CGSize>) -> some View {
        DisclosureGroup {
            VStack(spacing: 4) {
                axisRow("w", value: Binding(
                    get: { size.wrappedValue.width },
                    set: { size.wrappedValue.width = $0 }
                ), range: 10...300)

                axisRow("h", value: Binding(
                    get: { size.wrappedValue.height },
                    set: { size.wrappedValue.height = $0 }
                ), range: 10...200)
            }
            .padding(.leading, 4)
        } label: {
            HStack {
                Text(label)
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(size.wrappedValue.width))×\(Int(size.wrappedValue.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Offset Section (dx/dy sliders for a CGSize)

    @ViewBuilder
    private func offsetSection(_ label: String, offset: Binding<CGSize>) -> some View {
        DisclosureGroup {
            VStack(spacing: 4) {
                axisRow("dx", value: Binding(
                    get: { offset.wrappedValue.width },
                    set: { offset.wrappedValue.width = $0 }
                ), range: -100...100)

                axisRow("dy", value: Binding(
                    get: { offset.wrappedValue.height },
                    set: { offset.wrappedValue.height = $0 }
                ), range: -100...100)
            }
            .padding(.leading, 4)
        } label: {
            HStack {
                Text(label)
                    .font(.caption.bold())
                Spacer()
                Text("(\(Int(offset.wrappedValue.width)), \(Int(offset.wrappedValue.height)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Axis Row (label + slider + stepper)

    @ViewBuilder
    private func axisRow(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)

            Slider(value: value, in: range, step: 1)
                .controlSize(.small)

            Text("\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)

            Stepper("", value: value, in: range, step: 1)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
