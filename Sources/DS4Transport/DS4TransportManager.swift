// DS4TransportManager.swift — High-level controller connection manager for SwiftUI
// Bridges DS4TransportProtocol callbacks to Combine @Published properties.

import Foundation
import Combine
import DS4Protocol

/// Manages a DS4 controller connection and provides observable state for SwiftUI.
///
/// This is the primary interface the companion app uses. It wraps a `DS4TransportProtocol`
/// implementation and publishes state changes via `@Published` properties.
///
/// Usage:
/// ```swift
/// let manager = DS4TransportManager(transport: DS4USBTransport())
/// manager.connect()
/// // Observe manager.inputState, manager.connectionState, etc.
/// ```
@MainActor
public final class DS4TransportManager: ObservableObject {

    // MARK: - Published State

    /// Current connection state.
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    /// Latest parsed input state from the controller.
    @Published public private(set) var inputState: DS4InputState = DS4InputState()

    /// Connected device info.
    @Published public private(set) var deviceInfo: DS4DeviceInfo?

    /// Error message, if any.
    @Published public private(set) var lastError: String?

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

    public init(transport: DS4TransportProtocol) {
        self.transport = transport
        setupTransportCallbacks()
    }

    deinit {
        displayTimer?.invalidate()
    }

    // MARK: - Public API

    /// Connect to the first available DS4 controller.
    public func connect() {
        guard connectionState == .disconnected || connectionState != .connecting else { return }
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
        } catch {
            lastError = "Failed to send output report: \(error)"
        }
    }

    /// Read a feature report from the connected device.
    public func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]? {
        return transport.readFeatureReport(reportID: reportID, length: length)
    }

    // MARK: - Private

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
        } catch {
            // Silently skip malformed/reduced reports
        }
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPendingState()
            }
        }
    }

    private func flushPendingState() {
        guard let state = pendingState else { return }
        inputState = state
        pendingState = nil
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
