import XCTest
@testable import DS4Protocol

final class DS4CalibrationDataTests: XCTestCase {

    // MARK: - Test Helpers

    /// Build a 37-byte USB calibration report (Report ID 0x02) from individual field values.
    /// Unspecified fields default to zero. Uses the USB interleaved plus/minus layout.
    static func makeCalibrationReport(
        reportID: UInt8 = 0x02,
        gyroPitchBias: Int16 = 0, gyroYawBias: Int16 = 0, gyroRollBias: Int16 = 0,
        gyroPitchPlus: Int16 = 0, gyroPitchMinus: Int16 = 0,
        gyroYawPlus: Int16 = 0, gyroYawMinus: Int16 = 0,
        gyroRollPlus: Int16 = 0, gyroRollMinus: Int16 = 0,
        gyroSpeedPlus: Int16 = 0, gyroSpeedMinus: Int16 = 0,
        accelXPlus: Int16 = 0, accelXMinus: Int16 = 0,
        accelYPlus: Int16 = 0, accelYMinus: Int16 = 0,
        accelZPlus: Int16 = 0, accelZMinus: Int16 = 0
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 37)
        report[0] = reportID

        writeInt16LE(&report, 1, gyroPitchBias)
        writeInt16LE(&report, 3, gyroYawBias)
        writeInt16LE(&report, 5, gyroRollBias)

        // USB layout: interleaved plus/minus per axis
        writeInt16LE(&report, 7, gyroPitchPlus)
        writeInt16LE(&report, 9, gyroPitchMinus)
        writeInt16LE(&report, 11, gyroYawPlus)
        writeInt16LE(&report, 13, gyroYawMinus)
        writeInt16LE(&report, 15, gyroRollPlus)
        writeInt16LE(&report, 17, gyroRollMinus)

        writeInt16LE(&report, 19, gyroSpeedPlus)
        writeInt16LE(&report, 21, gyroSpeedMinus)

        writeInt16LE(&report, 23, accelXPlus)
        writeInt16LE(&report, 25, accelXMinus)
        writeInt16LE(&report, 27, accelYPlus)
        writeInt16LE(&report, 29, accelYMinus)
        writeInt16LE(&report, 31, accelZPlus)
        writeInt16LE(&report, 33, accelZMinus)

        return report
    }

    /// Build a 37-byte BT calibration report (Report ID 0x05) with BT plus/minus layout.
    /// BT layout: all plus values first (pitchPlus, yawPlus, rollPlus), then all minus.
    static func makeBTCalibrationReport(
        gyroPitchBias: Int16 = 0, gyroYawBias: Int16 = 0, gyroRollBias: Int16 = 0,
        gyroPitchPlus: Int16 = 0, gyroYawPlus: Int16 = 0, gyroRollPlus: Int16 = 0,
        gyroPitchMinus: Int16 = 0, gyroYawMinus: Int16 = 0, gyroRollMinus: Int16 = 0,
        gyroSpeedPlus: Int16 = 0, gyroSpeedMinus: Int16 = 0,
        accelXPlus: Int16 = 0, accelXMinus: Int16 = 0,
        accelYPlus: Int16 = 0, accelYMinus: Int16 = 0,
        accelZPlus: Int16 = 0, accelZMinus: Int16 = 0
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 37)
        report[0] = 0x05  // BT Report ID

        writeInt16LE(&report, 1, gyroPitchBias)
        writeInt16LE(&report, 3, gyroYawBias)
        writeInt16LE(&report, 5, gyroRollBias)

        // BT layout: all plus first, then all minus
        writeInt16LE(&report, 7, gyroPitchPlus)
        writeInt16LE(&report, 9, gyroYawPlus)
        writeInt16LE(&report, 11, gyroRollPlus)
        writeInt16LE(&report, 13, gyroPitchMinus)
        writeInt16LE(&report, 15, gyroYawMinus)
        writeInt16LE(&report, 17, gyroRollMinus)

        writeInt16LE(&report, 19, gyroSpeedPlus)
        writeInt16LE(&report, 21, gyroSpeedMinus)

        writeInt16LE(&report, 23, accelXPlus)
        writeInt16LE(&report, 25, accelXMinus)
        writeInt16LE(&report, 27, accelYPlus)
        writeInt16LE(&report, 29, accelYMinus)
        writeInt16LE(&report, 31, accelZPlus)
        writeInt16LE(&report, 33, accelZMinus)

        return report
    }

    /// Write a signed Int16 at the given offset in little-endian byte order.
    private static func writeInt16LE(_ buf: inout [UInt8], _ offset: Int, _ value: Int16) {
        let bits = UInt16(bitPattern: value)
        buf[offset]     = UInt8(bits & 0xFF)
        buf[offset + 1] = UInt8(bits >> 8)
    }

    // MARK: - Known Example Data

    /// Example calibration data from docs/08-Gyroscope-IMU-Feature.md Section 3.2.3.
    /// This uses the USB interleaved layout as described in the task spec.
    static let exampleReport: [UInt8] = makeCalibrationReport(
        gyroPitchBias: 1, gyroYawBias: 0, gyroRollBias: 0,
        gyroPitchPlus: 8839, gyroPitchMinus: -8889,
        gyroYawPlus: -8837, gyroYawMinus: 8893,
        gyroRollPlus: 8882, gyroRollMinus: -8893,
        gyroSpeedPlus: 540, gyroSpeedMinus: 540,
        accelXPlus: 7807, accelXMinus: -8402,
        accelYPlus: 8032, accelYMinus: -8116,
        accelZPlus: 7482, accelZMinus: -8506
    )

    // MARK: - USB Parsing Tests

    func testParseUSBReportID() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        // If we got here without error, report ID was accepted
        XCTAssertEqual(cal.gyroPitchBias, 1)
    }

    func testParseUSBGyroBias() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertEqual(cal.gyroPitchBias, 1)
        XCTAssertEqual(cal.gyroYawBias, 0)
        XCTAssertEqual(cal.gyroRollBias, 0)
    }

    func testParseUSBGyroReferences() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertEqual(cal.gyroPitchPlus, 8839)
        XCTAssertEqual(cal.gyroPitchMinus, -8889)
        XCTAssertEqual(cal.gyroYawPlus, -8837)
        XCTAssertEqual(cal.gyroYawMinus, 8893)
        XCTAssertEqual(cal.gyroRollPlus, 8882)
        XCTAssertEqual(cal.gyroRollMinus, -8893)
    }

    func testParseUSBGyroSpeed() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertEqual(cal.gyroSpeedPlus, 540)
        XCTAssertEqual(cal.gyroSpeedMinus, 540)
    }

    func testParseUSBAccelReferences() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertEqual(cal.accelXPlus, 7807)
        XCTAssertEqual(cal.accelXMinus, -8402)
        XCTAssertEqual(cal.accelYPlus, 8032)
        XCTAssertEqual(cal.accelYMinus, -8116)
        XCTAssertEqual(cal.accelZPlus, 7482)
        XCTAssertEqual(cal.accelZMinus, -8506)
    }

    // MARK: - Bluetooth Parsing Tests

    func testParseBTLayoutDifference() throws {
        // BT layout: pitchPlus, yawPlus, rollPlus first, then minus values
        let report = Self.makeBTCalibrationReport(
            gyroPitchBias: 10, gyroYawBias: 20, gyroRollBias: 30,
            gyroPitchPlus: 8000, gyroYawPlus: 8100, gyroRollPlus: 8200,
            gyroPitchMinus: -8000, gyroYawMinus: -8100, gyroRollMinus: -8200,
            gyroSpeedPlus: 540, gyroSpeedMinus: 540,
            accelXPlus: 7800, accelXMinus: -8400,
            accelYPlus: 8000, accelYMinus: -8100,
            accelZPlus: 7500, accelZMinus: -8500
        )

        let cal = try DS4CalibrationDataParser.parseBluetooth(report)
        XCTAssertEqual(cal.gyroPitchBias, 10)
        XCTAssertEqual(cal.gyroYawBias, 20)
        XCTAssertEqual(cal.gyroRollBias, 30)
        XCTAssertEqual(cal.gyroPitchPlus, 8000)
        XCTAssertEqual(cal.gyroYawPlus, 8100)
        XCTAssertEqual(cal.gyroRollPlus, 8200)
        XCTAssertEqual(cal.gyroPitchMinus, -8000)
        XCTAssertEqual(cal.gyroYawMinus, -8100)
        XCTAssertEqual(cal.gyroRollMinus, -8200)
    }

    func testParseBTInvalidReportID() {
        // USB report ID passed to BT parser should fail
        XCTAssertThrowsError(try DS4CalibrationDataParser.parseBluetooth(Self.exampleReport)) { error in
            if case DS4CalibrationDataParser.ParseError.invalidReportID(let expected, let got) = error {
                XCTAssertEqual(expected, 0x05)
                XCTAssertEqual(got, 0x02)
            } else {
                XCTFail("Expected invalidReportID error")
            }
        }
    }

    // MARK: - Gyro Calibration Tests

    func testCalibrateGyroZeroAtBias() throws {
        // When raw value equals the bias, calibrated output should be 0 (controller at rest)
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)

        let pitchDPS = cal.calibrateGyro(axis: .pitch, rawValue: cal.gyroPitchBias)
        XCTAssertEqual(pitchDPS, 0.0, accuracy: 0.001, "Gyro at bias should read 0 deg/s")

        let yawDPS = cal.calibrateGyro(axis: .yaw, rawValue: cal.gyroYawBias)
        XCTAssertEqual(yawDPS, 0.0, accuracy: 0.001, "Gyro at bias should read 0 deg/s")

        let rollDPS = cal.calibrateGyro(axis: .roll, rawValue: cal.gyroRollBias)
        XCTAssertEqual(rollDPS, 0.0, accuracy: 0.001, "Gyro at bias should read 0 deg/s")
    }

    func testCalibrateGyroSymmetric() throws {
        // Symmetric calibration: equal plus/minus and speed values
        let report = Self.makeCalibrationReport(
            gyroPitchBias: 0,
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroYawPlus: 1000, gyroYawMinus: -1000,
            gyroRollPlus: 1000, gyroRollMinus: -1000,
            gyroSpeedPlus: 1000, gyroSpeedMinus: 1000
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        // With symmetric calibration: calibrated = raw * (1000 + 1000) / (1000 - (-1000))
        //                                        = raw * 2000 / 2000 = raw
        let result = cal.calibrateGyro(axis: .pitch, rawValue: 500)
        XCTAssertEqual(result, 500.0, accuracy: 0.001)
    }

    func testCalibrateGyroNegativeRawValue() throws {
        let report = Self.makeCalibrationReport(
            gyroPitchBias: 0,
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroSpeedPlus: 1000, gyroSpeedMinus: 1000
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        let result = cal.calibrateGyro(axis: .pitch, rawValue: -750)
        XCTAssertEqual(result, -750.0, accuracy: 0.001)
    }

    func testCalibrateGyroWithDocExampleValues() throws {
        // From docs/08-Gyroscope-IMU-Feature.md Section 3.3.1:
        // pitchBias=1, pitchPlus=8839, pitchMinus=-8889, speedPlus=540, speedMinus=540
        // calibrated_pitch = (raw - 1) * (540 + 540) / (8839 - (-8889))
        //                  = (raw - 1) * 1080 / 17728
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)

        // Test with raw = 1 (bias): should be 0
        let atBias = cal.calibrateGyro(axis: .pitch, rawValue: 1)
        XCTAssertEqual(atBias, 0.0, accuracy: 0.001)

        // Test with a non-zero raw value
        // (100 - 1) * 1080 / 17728 = 99 * 1080 / 17728 = 106920 / 17728 ≈ 6.031
        let atRaw100 = cal.calibrateGyro(axis: .pitch, rawValue: 100)
        XCTAssertEqual(atRaw100, 99.0 * 1080.0 / 17728.0, accuracy: 0.001)
    }

    // MARK: - Accel Calibration Tests

    func testCalibrateAccelAtRest() throws {
        // For a controller at rest, one axis should read ~1g.
        // Using symmetric references: plus=8192, minus=-8192
        // center = (8192 + (-8192)) / 2 = 0
        // halfRange = (8192 - (-8192)) / 2 = 8192
        // At rest with raw=8192: calibrated = (8192 - 0) / 8192 = 1.0g
        let report = Self.makeCalibrationReport(
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroYawPlus: 1000, gyroYawMinus: -1000,
            gyroRollPlus: 1000, gyroRollMinus: -1000,
            gyroSpeedPlus: 540, gyroSpeedMinus: 540,
            accelXPlus: 8192, accelXMinus: -8192,
            accelYPlus: 8192, accelYMinus: -8192,
            accelZPlus: 8192, accelZMinus: -8192
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        let yG = cal.calibrateAccel(axis: DS4IMUAxis.yaw, rawValue: 8192)
        XCTAssertEqual(yG, 1.0, accuracy: 0.001, "At-rest accel should read ~1.0g")
    }

    func testCalibrateAccelNegativeOneG() throws {
        // With symmetric calibration, raw=-8192 should yield -1.0g
        let report = Self.makeCalibrationReport(
            gyroPitchPlus: 1, gyroPitchMinus: -1,
            gyroYawPlus: 1, gyroYawMinus: -1,
            gyroRollPlus: 1, gyroRollMinus: -1,
            accelYPlus: 8192, accelYMinus: -8192
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        let result = cal.calibrateAccel(axis: DS4IMUAxis.yaw, rawValue: -8192)
        XCTAssertEqual(result, -1.0, accuracy: 0.001)
    }

    func testCalibrateAccelZeroAtCenter() throws {
        // When raw value equals the center point, calibrated should be 0
        let report = Self.makeCalibrationReport(
            gyroPitchPlus: 1, gyroPitchMinus: -1,
            gyroYawPlus: 1, gyroYawMinus: -1,
            gyroRollPlus: 1, gyroRollMinus: -1,
            accelXPlus: 8192, accelXMinus: -8192
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        // Center = (8192 + (-8192)) / 2 = 0
        let result = cal.calibrateAccel(axis: DS4IMUAxis.pitch, rawValue: 0)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testCalibrateAccelWithAsymmetricReferences() throws {
        // Real controllers have slightly asymmetric calibration
        // accelXPlus=7807, accelXMinus=-8402 (from example data)
        // center = (7807 + (-8402)) / 2 = -595 / 2 = -297 (integer division)
        // range = 7807 - (-8402) = 16209
        // halfRange = 16209 / 2.0 = 8104.5
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)

        // At the plus reference point: should be approximately +1g
        let atPlus = cal.calibrateAccel(axis: .pitch, rawValue: 7807)
        // (7807 - (-297)) / 8104.5 = 8104 / 8104.5 ≈ 0.99994
        XCTAssertEqual(atPlus, 1.0, accuracy: 0.01)

        // At the minus reference point: should be approximately -1g
        let atMinus = cal.calibrateAccel(axis: .pitch, rawValue: -8402)
        // (-8402 - (-297)) / 8104.5 = -8105 / 8104.5 ≈ -1.00006
        XCTAssertEqual(atMinus, -1.0, accuracy: 0.01)
    }

    // MARK: - Validation

    func testIsValidWithGoodData() throws {
        let cal = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertTrue(cal.isValid)
    }

    func testIsValidWithZeroData() {
        let cal = DS4CalibrationData()
        XCTAssertFalse(cal.isValid, "All-zero calibration should be invalid (zero denominators)")
    }

    func testIsValidWithOneZeroDenominator() throws {
        // accelZ has zero range (plus == minus), so isValid should be false
        let report = Self.makeCalibrationReport(
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroYawPlus: 1000, gyroYawMinus: -1000,
            gyroRollPlus: 1000, gyroRollMinus: -1000,
            gyroSpeedPlus: 540, gyroSpeedMinus: 540,
            accelXPlus: 8192, accelXMinus: -8192,
            accelYPlus: 8192, accelYMinus: -8192,
            accelZPlus: 0, accelZMinus: 0  // zero range!
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)
        XCTAssertFalse(cal.isValid)
    }

    // MARK: - Calibration Fallback on Zero Denominator

    func testCalibrateGyroZeroDenomFallback() {
        // When plus == minus (zero denominator), calibrateGyro should return raw value
        let cal = DS4CalibrationData(
            gyroPitchPlus: 100, gyroPitchMinus: 100  // same: denom = 0
        )
        let result = cal.calibrateGyro(axis: .pitch, rawValue: 42)
        XCTAssertEqual(result, 42.0)
    }

    func testCalibrateAccelZeroDenomFallback() {
        // When plus == minus (zero denominator), calibrateAccel should return raw value
        let cal = DS4CalibrationData(
            accelXPlus: 100, accelXMinus: 100  // same: denom = 0
        )
        let result = cal.calibrateAccel(axis: .pitch, rawValue: 42)
        XCTAssertEqual(result, 42.0)
    }

    // MARK: - Error Cases

    func testInvalidLength() {
        let shortReport = [UInt8](repeating: 0, count: 20)
        XCTAssertThrowsError(try DS4CalibrationDataParser.parseUSB(shortReport)) { error in
            if case DS4CalibrationDataParser.ParseError.invalidLength(let expected, let got) = error {
                XCTAssertEqual(expected, 37)
                XCTAssertEqual(got, 20)
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }

    func testInvalidReportID() {
        var report = Self.exampleReport
        report[0] = 0xFF  // wrong report ID
        XCTAssertThrowsError(try DS4CalibrationDataParser.parseUSB(report)) { error in
            if case DS4CalibrationDataParser.ParseError.invalidReportID(let expected, let got) = error {
                XCTAssertEqual(expected, 0x02)
                XCTAssertEqual(got, 0xFF)
            } else {
                XCTFail("Expected invalidReportID error")
            }
        }
    }

    func testEmptyReport() {
        XCTAssertThrowsError(try DS4CalibrationDataParser.parseUSB([])) { error in
            if case DS4CalibrationDataParser.ParseError.invalidLength(let expected, let got) = error {
                XCTAssertEqual(expected, 37)
                XCTAssertEqual(got, 0)
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let original = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DS4CalibrationData.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripPreservesAllFields() throws {
        let original = DS4CalibrationData(
            gyroPitchBias: 1, gyroYawBias: 2, gyroRollBias: 3,
            gyroPitchPlus: 100, gyroYawPlus: 200, gyroRollPlus: 300,
            gyroPitchMinus: -100, gyroYawMinus: -200, gyroRollMinus: -300,
            gyroSpeedPlus: 540, gyroSpeedMinus: 540,
            accelXPlus: 8192, accelXMinus: -8192,
            accelYPlus: 8192, accelYMinus: -8192,
            accelZPlus: 8192, accelZMinus: -8192
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DS4CalibrationData.self, from: data)

        XCTAssertEqual(decoded.gyroPitchBias, 1)
        XCTAssertEqual(decoded.gyroYawBias, 2)
        XCTAssertEqual(decoded.gyroRollBias, 3)
        XCTAssertEqual(decoded.gyroPitchPlus, 100)
        XCTAssertEqual(decoded.gyroYawPlus, 200)
        XCTAssertEqual(decoded.gyroRollPlus, 300)
        XCTAssertEqual(decoded.gyroPitchMinus, -100)
        XCTAssertEqual(decoded.gyroYawMinus, -200)
        XCTAssertEqual(decoded.gyroRollMinus, -300)
        XCTAssertEqual(decoded.gyroSpeedPlus, 540)
        XCTAssertEqual(decoded.gyroSpeedMinus, 540)
        XCTAssertEqual(decoded.accelXPlus, 8192)
        XCTAssertEqual(decoded.accelXMinus, -8192)
        XCTAssertEqual(decoded.accelYPlus, 8192)
        XCTAssertEqual(decoded.accelYMinus, -8192)
        XCTAssertEqual(decoded.accelZPlus, 8192)
        XCTAssertEqual(decoded.accelZMinus, -8192)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Equatable

    func testEquatable() throws {
        let cal1 = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        let cal2 = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        XCTAssertEqual(cal1, cal2)
    }

    func testNotEqualWhenDifferent() throws {
        let cal1 = try DS4CalibrationDataParser.parseUSB(Self.exampleReport)
        var report2 = Self.exampleReport
        // Change one byte (gyro pitch bias)
        report2[1] = 0xFF
        report2[2] = 0x7F  // +32767
        let cal2 = try DS4CalibrationDataParser.parseUSB(report2)
        XCTAssertNotEqual(cal1, cal2)
    }

    // MARK: - IMU Axis Enum

    func testIMUAxisRawValues() {
        XCTAssertEqual(DS4IMUAxis.pitch.rawValue, "pitch")
        XCTAssertEqual(DS4IMUAxis.yaw.rawValue, "yaw")
        XCTAssertEqual(DS4IMUAxis.roll.rawValue, "roll")
    }

    func testIMUAxisCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for axis in [DS4IMUAxis.pitch, .yaw, .roll] {
            let data = try encoder.encode(axis)
            let decoded = try decoder.decode(DS4IMUAxis.self, from: data)
            XCTAssertEqual(axis, decoded)
        }
    }

    // MARK: - All Axes Calibration

    func testCalibrateAllGyroAxes() throws {
        let report = Self.makeCalibrationReport(
            gyroPitchBias: 10, gyroYawBias: 20, gyroRollBias: 30,
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroYawPlus: 1000, gyroYawMinus: -1000,
            gyroRollPlus: 1000, gyroRollMinus: -1000,
            gyroSpeedPlus: 1000, gyroSpeedMinus: 1000
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        // Pitch: (500 - 10) * 2000 / 2000 = 490
        let pitch = cal.calibrateGyro(axis: .pitch, rawValue: 500)
        XCTAssertEqual(pitch, 490.0, accuracy: 0.001)

        // Yaw: (500 - 20) * 2000 / 2000 = 480
        let yaw = cal.calibrateGyro(axis: .yaw, rawValue: 500)
        XCTAssertEqual(yaw, 480.0, accuracy: 0.001)

        // Roll: (500 - 30) * 2000 / 2000 = 470
        let roll = cal.calibrateGyro(axis: .roll, rawValue: 500)
        XCTAssertEqual(roll, 470.0, accuracy: 0.001)
    }

    func testCalibrateAllAccelAxes() throws {
        let report = Self.makeCalibrationReport(
            gyroPitchPlus: 1, gyroPitchMinus: -1,
            gyroYawPlus: 1, gyroYawMinus: -1,
            gyroRollPlus: 1, gyroRollMinus: -1,
            accelXPlus: 8192, accelXMinus: -8192,
            accelYPlus: 8192, accelYMinus: -8192,
            accelZPlus: 8192, accelZMinus: -8192
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        // All axes with raw=8192 should yield 1.0g
        XCTAssertEqual(cal.calibrateAccel(axis: .pitch, rawValue: 8192), 1.0, accuracy: 0.001)
        XCTAssertEqual(cal.calibrateAccel(axis: .yaw, rawValue: 8192), 1.0, accuracy: 0.001)
        XCTAssertEqual(cal.calibrateAccel(axis: .roll, rawValue: 8192), 1.0, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    func testParseReportLargerThan37Bytes() throws {
        // Parser should accept reports that are longer than the minimum 37 bytes
        let largerReport = Self.exampleReport + [UInt8](repeating: 0, count: 10)
        XCTAssertEqual(largerReport.count, 47)
        let cal = try DS4CalibrationDataParser.parseUSB(largerReport)
        XCTAssertEqual(cal.gyroPitchBias, 1)
    }

    func testCalibrateGyroMaxInt16() throws {
        let report = Self.makeCalibrationReport(
            gyroPitchBias: 0,
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroSpeedPlus: 1000, gyroSpeedMinus: 1000
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        let result = cal.calibrateGyro(axis: .pitch, rawValue: Int16.max)
        XCTAssertEqual(result, Double(Int16.max), accuracy: 0.001)
    }

    func testCalibrateGyroMinInt16() throws {
        let report = Self.makeCalibrationReport(
            gyroPitchBias: 0,
            gyroPitchPlus: 1000, gyroPitchMinus: -1000,
            gyroSpeedPlus: 1000, gyroSpeedMinus: 1000
        )
        let cal = try DS4CalibrationDataParser.parseUSB(report)

        let result = cal.calibrateGyro(axis: .pitch, rawValue: Int16.min)
        XCTAssertEqual(result, Double(Int16.min), accuracy: 0.001)
    }
}
