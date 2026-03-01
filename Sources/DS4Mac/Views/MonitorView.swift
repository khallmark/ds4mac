// MonitorView.swift — Live input state display with monospaced text
// Shows sticks, buttons, triggers, IMU, touchpad, and battery in real-time.

import SwiftUI
import Charts
import DS4Protocol
import DS4Transport

/// A single timestamped IMU data point for the rolling chart buffer.
struct IMUSample: Identifiable {
    let id: Int
    let gyroPitch: Double
    let gyroYaw: Double
    let gyroRoll: Double
    let accelX: Double
    let accelY: Double
    let accelZ: Double
}

/// A flattened per-series point for Swift Charts rendering.
struct IMUChartPoint: Identifiable {
    let id: Int
    let sampleIndex: Int
    let value: Double
    let axis: String
}

struct MonitorView: View {
    @Environment(DS4TransportManager.self) var manager

    @State private var imuSamples: [IMUSample] = []
    @State private var sampleCounter: Int = 0
    @State private var showCalibrated: Bool = true
    private let maxSamples = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sticksSection
            triggersSection
            buttonsSection
            imuSection
            touchpadSection
        }
        .padding()
        .font(.system(.body, design: .monospaced))
        .opacity(manager.connectionState == .connected ? 1.0 : 0.5)
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

    private var useCalibrated: Bool {
        showCalibrated && manager.calibrationData != nil
    }

    @ViewBuilder
    private var imuSection: some View {
        let imu = manager.inputState.imu
        let cal = manager.calibrationData

        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    if useCalibrated, let cal {
                        GridRow {
                            Text("Gyro:")
                            Text("P=\(fd(gyroDeadZone(cal.calibrateGyro(axis: .pitch, rawValue: imu.gyroPitch))))  Y=\(fd(gyroDeadZone(cal.calibrateGyro(axis: .yaw, rawValue: imu.gyroYaw))))  R=\(fd(gyroDeadZone(cal.calibrateGyro(axis: .roll, rawValue: imu.gyroRoll)))) deg/s")
                        }
                        GridRow {
                            Text("Accel:")
                            Text("X=\(fg(cal.calibrateAccel(axis: .pitch, rawValue: imu.accelX)))  Y=\(fg(cal.calibrateAccel(axis: .yaw, rawValue: imu.accelY)))  Z=\(fg(cal.calibrateAccel(axis: .roll, rawValue: imu.accelZ))) g")
                        }
                    } else {
                        GridRow {
                            Text("Gyro:")
                            Text("P=\(f6(imu.gyroPitch))  Y=\(f6(imu.gyroYaw))  R=\(f6(imu.gyroRoll))")
                        }
                        GridRow {
                            Text("Accel:")
                            Text("X=\(f6(imu.accelX))  Y=\(f6(imu.accelY))  Z=\(f6(imu.accelZ))")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text("IMU (Gyroscope & Accelerometer)")
                Spacer()
                Toggle("Calibrated", isOn: $showCalibrated)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(cal == nil)
            }
        }

        gyroChart
        accelChart
            .onChange(of: manager.inputState.imu) { _, newIMU in
                appendSample(from: newIMU)
            }
    }

    // MARK: - Gyroscope Chart

    @ViewBuilder
    private var gyroChart: some View {
        let cal = useCalibrated ? manager.calibrationData : nil
        let gyroLabel = cal != nil ? "deg/s" : "raw"
        let points = imuSamples.flatMap { s in
            [
                IMUChartPoint(id: s.id &* 3, sampleIndex: s.id,
                              value: cal?.calibrateGyro(axis: .pitch, rawValue: Int16(s.gyroPitch)) ?? s.gyroPitch,
                              axis: "Pitch"),
                IMUChartPoint(id: s.id &* 3 &+ 1, sampleIndex: s.id,
                              value: cal?.calibrateGyro(axis: .yaw, rawValue: Int16(s.gyroYaw)) ?? s.gyroYaw,
                              axis: "Yaw"),
                IMUChartPoint(id: s.id &* 3 &+ 2, sampleIndex: s.id,
                              value: cal?.calibrateGyro(axis: .roll, rawValue: Int16(s.gyroRoll)) ?? s.gyroRoll,
                              axis: "Roll"),
            ]
        }

        GroupBox("Gyroscope") {
            Chart(points) { point in
                LineMark(
                    x: .value("Sample", point.sampleIndex),
                    y: .value(gyroLabel, point.value)
                )
                .foregroundStyle(by: .value("Axis", point.axis))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                "Pitch": Color.red,
                "Yaw": Color.green,
                "Roll": Color.blue,
            ])
            .chartXAxis(.hidden)
            .chartXScale(domain: (imuSamples.first?.id ?? 0)...(imuSamples.last?.id ?? maxSamples))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 4)
            .frame(height: 120)
        }
    }

    // MARK: - Accelerometer Chart

    @ViewBuilder
    private var accelChart: some View {
        let cal = useCalibrated ? manager.calibrationData : nil
        let accelLabel = cal != nil ? "g" : "raw"
        let points = imuSamples.flatMap { s in
            [
                IMUChartPoint(id: s.id &* 3, sampleIndex: s.id,
                              value: cal?.calibrateAccel(axis: .pitch, rawValue: Int16(s.accelX)) ?? s.accelX,
                              axis: "X"),
                IMUChartPoint(id: s.id &* 3 &+ 1, sampleIndex: s.id,
                              value: cal?.calibrateAccel(axis: .yaw, rawValue: Int16(s.accelY)) ?? s.accelY,
                              axis: "Y"),
                IMUChartPoint(id: s.id &* 3 &+ 2, sampleIndex: s.id,
                              value: cal?.calibrateAccel(axis: .roll, rawValue: Int16(s.accelZ)) ?? s.accelZ,
                              axis: "Z"),
            ]
        }

        GroupBox("Accelerometer") {
            Chart(points) { point in
                LineMark(
                    x: .value("Sample", point.sampleIndex),
                    y: .value(accelLabel, point.value)
                )
                .foregroundStyle(by: .value("Axis", point.axis))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartForegroundStyleScale([
                "X": Color.orange,
                "Y": Color.cyan,
                "Z": Color.purple,
            ])
            .chartXAxis(.hidden)
            .chartXScale(domain: (imuSamples.first?.id ?? 0)...(imuSamples.last?.id ?? maxSamples))
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 4)
            .frame(height: 120)
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

    private func appendSample(from imu: DS4IMUState) {
        let sample = IMUSample(
            id: sampleCounter,
            gyroPitch: Double(imu.gyroPitch),
            gyroYaw: Double(imu.gyroYaw),
            gyroRoll: Double(imu.gyroRoll),
            accelX: Double(imu.accelX),
            accelY: Double(imu.accelY),
            accelZ: Double(imu.accelZ)
        )
        sampleCounter += 1
        imuSamples.append(sample)
        if imuSamples.count > maxSamples {
            imuSamples.removeFirst(imuSamples.count - maxSamples)
        }
    }

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

    /// Display dead zone for calibrated gyro (deg/s). Matches OrientationFilter threshold.
    private let displayGyroDeadZone: Double = 0.5

    /// Zero out gyro values below dead zone threshold for cleaner display at rest.
    private func gyroDeadZone(_ val: Double) -> Double {
        abs(val) < displayGyroDeadZone ? 0.0 : val
    }

    /// Format Double as deg/s with 1 decimal place, right-aligned 7 chars
    private func fd(_ val: Double) -> String {
        String(format: "%7.1f", val)
    }

    /// Format Double as g-force with 2 decimal places, right-aligned 6 chars
    private func fg(_ val: Double) -> String {
        String(format: "%6.2f", val)
    }
}
