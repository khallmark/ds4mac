import XCTest
@testable import DS4Protocol

final class DS4OutputReportBuilderTests: XCTestCase {

    // MARK: - USB Output Report

    func testUSBReportID() {
        let report = DS4OutputReportBuilder.buildUSB(DS4OutputState())
        XCTAssertEqual(report[0], 0x05)
    }

    func testUSBReportLength() {
        let report = DS4OutputReportBuilder.buildUSB(DS4OutputState())
        XCTAssertEqual(report.count, 32)
    }

    func testUSBFeatureFlags() {
        let report = DS4OutputReportBuilder.buildUSB(DS4OutputState())
        XCTAssertEqual(report[1], 0x07)  // rumble + lightbar + flash
    }

    func testUSBRumbleValues() {
        let state = DS4OutputState(rumbleHeavy: 200, rumbleLight: 100)
        let report = DS4OutputReportBuilder.buildUSB(state)
        // Note: byte 4 = light (right/weak), byte 5 = heavy (left/strong)
        XCTAssertEqual(report[4], 100)  // light/weak motor
        XCTAssertEqual(report[5], 200)  // heavy/strong motor
    }

    func testUSBLEDValues() {
        let state = DS4OutputState(ledRed: 255, ledGreen: 128, ledBlue: 64)
        let report = DS4OutputReportBuilder.buildUSB(state)
        XCTAssertEqual(report[6], 255)  // red
        XCTAssertEqual(report[7], 128)  // green
        XCTAssertEqual(report[8], 64)   // blue
    }

    func testUSBFlashValues() {
        let state = DS4OutputState(flashOn: 100, flashOff: 50)
        let report = DS4OutputReportBuilder.buildUSB(state)
        XCTAssertEqual(report[9], 100)   // flash on
        XCTAssertEqual(report[10], 50)   // flash off
    }

    func testUSBReportAllZero() {
        let state = DS4OutputState()
        let report = DS4OutputReportBuilder.buildUSB(state)
        // Only report ID and feature flags should be non-zero
        XCTAssertEqual(report[0], 0x05)
        XCTAssertEqual(report[1], 0x07)
        XCTAssertEqual(report[2], 0x04)
        for i in 3..<32 where i != 0 && i != 1 && i != 2 {
            XCTAssertEqual(report[i], 0, "Byte \(i) should be 0")
        }
    }

    func testUSBReportMaxValues() {
        let state = DS4OutputState(
            rumbleHeavy: 255, rumbleLight: 255,
            ledRed: 255, ledGreen: 255, ledBlue: 255,
            flashOn: 255, flashOff: 255
        )
        let report = DS4OutputReportBuilder.buildUSB(state)
        XCTAssertEqual(report[4], 255)
        XCTAssertEqual(report[5], 255)
        XCTAssertEqual(report[6], 255)
        XCTAssertEqual(report[7], 255)
        XCTAssertEqual(report[8], 255)
        XCTAssertEqual(report[9], 255)
        XCTAssertEqual(report[10], 255)
    }

    // MARK: - Bluetooth Output Report

    func testBTReportID() {
        let report = DS4OutputReportBuilder.buildBluetooth(DS4OutputState())
        XCTAssertEqual(report[0], 0x11)
    }

    func testBTReportLength() {
        let report = DS4OutputReportBuilder.buildBluetooth(DS4OutputState())
        XCTAssertEqual(report.count, 78)
    }

    func testBTHeaderFlags() {
        let report = DS4OutputReportBuilder.buildBluetooth(DS4OutputState())
        XCTAssertEqual(report[1], 0xC0)  // EnableHID + EnableCRC
        XCTAssertEqual(report[2], 0x00)  // no audio
        XCTAssertEqual(report[3], 0x07)  // feature flags
    }

    func testBTRumbleOffset() {
        // BT motor bytes are at offset 6 and 7 (+2 vs USB's 4 and 5)
        let state = DS4OutputState(rumbleHeavy: 200, rumbleLight: 100)
        let report = DS4OutputReportBuilder.buildBluetooth(state)
        XCTAssertEqual(report[6], 100)  // light/weak (+2 from USB byte 4)
        XCTAssertEqual(report[7], 200)  // heavy/strong (+2 from USB byte 5)
    }

    func testBTLEDOffset() {
        let state = DS4OutputState(ledRed: 255, ledGreen: 128, ledBlue: 64)
        let report = DS4OutputReportBuilder.buildBluetooth(state)
        XCTAssertEqual(report[8], 255)   // red (+2 from USB byte 6)
        XCTAssertEqual(report[9], 128)   // green
        XCTAssertEqual(report[10], 64)   // blue
    }

    func testBTFlashOffset() {
        let state = DS4OutputState(flashOn: 100, flashOff: 50)
        let report = DS4OutputReportBuilder.buildBluetooth(state)
        XCTAssertEqual(report[11], 100)  // flash on (+2 from USB byte 9)
        XCTAssertEqual(report[12], 50)   // flash off
    }

    func testBTReportHasValidCRC() {
        let state = DS4OutputState(rumbleHeavy: 128, ledRed: 255)
        let report = DS4OutputReportBuilder.buildBluetooth(state)
        XCTAssertTrue(DS4CRC32.validateOutputReport(report))
    }

    func testBTReportDifferentStatesDifferentCRCs() {
        let report1 = DS4OutputReportBuilder.buildBluetooth(
            DS4OutputState(ledRed: 255)
        )
        let report2 = DS4OutputReportBuilder.buildBluetooth(
            DS4OutputState(ledBlue: 255)
        )
        // CRC bytes [74..77] should differ
        XCTAssertNotEqual(
            Array(report1[74...77]),
            Array(report2[74...77])
        )
    }

    // MARK: - Motor Ordering Sanity Check

    func testMotorOrderingIsRightThenLeft() {
        // This is a common source of confusion: byte order is light(right) then heavy(left)
        let state = DS4OutputState(rumbleHeavy: 200, rumbleLight: 50)
        let usbReport = DS4OutputReportBuilder.buildUSB(state)
        let btReport = DS4OutputReportBuilder.buildBluetooth(state)

        // USB: byte 4 = light(50), byte 5 = heavy(200)
        XCTAssertEqual(usbReport[4], 50, "USB byte 4 should be light/right motor")
        XCTAssertEqual(usbReport[5], 200, "USB byte 5 should be heavy/left motor")

        // BT: byte 6 = light(50), byte 7 = heavy(200)
        XCTAssertEqual(btReport[6], 50, "BT byte 6 should be light/right motor")
        XCTAssertEqual(btReport[7], 200, "BT byte 7 should be heavy/left motor")
    }
}
