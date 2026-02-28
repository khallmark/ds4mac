// MonitorView.swift — Live input state display with monospaced text
// Shows sticks, buttons, triggers, IMU, touchpad, and battery in real-time.

import SwiftUI
import DS4Protocol
import DS4Transport

struct MonitorView: View {
    @EnvironmentObject var manager: DS4TransportManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if manager.connectionState != .connected {
                    notConnectedView
                } else {
                    sticksSection
                    triggersSection
                    buttonsSection
                    imuSection
                    touchpadSection
                }
            }
            .padding()
        }
        .navigationTitle("Input Monitor")
        .font(.system(.body, design: .monospaced))
    }

    // MARK: - Not Connected

    @ViewBuilder
    private var notConnectedView: some View {
        ContentUnavailableView(
            "No Controller Connected",
            systemImage: "gamecontroller",
            description: Text("Connect a DualShock 4 controller to see live input data.")
        )
    }

    // MARK: - Sticks

    @ViewBuilder
    private var sticksSection: some View {
        let state = manager.inputState
        GroupBox("Analog Sticks") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    Text("Left Stick:")
                    Text("X=\(f3(state.leftStick.x))  Y=\(f3(state.leftStick.y))")
                }
                GridRow {
                    Text("Right Stick:")
                    Text("X=\(f3(state.rightStick.x))  Y=\(f3(state.rightStick.y))")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Triggers

    @ViewBuilder
    private var triggersSection: some View {
        let state = manager.inputState
        GroupBox("Triggers") {
            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Text("L2: \(f3(state.l2Trigger))")
                    ProgressView(value: Double(state.l2Trigger), total: 255)
                        .frame(width: 120)
                }
                VStack(alignment: .leading) {
                    Text("R2: \(f3(state.r2Trigger))")
                    ProgressView(value: Double(state.r2Trigger), total: 255)
                        .frame(width: 120)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonsSection: some View {
        let b = manager.inputState.buttons
        let dpad = manager.inputState.dpad

        GroupBox("Buttons & D-Pad") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    buttonChip("X", active: b.cross)
                    buttonChip("O", active: b.circle)
                    buttonChip("[]", active: b.square)
                    buttonChip("/\\", active: b.triangle)
                }
                HStack(spacing: 8) {
                    buttonChip("L1", active: b.l1)
                    buttonChip("R1", active: b.r1)
                    buttonChip("L2", active: b.l2)
                    buttonChip("R2", active: b.r2)
                }
                HStack(spacing: 8) {
                    buttonChip("L3", active: b.l3)
                    buttonChip("R3", active: b.r3)
                    buttonChip("Share", active: b.share)
                    buttonChip("Options", active: b.options)
                }
                HStack(spacing: 8) {
                    buttonChip("PS", active: b.ps)
                    buttonChip("Touch", active: b.touchpadClick)
                    Text("D-Pad: \(dpadLabel(dpad))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - IMU

    @ViewBuilder
    private var imuSection: some View {
        let imu = manager.inputState.imu
        GroupBox("IMU (Gyroscope & Accelerometer)") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Gyro:")
                    Text("P=\(f6(imu.gyroPitch))  Y=\(f6(imu.gyroYaw))  R=\(f6(imu.gyroRoll))")
                }
                GridRow {
                    Text("Accel:")
                    Text("X=\(f6(imu.accelX))  Y=\(f6(imu.accelY))  Z=\(f6(imu.accelZ))")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Touchpad

    @ViewBuilder
    private var touchpadSection: some View {
        let tp = manager.inputState.touchpad
        GroupBox("Touchpad") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Touch 0:")
                    if tp.touch0.active {
                        Text("id=\(tp.touch0.trackingID)  x=\(tp.touch0.x)  y=\(tp.touch0.y)")
                    } else {
                        Text("(inactive)").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Touch 1:")
                    if tp.touch1.active {
                        Text("id=\(tp.touch1.trackingID)  x=\(tp.touch1.x)  y=\(tp.touch1.y)")
                    } else {
                        Text("(inactive)").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func buttonChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundStyle(active ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func dpadLabel(_ dpad: DS4DPadDirection) -> String {
        switch dpad {
        case .north:     return "Up"
        case .northEast: return "Up-Right"
        case .east:      return "Right"
        case .southEast: return "Down-Right"
        case .south:     return "Down"
        case .southWest: return "Down-Left"
        case .west:      return "Left"
        case .northWest: return "Up-Left"
        case .neutral:   return "(center)"
        }
    }

    /// Format UInt8 as right-aligned 3-char string
    private func f3(_ val: UInt8) -> String {
        String(format: "%3d", val)
    }

    /// Format Int16 as right-aligned 6-char string
    private func f6(_ val: Int16) -> String {
        String(format: "%6d", val)
    }
}
