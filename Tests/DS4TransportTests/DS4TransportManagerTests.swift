// DS4TransportManagerTests.swift — Test the ObservableObject bridge using DS4MockTransport

import XCTest
@testable import DS4Transport
import DS4Protocol

@MainActor
final class DS4TransportManagerTests: XCTestCase {

    private func makeManager() -> (DS4TransportManager, DS4MockTransport) {
        let transport = DS4MockTransport()
        let manager = DS4TransportManager(transport: transport)
        return (manager, transport)
    }

    /// Helper: build a minimal valid 64-byte USB input report with neutral sticks
    private func makeUSBReport(
        leftStickX: UInt8 = 0x80, leftStickY: UInt8 = 0x80,
        rightStickX: UInt8 = 0x80, rightStickY: UInt8 = 0x80,
        buttons0: UInt8 = 0x08,
        l2: UInt8 = 0, r2: UInt8 = 0
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x01  // Report ID
        report[1] = leftStickX
        report[2] = leftStickY
        report[3] = rightStickX
        report[4] = rightStickY
        report[5] = buttons0
        report[8] = l2
        report[9] = r2
        // Touch fingers inactive (bit 7 set): finger 0 at byte 35, finger 1 at byte 39
        report[35] = 0x80
        report[39] = 0x80
        return report
    }

    // MARK: - Connection Tests

    func testInitialStateIsDisconnected() {
        let (manager, _) = makeManager()
        XCTAssertEqual(manager.connectionState, .disconnected)
        XCTAssertNil(manager.deviceInfo)
        XCTAssertNil(manager.lastError)
    }

    func testConnectTransitionsToConnected() async {
        let (manager, _) = makeManager()
        manager.connect()

        // The .connected event is dispatched via Task — yield to let it run
        await Task.yield()

        XCTAssertEqual(manager.connectionState, .connected)
        XCTAssertNotNil(manager.deviceInfo)
        XCTAssertEqual(manager.deviceInfo?.product, "Mock DS4")
        XCTAssertNil(manager.lastError)
    }

    func testDisconnectClearsState() async {
        let (manager, _) = makeManager()
        manager.connect()
        await Task.yield()

        manager.disconnect()

        XCTAssertEqual(manager.connectionState, .disconnected)
        XCTAssertNil(manager.deviceInfo)
    }

    // MARK: - Input Report Tests

    func testInputReportUpdatesState() async {
        let (manager, transport) = makeManager()
        manager.connect()
        await Task.yield()

        // Inject a report with non-center sticks
        let report = makeUSBReport(leftStickX: 0, leftStickY: 255)
        transport.injectReport(report)
        await Task.yield()

        // The state won't appear in inputState until the display timer flushes.
        // Trigger flush manually by waiting for timer tick.
        // For testing, access the pending state indirectly — the timer runs at 30 Hz.
        // Wait a bit for the timer to fire.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms > 33ms timer interval

        XCTAssertEqual(manager.inputState.leftStick.x, 0)
        XCTAssertEqual(manager.inputState.leftStick.y, 255)
    }

    // MARK: - Output Report Tests

    func testSetLEDColorSendsOutputReport() async {
        let (manager, transport) = makeManager()
        manager.connect()
        await Task.yield()

        manager.setLEDColor(red: 255, green: 0, blue: 128)

        XCTAssertEqual(transport.sentReports.count, 1)
        let report = transport.sentReports[0]
        // USB output report: byte 0 = 0x05, byte 6 = red, byte 7 = green, byte 8 = blue
        XCTAssertEqual(report[0], DS4ReportID.usbOutput)
        XCTAssertEqual(report[6], 255)  // red
        XCTAssertEqual(report[7], 0)    // green
        XCTAssertEqual(report[8], 128)  // blue
    }

    func testSetRumbleSendsOutputReport() async {
        let (manager, transport) = makeManager()
        manager.connect()
        await Task.yield()

        manager.setRumble(heavy: 200, light: 100)

        XCTAssertEqual(transport.sentReports.count, 1)
        let report = transport.sentReports[0]
        // USB output: byte 4 = light (right/weak), byte 5 = heavy (left/strong)
        XCTAssertEqual(report[0], DS4ReportID.usbOutput)
        XCTAssertEqual(report[4], 100)  // light/right/weak motor
        XCTAssertEqual(report[5], 200)  // heavy/left/strong motor
    }

    func testSetLEDDoesNothingWhenNotConnected() {
        let (manager, transport) = makeManager()
        // Don't connect — should silently skip
        manager.setLEDColor(red: 255, green: 0, blue: 0)
        XCTAssertTrue(transport.sentReports.isEmpty)
    }

    // MARK: - Error Handling

    func testConnectWithAlreadyConnectedTransport() async {
        let transport = DS4MockTransport()
        try? transport.connect() // Pre-connect the mock
        let manager = DS4TransportManager(transport: transport)

        manager.connect()
        await Task.yield()

        // Should report error since transport is already connected
        XCTAssertNotNil(manager.lastError)
    }

    // MARK: - Feature Report Tests

    func testReadFeatureReport() async {
        let (manager, transport) = makeManager()
        let calibrationData: [UInt8] = [0x02] + [UInt8](repeating: 0xBB, count: 36)
        transport.featureReports[0x02] = calibrationData

        manager.connect()
        await Task.yield()

        let result = manager.readFeatureReport(reportID: 0x02, length: 37)
        XCTAssertEqual(result, calibrationData)
    }

    // MARK: - Disconnection Event Tests

    func testTransportDisconnectionUpdatesState() async {
        let (manager, transport) = makeManager()
        manager.connect()
        await Task.yield()

        XCTAssertEqual(manager.connectionState, .connected)

        // Simulate device disconnection
        transport.disconnect()
        await Task.yield()

        XCTAssertEqual(manager.connectionState, .disconnected)
        XCTAssertNil(manager.deviceInfo)
    }
}
