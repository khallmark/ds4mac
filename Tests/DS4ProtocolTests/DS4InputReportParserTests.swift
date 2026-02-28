import XCTest
@testable import DS4Protocol

final class DS4InputReportParserTests: XCTestCase {

    // MARK: - Sticks

    func testParseSticksCentered() throws {
        let report = makeUSBReport()
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.leftStick.x, 128)
        XCTAssertEqual(state.leftStick.y, 128)
        XCTAssertEqual(state.rightStick.x, 128)
        XCTAssertEqual(state.rightStick.y, 128)
    }

    func testParseSticksMinMax() throws {
        let report = makeUSBReport(
            leftStickX: 0, leftStickY: 255,
            rightStickX: 255, rightStickY: 0
        )
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.leftStick.x, 0)
        XCTAssertEqual(state.leftStick.y, 255)
        XCTAssertEqual(state.rightStick.x, 255)
        XCTAssertEqual(state.rightStick.y, 0)
    }

    // MARK: - D-Pad

    func testParseDPadAllDirections() throws {
        let directions: [(UInt8, DS4DPadDirection)] = [
            (0, .north), (1, .northEast), (2, .east), (3, .southEast),
            (4, .south), (5, .southWest), (6, .west), (7, .northWest),
            (8, .neutral),
        ]
        for (raw, expected) in directions {
            let report = makeUSBReport(buttons0: raw)
            let state = try DS4InputReportParser.parseUSB(report)
            XCTAssertEqual(state.dpad, expected, "D-pad raw=\(raw) should be \(expected)")
        }
    }

    func testParseDPadInvalidValueDefaultsToNeutral() throws {
        // Values > 8 should map to neutral via the ?? .neutral fallback
        let report = makeUSBReport(buttons0: 0x0F)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.dpad, .neutral)
    }

    // MARK: - Face Buttons (byte 5, high nibble)

    func testParseSquareButton() throws {
        let report = makeUSBReport(buttons0: 0x08 | 0x10)  // neutral d-pad + square
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.square)
        XCTAssertFalse(state.buttons.cross)
        XCTAssertFalse(state.buttons.circle)
        XCTAssertFalse(state.buttons.triangle)
    }

    func testParseCrossButton() throws {
        let report = makeUSBReport(buttons0: 0x08 | 0x20)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.cross)
    }

    func testParseCircleButton() throws {
        let report = makeUSBReport(buttons0: 0x08 | 0x40)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.circle)
    }

    func testParseTriangleButton() throws {
        let report = makeUSBReport(buttons0: 0x08 | 0x80)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.triangle)
    }

    func testParseAllFaceButtons() throws {
        let report = makeUSBReport(buttons0: 0x08 | 0xF0)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.square)
        XCTAssertTrue(state.buttons.cross)
        XCTAssertTrue(state.buttons.circle)
        XCTAssertTrue(state.buttons.triangle)
    }

    // MARK: - Shoulder/Misc Buttons (byte 6)

    func testParseL1() throws {
        let report = makeUSBReport(buttons1: 0x01)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.l1)
    }

    func testParseR1() throws {
        let report = makeUSBReport(buttons1: 0x02)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.r1)
    }

    func testParseL2Digital() throws {
        let report = makeUSBReport(buttons1: 0x04)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.l2)
    }

    func testParseR2Digital() throws {
        let report = makeUSBReport(buttons1: 0x08)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.r2)
    }

    func testParseShare() throws {
        let report = makeUSBReport(buttons1: 0x10)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.share)
    }

    func testParseOptions() throws {
        let report = makeUSBReport(buttons1: 0x20)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.options)
    }

    func testParseL3() throws {
        let report = makeUSBReport(buttons1: 0x40)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.l3)
    }

    func testParseR3() throws {
        let report = makeUSBReport(buttons1: 0x80)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.r3)
    }

    // MARK: - PS & Touchpad Click (byte 7)

    func testParsePSButton() throws {
        let report = makeUSBReport(buttons2: 0x01)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.ps)
    }

    func testParseTouchpadClick() throws {
        let report = makeUSBReport(buttons2: 0x02)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.buttons.touchpadClick)
    }

    func testParseFrameCounter() throws {
        // Frame counter is bits 7:2 of byte 7 (6-bit, 0-63)
        let report = makeUSBReport(buttons2: 0xFC)  // counter = 63
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.frameCounter, 63)
    }

    // MARK: - Triggers

    func testParseTriggersMax() throws {
        let report = makeUSBReport(l2: 255, r2: 255)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.l2Trigger, 255)
        XCTAssertEqual(state.r2Trigger, 255)
    }

    func testParseTriggersZero() throws {
        let report = makeUSBReport(l2: 0, r2: 0)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.l2Trigger, 0)
        XCTAssertEqual(state.r2Trigger, 0)
    }

    // MARK: - Timestamp

    func testParseTimestamp() throws {
        // 0x1234 → lo=0x34, hi=0x12
        let report = makeUSBReport(timestampLo: 0x34, timestampHi: 0x12)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.timestamp, 0x1234)
    }

    // MARK: - IMU

    func testParseGyroPositive() throws {
        let (lo, hi) = int16LEBytes(1000)
        let report = makeUSBReport(gyroPitchLo: lo, gyroPitchHi: hi)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.imu.gyroPitch, 1000)
    }

    func testParseGyroNegative() throws {
        let (lo, hi) = int16LEBytes(-500)
        let report = makeUSBReport(gyroYawLo: lo, gyroYawHi: hi)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.imu.gyroYaw, -500)
    }

    func testParseAccelerometer() throws {
        // At rest, accelY ≈ +8192 (1g)
        let (lo, hi) = int16LEBytes(8192)
        let report = makeUSBReport(accelYLo: lo, accelYHi: hi)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.imu.accelY, 8192)
    }

    // MARK: - Battery

    func testParseBatteryWireless() throws {
        let report = makeUSBReport(batteryByte: 0x05)  // level=5, no cable
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.battery.level, 5)
        XCTAssertFalse(state.battery.cableConnected)
    }

    func testParseBatteryWired() throws {
        let report = makeUSBReport(batteryByte: 0x1A)  // level=10, cable=1
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.battery.level, 10)
        XCTAssertTrue(state.battery.cableConnected)
    }

    func testParseBatteryPeripherals() throws {
        let report = makeUSBReport(batteryByte: 0x60)  // headphones + mic
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.battery.headphones)
        XCTAssertTrue(state.battery.microphone)
    }

    // MARK: - Touchpad

    func testParseTouchpadInactive() throws {
        // bit 7 set = NOT touching
        let touch = makeTouchFingerBytes(active: false, trackingID: 0, x: 0, y: 0)
        let report = makeUSBReport(touch0: touch)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertFalse(state.touchpad.touch0.active)
    }

    func testParseTouchpadActive() throws {
        // bit 7 clear = touching
        let touch = makeTouchFingerBytes(active: true, trackingID: 42, x: 960, y: 471)
        let report = makeUSBReport(touch0: touch)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.touchpad.touch0.active)
        XCTAssertEqual(state.touchpad.touch0.trackingID, 42)
        XCTAssertEqual(state.touchpad.touch0.x, 960)
        XCTAssertEqual(state.touchpad.touch0.y, 471)
    }

    func testParseTouchpadMaxCoordinates() throws {
        let touch = makeTouchFingerBytes(active: true, trackingID: 127, x: 1919, y: 942)
        let report = makeUSBReport(touch0: touch)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertEqual(state.touchpad.touch0.x, 1919)
        XCTAssertEqual(state.touchpad.touch0.y, 942)
        XCTAssertEqual(state.touchpad.touch0.trackingID, 127)
    }

    func testParseTouchpadTwoFingers() throws {
        let t0 = makeTouchFingerBytes(active: true, trackingID: 1, x: 100, y: 200)
        let t1 = makeTouchFingerBytes(active: true, trackingID: 2, x: 1800, y: 900)
        let report = makeUSBReport(touch0: t0, touch1: t1)
        let state = try DS4InputReportParser.parseUSB(report)
        XCTAssertTrue(state.touchpad.touch0.active)
        XCTAssertTrue(state.touchpad.touch1.active)
        XCTAssertEqual(state.touchpad.touch0.x, 100)
        XCTAssertEqual(state.touchpad.touch1.x, 1800)
    }

    // MARK: - Auto-Detect

    func testAutoDetectUSB() throws {
        let report = makeUSBReport()
        let state = try DS4InputReportParser.parse(report)
        XCTAssertEqual(state.dpad, .neutral)
    }

    func testAutoDetectBluetooth() throws {
        let report = makeBTReport()
        let state = try DS4InputReportParser.parse(report)
        XCTAssertEqual(state.dpad, .neutral)
    }

    // MARK: - Error Cases

    func testInvalidLength() {
        let shortReport = [UInt8](repeating: 0, count: 32)
        XCTAssertThrowsError(try DS4InputReportParser.parseUSB(shortReport)) { error in
            if case DS4InputReportParser.ParseError.invalidLength(let expected, let got) = error {
                XCTAssertEqual(expected, 64)
                XCTAssertEqual(got, 32)
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }

    func testInvalidReportID() {
        var report = makeUSBReport()
        report[0] = 0x02  // wrong report ID
        XCTAssertThrowsError(try DS4InputReportParser.parseUSB(report)) { error in
            if case DS4InputReportParser.ParseError.invalidReportID(let expected, let got) = error {
                XCTAssertEqual(expected, 0x01)
                XCTAssertEqual(got, 0x02)
            } else {
                XCTFail("Expected invalidReportID error")
            }
        }
    }

    func testEmptyReport() {
        XCTAssertThrowsError(try DS4InputReportParser.parse([])) { error in
            if case DS4InputReportParser.ParseError.invalidLength = error {
                // expected
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }

    // MARK: - Neutral State

    func testNeutralStateAllDefaults() throws {
        let report = makeUSBReport()
        let state = try DS4InputReportParser.parseUSB(report)

        XCTAssertEqual(state.dpad, .neutral)
        XCTAssertFalse(state.buttons.cross)
        XCTAssertFalse(state.buttons.circle)
        XCTAssertFalse(state.buttons.square)
        XCTAssertFalse(state.buttons.triangle)
        XCTAssertFalse(state.buttons.l1)
        XCTAssertFalse(state.buttons.r1)
        XCTAssertFalse(state.buttons.share)
        XCTAssertFalse(state.buttons.options)
        XCTAssertFalse(state.buttons.ps)
        XCTAssertFalse(state.buttons.touchpadClick)
        XCTAssertEqual(state.l2Trigger, 0)
        XCTAssertEqual(state.r2Trigger, 0)
        XCTAssertFalse(state.touchpad.touch0.active)
        XCTAssertFalse(state.touchpad.touch1.active)
    }
}
