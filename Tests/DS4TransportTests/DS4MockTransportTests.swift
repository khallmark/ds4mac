// DS4MockTransportTests.swift — Verify mock transport conforms to protocol correctly

import XCTest
@testable import DS4Transport
import DS4Protocol

final class DS4MockTransportTests: XCTestCase {

    func testInitialState() {
        let mock = DS4MockTransport()
        XCTAssertEqual(mock.transportName, "Mock")
        XCTAssertFalse(mock.isConnected)
        XCTAssertNil(mock.deviceInfo)
        XCTAssertTrue(mock.sentReports.isEmpty)
    }

    func testConnectSetsStateAndFiresEvent() throws {
        let mock = DS4MockTransport()
        var receivedEvent: DS4TransportEvent?
        mock.onEvent = { event in receivedEvent = event }

        try mock.connect()

        XCTAssertTrue(mock.isConnected)
        XCTAssertNotNil(mock.deviceInfo)
        XCTAssertEqual(mock.deviceInfo?.product, "Mock DS4")

        if case .connected(let info) = receivedEvent {
            XCTAssertEqual(info.product, "Mock DS4")
            XCTAssertEqual(info.connectionType, .usb)
        } else {
            XCTFail("Expected .connected event, got \(String(describing: receivedEvent))")
        }
    }

    func testConnectWhenAlreadyConnectedThrows() throws {
        let mock = DS4MockTransport()
        try mock.connect()

        XCTAssertThrowsError(try mock.connect()) { error in
            XCTAssertEqual(error as? DS4TransportError, .alreadyConnected)
        }
    }

    func testDisconnectFiresEvent() throws {
        let mock = DS4MockTransport()
        try mock.connect()

        var receivedEvent: DS4TransportEvent?
        mock.onEvent = { event in receivedEvent = event }

        mock.disconnect()

        XCTAssertFalse(mock.isConnected)
        XCTAssertNil(mock.deviceInfo)

        if case .disconnected = receivedEvent {
            // expected
        } else {
            XCTFail("Expected .disconnected event, got \(String(describing: receivedEvent))")
        }
    }

    func testDisconnectWhenNotConnectedIsNoop() {
        let mock = DS4MockTransport()
        var eventFired = false
        mock.onEvent = { _ in eventFired = true }

        mock.disconnect()

        XCTAssertFalse(eventFired)
    }

    func testSendOutputReportRecordsData() throws {
        let mock = DS4MockTransport()
        try mock.connect()

        let report: [UInt8] = [0x05, 0x07, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00]
        try mock.sendOutputReport(report)

        XCTAssertEqual(mock.sentReports.count, 1)
        XCTAssertEqual(mock.sentReports[0], report)
    }

    func testSendOutputReportWhenNotConnectedThrows() {
        let mock = DS4MockTransport()

        XCTAssertThrowsError(try mock.sendOutputReport([0x05])) { error in
            XCTAssertEqual(error as? DS4TransportError, .notConnected)
        }
    }

    func testClearSentReports() throws {
        let mock = DS4MockTransport()
        try mock.connect()
        try mock.sendOutputReport([0x05, 0x00])

        XCTAssertEqual(mock.sentReports.count, 1)
        mock.clearSentReports()
        XCTAssertTrue(mock.sentReports.isEmpty)
    }

    func testInjectReportFiresInputReportEvent() {
        let mock = DS4MockTransport()
        let testData: [UInt8] = [0x01, 0x80, 0x80]

        var receivedBytes: [UInt8]?
        mock.onEvent = { event in
            if case .inputReport(let bytes) = event {
                receivedBytes = bytes
            }
        }

        mock.injectReport(testData)

        XCTAssertEqual(receivedBytes, testData)
    }

    func testReadFeatureReportReturnsConfiguredData() {
        let mock = DS4MockTransport()
        let calibrationData: [UInt8] = [0x02] + [UInt8](repeating: 0xAA, count: 36)
        mock.featureReports[0x02] = calibrationData

        let result = mock.readFeatureReport(reportID: 0x02, length: 37)
        XCTAssertEqual(result, calibrationData)
    }

    func testReadFeatureReportReturnsNilWhenNotConfigured() {
        let mock = DS4MockTransport()
        let result = mock.readFeatureReport(reportID: 0xFF, length: 10)
        XCTAssertNil(result)
    }

    func testCustomDeviceInfo() throws {
        let customInfo = DS4DeviceInfo(
            vendorID: 0x054C,
            productID: 0x05C4,
            manufacturer: "Sony",
            product: "DS4 V1",
            connectionType: .bluetooth,
            transport: "Bluetooth"
        )
        let mock = DS4MockTransport(deviceInfo: customInfo)
        try mock.connect()

        XCTAssertEqual(mock.deviceInfo?.connectionType, .bluetooth)
        XCTAssertEqual(mock.deviceInfo?.vendorID, 0x054C)
    }
}
