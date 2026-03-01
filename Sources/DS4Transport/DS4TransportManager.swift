// DS4TransportManager.swift — High-level controller connection manager for SwiftUI
// Bridges DS4TransportProtocol to SwiftUI via @Observable property-level tracking.

import Foundation
import Observation
import DS4Protocol

/// Manages a DS4 controller connection and provides observable state for SwiftUI.
///
/// This is the primary interface the companion app uses. It wraps a `DS4TransportProtocol`
/// implementation and publishes state changes via `@Observable` tracked properties.
/// SwiftUI views only re-render when properties they actually read change.
///
/// Usage:
/// ```swift
/// let manager = DS4TransportManager(transport: DS4USBTransport())
/// manager.connect()
/// // Observe manager.inputState, manager.connectionState, etc.
/// ```
@MainActor
@Observable
public final class DS4TransportManager {

    // MARK: - Observable State

    /// Current connection state.
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Latest parsed input state from the controller.
    public private(set) var inputState: DS4InputState = DS4InputState()

    /// Connected device info.
    public private(set) var deviceInfo: DS4DeviceInfo?

    /// Last output state sent to the controller (LED color, rumble).
    public private(set) var outputState: DS4OutputState = DS4OutputState()

    /// IMU calibration data read from the controller on connect.
    public private(set) var calibrationData: DS4CalibrationData?

    /// Error message, if any.
    public private(set) var lastError: String?

    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Private State

    private let transport: DS4TransportProtocol

    /// Throttle: only update inputState at this interval to avoid SwiftUI churn.
    /// DS4 sends reports at ~250 Hz; we display at ~30 Hz.
    private let updateInterval: TimeInterval = 1.0 / 30.0
    private var lastUpdateTime: TimeInterval = 0
    private var pendingState: DS4InputState?

    /// Timer to flush the most recent pending state on the throttle interval.
    private var displayTimer: Timer?

    /// Flag set from transport callback, read by timer to avoid unnecessary Task allocation.
    /// Deliberately nonisolated — racy reads are acceptable (the authoritative check is in flushPendingState).
    @ObservationIgnored
    nonisolated(unsafe) private var hasPendingState: Bool = false

    public init(transport: DS4TransportProtocol) {
        self.transport = transport
        setupTransportCallbacks()
    }

    // MARK: - Public API

    /// Connect to the first available DS4 controller.
    public func connect() {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        lastError = nil

        do {
            try transport.connect()
            transport.startInputReportPolling()
            startDisplayTimer()
        } catch let error as DS4TransportError {
            connectionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    /// Disconnect from the current controller.
    public func disconnect() {
        displayTimer?.invalidate()
        displayTimer = nil
        transport.disconnect()
        connectionState = .disconnected
        deviceInfo = nil
        calibrationData = nil
        pendingState = nil
    }

    /// Set the light bar color.
    public func setLEDColor(red: UInt8, green: UInt8, blue: UInt8) {
        let output = DS4OutputState(ledRed: red, ledGreen: green, ledBlue: blue)
        sendOutputState(output)
    }

    /// Set rumble motor intensities.
    public func setRumble(heavy: UInt8, light: UInt8) {
        let output = DS4OutputState(rumbleHeavy: heavy, rumbleLight: light)
        sendOutputState(output)
    }

    /// Send a combined output state (LED + rumble).
    public func sendOutputState(_ output: DS4OutputState) {
        guard let info = deviceInfo else { return }
        let report: [UInt8]
        if info.connectionType == .bluetooth {
            report = DS4OutputReportBuilder.buildBluetooth(output)
        } else {
            report = DS4OutputReportBuilder.buildUSB(output)
        }
        do {
            try transport.sendOutputReport(report)
            outputState = output
        } catch {
            lastError = "Failed to send output report: \(error)"
        }
    }

    /// Read a feature report from the connected device.
    public func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]? {
        return transport.readFeatureReport(reportID: reportID, length: length)
    }

    // MARK: - Private

    private func loadCalibrationData(connectionType: DS4ConnectionType) {
        let reportID: UInt8
        let length: Int

        switch connectionType {
        case .bluetooth:
            reportID = DS4ReportID.calibrationBT
            length = 41  // 37 payload + 4 CRC
        case .usb:
            reportID = DS4ReportID.calibrationUSB
            length = DS4ReportSize.calibration
        }

        guard let data = transport.readFeatureReport(reportID: reportID, length: length) else {
            calibrationData = nil
            return
        }

        do {
            let cal: DS4CalibrationData
            switch connectionType {
            case .bluetooth:
                cal = try DS4CalibrationDataParser.parseBluetooth(data)
            case .usb:
                cal = try DS4CalibrationDataParser.parseUSB(data)
            }
            calibrationData = cal.isValid ? cal : nil
        } catch {
            calibrationData = nil
        }
    }

    private func setupTransportCallbacks() {
        transport.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: DS4TransportEvent) {
        switch event {
        case .connected(let info):
            deviceInfo = info
            connectionState = .connected
            lastError = nil
            loadCalibrationData(connectionType: info.connectionType)

        case .disconnected:
            connectionState = .disconnected
            deviceInfo = nil
            displayTimer?.invalidate()
            displayTimer = nil

        case .inputReport(let bytes):
            parseAndThrottleReport(bytes)

        case .error(let transportError):
            lastError = transportError.localizedDescription
            connectionState = .error(transportError.localizedDescription)
        }
    }

    private func parseAndThrottleReport(_ bytes: [UInt8]) {
        do {
            let state = try DS4InputReportParser.parse(bytes)
            pendingState = state
            hasPendingState = true
        } catch {
            // Silently skip malformed/reduced reports
        }
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self, self.hasPendingState else { return }
            Task { @MainActor [weak self] in
                self?.flushPendingState()
            }
        }
    }

    private func flushPendingState() {
        guard let state = pendingState else { return }
        pendingState = nil
        hasPendingState = false
        guard state != inputState else { return }
        inputState = state
    }
}

// MARK: - DS4TransportError LocalizedError

extension DS4TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No DualShock 4 controller found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .reportSendFailed(let reason):
            return "Report send failed: \(reason)"
        case .featureReportFailed(let reportID, let reason):
            return "Feature report 0x\(String(reportID, radix: 16)) failed: \(reason)"
        case .alreadyConnected:
            return "Already connected"
        case .notConnected:
            return "Not connected"
        }
    }
}
