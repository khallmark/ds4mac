import XCTest
@testable import DS4Protocol

final class DS4ConstantsTests: XCTestCase {

    // MARK: - Device IDs

    func testSonyVendorID() {
        XCTAssertEqual(DS4DeviceID.vendorID, 0x054C)
        XCTAssertEqual(DS4DeviceID.vendorID, 1356)  // decimal in Info.plist
    }

    func testDS4V1ProductID() {
        XCTAssertEqual(DS4DeviceID.ds4V1PID, 0x05C4)
        XCTAssertEqual(DS4DeviceID.ds4V1PID, 1476)
    }

    func testDS4V2ProductID() {
        XCTAssertEqual(DS4DeviceID.ds4V2PID, 0x09CC)
        XCTAssertEqual(DS4DeviceID.ds4V2PID, 2508)
    }

    // MARK: - Report IDs

    func testUSBInputReportID() {
        XCTAssertEqual(DS4ReportID.usbInput, 0x01)
    }

    func testBTInputReportID() {
        XCTAssertEqual(DS4ReportID.btInput, 0x11)
    }

    func testUSBOutputReportID() {
        XCTAssertEqual(DS4ReportID.usbOutput, 0x05)
    }

    // MARK: - Report Sizes

    func testUSBInputReportSize() {
        XCTAssertEqual(DS4ReportSize.usbInput, 64)
    }

    func testBTInputReportSize() {
        XCTAssertEqual(DS4ReportSize.btInput, 78)
    }

    func testUSBOutputReportSize() {
        XCTAssertEqual(DS4ReportSize.usbOutput, 32)
    }

    func testBTOutputReportSize() {
        XCTAssertEqual(DS4ReportSize.btOutput, 78)
    }

    // MARK: - Feature Flags

    func testStandardFeatureFlags() {
        let standard = DS4FeatureFlag.standard
        XCTAssertEqual(standard.rawValue, 0x07)
        XCTAssertTrue(standard.contains(.rumble))
        XCTAssertTrue(standard.contains(.lightbar))
        XCTAssertTrue(standard.contains(.flash))
    }

    // MARK: - D-Pad

    func testDPadNeutralValue() {
        XCTAssertEqual(DS4DPadDirection.neutral.rawValue, 8)
    }

    func testDPadAllDirections() {
        XCTAssertEqual(DS4DPadDirection.north.rawValue, 0)
        XCTAssertEqual(DS4DPadDirection.northEast.rawValue, 1)
        XCTAssertEqual(DS4DPadDirection.east.rawValue, 2)
        XCTAssertEqual(DS4DPadDirection.southEast.rawValue, 3)
        XCTAssertEqual(DS4DPadDirection.south.rawValue, 4)
        XCTAssertEqual(DS4DPadDirection.southWest.rawValue, 5)
        XCTAssertEqual(DS4DPadDirection.west.rawValue, 6)
        XCTAssertEqual(DS4DPadDirection.northWest.rawValue, 7)
    }

    // MARK: - Battery

    func testBatteryPercentageWireless() {
        let bat = DS4BatteryState(level: 4, cableConnected: false)
        XCTAssertEqual(bat.percentage, 50)
    }

    func testBatteryPercentageWired() {
        let bat = DS4BatteryState(level: 11, cableConnected: true)
        XCTAssertEqual(bat.percentage, 100)
    }

    func testBatteryPercentageFull() {
        let bat = DS4BatteryState(level: 8, cableConnected: false)
        XCTAssertEqual(bat.percentage, 100)
    }

    // MARK: - Device Info

    func testModelNameV1() {
        let info = DS4DeviceInfo(productID: DS4DeviceID.ds4V1PID)
        XCTAssertEqual(info.modelName, "DualShock 4 V1")
    }

    func testModelNameV2() {
        let info = DS4DeviceInfo(productID: DS4DeviceID.ds4V2PID)
        XCTAssertEqual(info.modelName, "DualShock 4 V2")
    }

    // MARK: - Codable

    func testInputStateCodable() throws {
        let state = DS4InputState()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DS4InputState.self, from: data)
        XCTAssertEqual(state, decoded)
    }

    func testOutputStateCodable() throws {
        let state = DS4OutputState(rumbleHeavy: 128, ledRed: 255, ledGreen: 0, ledBlue: 64)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DS4OutputState.self, from: data)
        XCTAssertEqual(state, decoded)
    }
}
