// DS4MockTransport.swift — Mock transport for testing and SwiftUI previews
// Generates synthetic DS4 reports without requiring real hardware.

import DS4Protocol

/// Mock transport that simulates a DS4 controller connection.
///
/// Useful for:
/// - Unit testing `DS4TransportManager`
/// - SwiftUI previews
/// - Development without a connected controller
public final class DS4MockTransport: DS4TransportProtocol {

    public var transportName: String { "Mock" }
    public private(set) var deviceInfo: DS4DeviceInfo?
    public private(set) var isConnected: Bool = false
    public var onEvent: ((DS4TransportEvent) -> Void)?

    /// All output reports sent via `sendOutputReport(_:)`, for test verification.
    public private(set) var sentReports: [[UInt8]] = []

    /// Feature report data to return, keyed by report ID.
    public var featureReports: [UInt8: [UInt8]] = [:]

    /// Device info to use when `connect()` is called.
    public var mockDeviceInfo: DS4DeviceInfo

    public init(deviceInfo: DS4DeviceInfo = DS4DeviceInfo(
        manufacturer: "Mock",
        product: "Mock DS4",
        connectionType: .usb,
        transport: "Mock"
    )) {
        self.mockDeviceInfo = deviceInfo
    }

    public func connect() throws {
        guard !isConnected else { throw DS4TransportError.alreadyConnected }
        isConnected = true
        deviceInfo = mockDeviceInfo
        onEvent?(.connected(mockDeviceInfo))
    }

    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        deviceInfo = nil
        onEvent?(.disconnected)
    }

    public func startInputReportPolling() {
        // No-op — use injectReport(_:) to simulate incoming reports
    }

    @discardableResult
    public func sendOutputReport(_ data: [UInt8]) throws -> Bool {
        guard isConnected else { throw DS4TransportError.notConnected }
        sentReports.append(data)
        return true
    }

    public func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]? {
        return featureReports[reportID]
    }

    // MARK: - Test Helpers

    /// Simulate an incoming input report from the controller.
    public func injectReport(_ data: [UInt8]) {
        onEvent?(.inputReport(data))
    }

    /// Clear recorded sent reports.
    public func clearSentReports() {
        sentReports.removeAll()
    }
}
