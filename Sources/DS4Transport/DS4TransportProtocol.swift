// DS4TransportProtocol.swift — Transport abstraction for DualShock 4 communication
// Reference: docs/10-macOS-Driver-Architecture.md Section 2.3, Layer 1

import DS4Protocol

/// Events from a DS4 transport layer.
public enum DS4TransportEvent: Sendable {
    case connected(DS4DeviceInfo)
    case disconnected
    case inputReport([UInt8])
    case error(DS4TransportError)
}

/// Errors from the transport layer.
public enum DS4TransportError: Error, Equatable, Sendable {
    case deviceNotFound
    case connectionFailed(String)
    case reportSendFailed(String)
    case featureReportFailed(reportID: UInt8, reason: String)
    case alreadyConnected
    case notConnected
}

/// Protocol for DS4 transport implementations (USB, Bluetooth, Mock).
///
/// Transports handle device discovery, connection lifecycle, and raw byte I/O.
/// All callback-based communication flows through `onEvent`.
///
/// Threading: IOKit callbacks fire on the RunLoop where the transport is scheduled.
/// Callers must ensure the RunLoop is running.
public protocol DS4TransportProtocol: AnyObject {

    /// Human-readable transport name (e.g., "USB", "Bluetooth", "Mock").
    var transportName: String { get }

    /// The currently connected device info, or nil if not connected.
    var deviceInfo: DS4DeviceInfo? { get }

    /// Whether a device is currently connected.
    var isConnected: Bool { get }

    /// Event handler called when transport events occur.
    /// Set this before calling `connect()`.
    var onEvent: ((DS4TransportEvent) -> Void)? { get set }

    /// Discover and connect to the first available DS4 controller.
    func connect() throws

    /// Disconnect from the currently connected device and release resources.
    func disconnect()

    /// Begin receiving input reports. Reports are delivered via `onEvent(.inputReport)`.
    func startInputReportPolling()

    /// Send a raw output report to the connected device.
    /// - Parameter data: Complete report bytes including report ID at index 0.
    @discardableResult
    func sendOutputReport(_ data: [UInt8]) throws -> Bool

    /// Read a feature report from the connected device.
    /// - Parameters:
    ///   - reportID: The HID feature report ID to read.
    ///   - length: The expected report length in bytes.
    /// - Returns: The raw report bytes, or nil on failure.
    func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]?
}
