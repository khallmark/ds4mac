// ControllerVisualizationView.swift — Schematic controller with live animated state
// Shows sticks, buttons, triggers, d-pad, and light bar as interactive graphics.

import SwiftUI
import DS4Protocol
import DS4Transport

struct ControllerVisualizationView: View {
    @Environment(DS4TransportManager.self) var manager

    var body: some View {
        controllerBody
            .padding()
            .opacity(manager.connectionState == .connected ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.3), value: manager.connectionState == .connected)
    }

    // MARK: - Controller Body

    @ViewBuilder
    private var controllerBody: some View {
        let state = manager.inputState

        VStack(spacing: 20) {
            lightBarStrip(state: state)
            shoulderButtons(state: state)

            // Main body
            ZStack {
                // Controller outline
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.windowBackgroundColor).opacity(0.5))
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 440, height: 280)

                HStack(spacing: 40) {
                    // Left side: D-pad + Left Stick
                    VStack(spacing: 24) {
                        dpadView(direction: state.dpad)
                        stickView(stick: state.leftStick, pressed: state.buttons.l3, label: "L")
                    }

                    // Center: Share, PS, Touchpad, Options
                    VStack(spacing: 16) {
                        HStack(spacing: 20) {
                            smallButton("Share", active: state.buttons.share)
                            smallButton("Touch", active: state.buttons.touchpadClick)
                            smallButton("Options", active: state.buttons.options)
                        }
                        psButton(active: state.buttons.ps)
                    }

                    // Right side: Face buttons + Right Stick
                    VStack(spacing: 24) {
                        faceButtons(buttons: state.buttons)
                        stickView(stick: state.rightStick, pressed: state.buttons.r3, label: "R")
                    }
                }
            }

            // Trigger analog bars
            triggerBars(state: state)
        }
    }

    // MARK: - Light Bar

    private func lightBarStrip(state: DS4InputState) -> some View {
        let output = manager.outputState
        let color = Color(
            red: Double(output.ledRed) / 255,
            green: Double(output.ledGreen) / 255,
            blue: Double(output.ledBlue) / 255
        )
        let isOff = output.ledRed == 0 && output.ledGreen == 0 && output.ledBlue == 0

        return Capsule()
            .fill(isOff ? Color.secondary.opacity(0.2) : color)
            .frame(width: 200, height: 6)
            .shadow(color: isOff ? .clear : color.opacity(0.6), radius: 8)
    }

    // MARK: - Shoulder Buttons

    private func shoulderButtons(state: DS4InputState) -> some View {
        HStack(spacing: 160) {
            VStack(spacing: 4) {
                shoulderButton("L1", active: state.buttons.l1)
            }
            VStack(spacing: 4) {
                shoulderButton("R1", active: state.buttons.r1)
            }
        }
    }

    private func shoulderButton(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(.caption, design: .rounded).bold())
            .frame(width: 48, height: 20)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundStyle(active ? .white : .secondary)
            .clipShape(Capsule())
    }

    // MARK: - Analog Stick

    private func stickView(stick: DS4StickState, pressed: Bool, label: String) -> some View {
        let radius: CGFloat = 40
        // Map 0-255 to -1...1
        let nx = (CGFloat(stick.x) - 128) / 128
        let ny = (CGFloat(stick.y) - 128) / 128
        let dotOffset = CGSize(width: nx * (radius - 8), height: ny * (radius - 8))

        return ZStack {
            // Stick well
            Circle()
                .fill(Color.secondary.opacity(0.1))
                .strokeBorder(pressed ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: pressed ? 2 : 1)
                .frame(width: radius * 2, height: radius * 2)

            // Crosshair
            Path { path in
                path.move(to: CGPoint(x: radius, y: 4))
                path.addLine(to: CGPoint(x: radius, y: radius * 2 - 4))
                path.move(to: CGPoint(x: 4, y: radius))
                path.addLine(to: CGPoint(x: radius * 2 - 4, y: radius))
            }
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            .frame(width: radius * 2, height: radius * 2)

            // Stick position dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 16, height: 16)
                .shadow(color: .accentColor.opacity(0.4), radius: 3)
                .offset(dotOffset)

            // Label
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .offset(y: radius + 12)
        }
        .frame(width: radius * 2, height: radius * 2 + 24)
    }

    // MARK: - D-Pad

    private func dpadView(direction: DS4DPadDirection) -> some View {
        let size: CGFloat = 72
        let arm: CGFloat = 22
        let gap: CGFloat = 2

        return ZStack {
            // Up
            dpadArm(rotation: 0, active: [.north, .northEast, .northWest].contains(direction))
                .offset(y: -(arm / 2 + gap))
            // Down
            dpadArm(rotation: 180, active: [.south, .southEast, .southWest].contains(direction))
                .offset(y: arm / 2 + gap)
            // Left
            dpadArm(rotation: 270, active: [.west, .northWest, .southWest].contains(direction))
                .offset(x: -(arm / 2 + gap))
            // Right
            dpadArm(rotation: 90, active: [.east, .northEast, .southEast].contains(direction))
                .offset(x: arm / 2 + gap)
            // Center
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: arm, height: arm)
        }
        .frame(width: size, height: size)
    }

    private func dpadArm(rotation: Double, active: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: rotation == 0 ? 4 : 0,
            bottomLeadingRadius: rotation == 270 ? 4 : 0,
            bottomTrailingRadius: rotation == 180 ? 4 : 0,
            topTrailingRadius: rotation == 90 ? 4 : 0
        )
        .fill(active ? Color.accentColor : Color.secondary.opacity(0.2))
        .frame(width: 22, height: 22)
    }

    // MARK: - Face Buttons

    private func faceButtons(buttons: DS4Buttons) -> some View {
        let size: CGFloat = 28
        let spacing: CGFloat = 36

        return ZStack {
            faceButton(symbol: "triangle", color: .green, active: buttons.triangle)
                .offset(y: -spacing / 2)
            faceButton(symbol: "xmark", color: .blue, active: buttons.cross)
                .offset(y: spacing / 2)
            faceButton(symbol: "square", color: .pink, active: buttons.square)
                .offset(x: -spacing / 2)
            faceButton(symbol: "circle", color: .red, active: buttons.circle)
                .offset(x: spacing / 2)
        }
        .frame(width: spacing + size, height: spacing + size)
    }

    private func faceButton(symbol: String, color: Color, active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active ? color : Color.secondary.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(active ? .white : color.opacity(0.7))
        }
    }

    // MARK: - Small Buttons

    private func smallButton(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(.caption2, design: .rounded))
            .frame(width: 44, height: 16)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(active ? .white : .secondary)
            .clipShape(Capsule())
    }

    private func psButton(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.accentColor : Color.secondary.opacity(0.15))
            .frame(width: 20, height: 20)
            .overlay {
                Text("PS")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(active ? .white : .secondary)
            }
    }

    // MARK: - Trigger Bars

    private func triggerBars(state: DS4InputState) -> some View {
        HStack(spacing: 40) {
            triggerBar(label: "L2", value: state.l2Trigger)
            triggerBar(label: "R2", value: state.r2Trigger)
        }
    }

    private func triggerBar(label: String, value: UInt8) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 120, height: 10)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, CGFloat(value) / 255 * 120), height: 10)
            }
            Text("\(value)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
