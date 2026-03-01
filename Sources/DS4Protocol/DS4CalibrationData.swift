// DS4CalibrationData.swift — Parse IMU calibration feature report (0x02 USB / 0x05 BT)
// Reference: docs/04-DS4-USB-Protocol.md Section 4.2, docs/08-Gyroscope-IMU-Feature.md Section 3

/// IMU axis identifier for gyroscope or accelerometer.
public enum DS4IMUAxis: String, Codable, Sendable {
    case pitch  // gyro X / accel X
    case yaw    // gyro Y / accel Y
    case roll   // gyro Z / accel Z
}

/// Parsed IMU calibration data from Feature Report 0x02 (USB, 37 bytes).
///
/// The calibration report contains bias values, positive/negative reference points,
/// and speed references that allow raw 16-bit IMU readings to be converted into
/// physical units (degrees/sec for gyroscope, g-force for accelerometer).
///
/// Layout (37 bytes including report ID):
/// - Byte 0: Report ID (0x02)
/// - Bytes 1-6: Gyro bias (pitch, yaw, roll) as int16 LE
/// - Bytes 7-18: Gyro plus/minus references (int16 LE)
/// - Bytes 19-22: Gyro speed plus/minus (int16 LE)
/// - Bytes 23-34: Accel plus/minus references (int16 LE)
/// - Bytes 35-36: Reserved
public struct DS4CalibrationData: Codable, Equatable, Sendable {

    // MARK: - Gyroscope Calibration Values

    /// Zero-rate bias for each gyro axis (subtracted from raw readings).
    public var gyroPitchBias: Int16
    public var gyroYawBias: Int16
    public var gyroRollBias: Int16

    /// Positive reference rotation for each gyro axis.
    public var gyroPitchPlus: Int16
    public var gyroYawPlus: Int16
    public var gyroRollPlus: Int16

    /// Negative reference rotation for each gyro axis.
    public var gyroPitchMinus: Int16
    public var gyroYawMinus: Int16
    public var gyroRollMinus: Int16

    /// Speed reference values (shared across all gyro axes).
    public var gyroSpeedPlus: Int16
    public var gyroSpeedMinus: Int16

    // MARK: - Accelerometer Calibration Values

    /// Positive 1g reference for each accel axis.
    public var accelXPlus: Int16
    public var accelXMinus: Int16
    public var accelYPlus: Int16
    public var accelYMinus: Int16
    public var accelZPlus: Int16
    public var accelZMinus: Int16

    // MARK: - Init

    public init(
        gyroPitchBias: Int16 = 0, gyroYawBias: Int16 = 0, gyroRollBias: Int16 = 0,
        gyroPitchPlus: Int16 = 0, gyroYawPlus: Int16 = 0, gyroRollPlus: Int16 = 0,
        gyroPitchMinus: Int16 = 0, gyroYawMinus: Int16 = 0, gyroRollMinus: Int16 = 0,
        gyroSpeedPlus: Int16 = 0, gyroSpeedMinus: Int16 = 0,
        accelXPlus: Int16 = 0, accelXMinus: Int16 = 0,
        accelYPlus: Int16 = 0, accelYMinus: Int16 = 0,
        accelZPlus: Int16 = 0, accelZMinus: Int16 = 0
    ) {
        self.gyroPitchBias = gyroPitchBias; self.gyroYawBias = gyroYawBias; self.gyroRollBias = gyroRollBias
        self.gyroPitchPlus = gyroPitchPlus; self.gyroYawPlus = gyroYawPlus; self.gyroRollPlus = gyroRollPlus
        self.gyroPitchMinus = gyroPitchMinus; self.gyroYawMinus = gyroYawMinus; self.gyroRollMinus = gyroRollMinus
        self.gyroSpeedPlus = gyroSpeedPlus; self.gyroSpeedMinus = gyroSpeedMinus
        self.accelXPlus = accelXPlus; self.accelXMinus = accelXMinus
        self.accelYPlus = accelYPlus; self.accelYMinus = accelYMinus
        self.accelZPlus = accelZPlus; self.accelZMinus = accelZMinus
    }

    // MARK: - Calibration Application

    /// Calibrate a raw gyroscope reading to degrees per second.
    ///
    /// Formula: `(rawValue - bias) * (gyroSpeedPlus + gyroSpeedMinus) / abs(plus - minus)`
    ///
    /// Uses absolute value of denominator to handle DS4v1 controllers (PID 0x05C4)
    /// with inverted yaw calibration data (docs/08-Gyroscope-IMU-Feature.md Section 3.3.4).
    ///
    /// - Parameters:
    ///   - axis: Which gyro axis (.pitch, .yaw, .roll)
    ///   - rawValue: Raw signed 16-bit gyroscope reading from the input report
    /// - Returns: Calibrated angular velocity in degrees per second
    public func calibrateGyro(axis: DS4IMUAxis, rawValue: Int16) -> Double {
        let bias: Int16
        let plus: Int16
        let minus: Int16

        switch axis {
        case .pitch:
            bias = gyroPitchBias; plus = gyroPitchPlus; minus = gyroPitchMinus
        case .yaw:
            bias = gyroYawBias; plus = gyroYawPlus; minus = gyroYawMinus
        case .roll:
            bias = gyroRollBias; plus = gyroRollPlus; minus = gyroRollMinus
        }

        let denom = Int32(plus) - Int32(minus)
        guard denom != 0 else { return Double(rawValue) }

        let speed2x = Int32(gyroSpeedPlus) + Int32(gyroSpeedMinus)
        let adjusted = Int32(rawValue) - Int32(bias)
        // abs() handles DS4v1 inverted yaw axis (Section 3.3.4)
        return Double(adjusted) * Double(speed2x) / Double(abs(denom))
    }

    /// Calibrate a raw accelerometer reading to g-force.
    ///
    /// Formula: `(rawValue - ((plus + minus) / 2)) / abs((plus - minus) / 2)`
    ///
    /// Uses absolute value of halfRange to handle DS4v1 controllers where
    /// plus/minus calibration references may be inverted (plus < minus).
    /// The sign of the result is determined by `(rawValue - center)`, not
    /// by the ordering of plus/minus references.
    ///
    /// - Parameters:
    ///   - axis: Which accel axis (.pitch maps to X, .yaw to Y, .roll to Z)
    ///   - rawValue: Raw signed 16-bit accelerometer reading from the input report
    /// - Returns: Calibrated acceleration in g-force units
    public func calibrateAccel(axis: DS4IMUAxis, rawValue: Int16) -> Double {
        let plus: Int16
        let minus: Int16

        switch axis {
        case .pitch:
            plus = accelXPlus; minus = accelXMinus
        case .yaw:
            plus = accelYPlus; minus = accelYMinus
        case .roll:
            plus = accelZPlus; minus = accelZMinus
        }

        let range = Int32(plus) - Int32(minus)
        guard range != 0 else { return Double(rawValue) }

        let center = (Int32(plus) + Int32(minus)) / 2
        // abs() handles DS4v1 controllers with inverted plus/minus references
        let halfRange = abs(Double(range) / 2.0)
        return Double(Int32(rawValue) - center) / halfRange
    }

    /// Whether the calibration data has valid (non-zero) denominators for all axes.
    public var isValid: Bool {
        (Int32(gyroPitchPlus) - Int32(gyroPitchMinus)) != 0
            && (Int32(gyroYawPlus) - Int32(gyroYawMinus)) != 0
            && (Int32(gyroRollPlus) - Int32(gyroRollMinus)) != 0
            && (Int32(accelXPlus) - Int32(accelXMinus)) != 0
            && (Int32(accelYPlus) - Int32(accelYMinus)) != 0
            && (Int32(accelZPlus) - Int32(accelZMinus)) != 0
    }
}

// MARK: - Parser

/// Parses raw HID feature report bytes into structured DS4CalibrationData.
public enum DS4CalibrationDataParser {

    public enum ParseError: Error, Equatable, Sendable {
        case invalidLength(expected: Int, got: Int)
        case invalidReportID(expected: UInt8, got: UInt8)
    }

    /// Parse a 37-byte USB calibration feature report (Report ID 0x02).
    ///
    /// Uses the USB (alternate) layout where plus/minus values are interleaved per axis:
    /// bytes 7-8: pitchPlus, 9-10: pitchMinus, 11-12: yawPlus, 13-14: yawMinus, etc.
    public static func parseUSB(_ data: [UInt8]) throws -> DS4CalibrationData {
        guard data.count >= DS4ReportSize.calibration else {
            throw ParseError.invalidLength(expected: DS4ReportSize.calibration, got: data.count)
        }
        guard data[0] == DS4ReportID.calibrationUSB else {
            throw ParseError.invalidReportID(expected: DS4ReportID.calibrationUSB, got: data[0])
        }

        // Gyro bias: bytes 1-6
        let pitchBias = readInt16LE(data, 1)
        let yawBias   = readInt16LE(data, 3)
        let rollBias  = readInt16LE(data, 5)

        // USB alternate layout: interleaved plus/minus per axis
        let pitchPlus  = readInt16LE(data, 7)
        let pitchMinus = readInt16LE(data, 9)
        let yawPlus    = readInt16LE(data, 11)
        let yawMinus   = readInt16LE(data, 13)
        let rollPlus   = readInt16LE(data, 15)
        let rollMinus  = readInt16LE(data, 17)

        // Gyro speed: bytes 19-22
        let speedPlus  = readInt16LE(data, 19)
        let speedMinus = readInt16LE(data, 21)

        // Accel references: bytes 23-34
        let accelXPlus  = readInt16LE(data, 23)
        let accelXMinus = readInt16LE(data, 25)
        let accelYPlus  = readInt16LE(data, 27)
        let accelYMinus = readInt16LE(data, 29)
        let accelZPlus  = readInt16LE(data, 31)
        let accelZMinus = readInt16LE(data, 33)

        return DS4CalibrationData(
            gyroPitchBias: pitchBias, gyroYawBias: yawBias, gyroRollBias: rollBias,
            gyroPitchPlus: pitchPlus, gyroYawPlus: yawPlus, gyroRollPlus: rollPlus,
            gyroPitchMinus: pitchMinus, gyroYawMinus: yawMinus, gyroRollMinus: rollMinus,
            gyroSpeedPlus: speedPlus, gyroSpeedMinus: speedMinus,
            accelXPlus: accelXPlus, accelXMinus: accelXMinus,
            accelYPlus: accelYPlus, accelYMinus: accelYMinus,
            accelZPlus: accelZPlus, accelZMinus: accelZMinus
        )
    }

    /// Parse a Bluetooth calibration feature report (Report ID 0x05).
    ///
    /// Uses the BT layout where all plus values come first, then all minus values:
    /// bytes 7-12: pitchPlus, yawPlus, rollPlus; bytes 13-18: pitchMinus, yawMinus, rollMinus.
    public static func parseBluetooth(_ data: [UInt8]) throws -> DS4CalibrationData {
        guard data.count >= DS4ReportSize.calibration else {
            throw ParseError.invalidLength(expected: DS4ReportSize.calibration, got: data.count)
        }
        guard data[0] == DS4ReportID.calibrationBT else {
            throw ParseError.invalidReportID(expected: DS4ReportID.calibrationBT, got: data[0])
        }

        // Gyro bias: bytes 1-6
        let pitchBias = readInt16LE(data, 1)
        let yawBias   = readInt16LE(data, 3)
        let rollBias  = readInt16LE(data, 5)

        // BT layout: all plus first, then all minus
        let pitchPlus  = readInt16LE(data, 7)
        let yawPlus    = readInt16LE(data, 9)
        let rollPlus   = readInt16LE(data, 11)
        let pitchMinus = readInt16LE(data, 13)
        let yawMinus   = readInt16LE(data, 15)
        let rollMinus  = readInt16LE(data, 17)

        // Gyro speed: bytes 19-22
        let speedPlus  = readInt16LE(data, 19)
        let speedMinus = readInt16LE(data, 21)

        // Accel references: bytes 23-34
        let accelXPlus  = readInt16LE(data, 23)
        let accelXMinus = readInt16LE(data, 25)
        let accelYPlus  = readInt16LE(data, 27)
        let accelYMinus = readInt16LE(data, 29)
        let accelZPlus  = readInt16LE(data, 31)
        let accelZMinus = readInt16LE(data, 33)

        return DS4CalibrationData(
            gyroPitchBias: pitchBias, gyroYawBias: yawBias, gyroRollBias: rollBias,
            gyroPitchPlus: pitchPlus, gyroYawPlus: yawPlus, gyroRollPlus: rollPlus,
            gyroPitchMinus: pitchMinus, gyroYawMinus: yawMinus, gyroRollMinus: rollMinus,
            gyroSpeedPlus: speedPlus, gyroSpeedMinus: speedMinus,
            accelXPlus: accelXPlus, accelXMinus: accelXMinus,
            accelYPlus: accelYPlus, accelYMinus: accelYMinus,
            accelZPlus: accelZPlus, accelZMinus: accelZMinus
        )
    }

    // MARK: - Helpers

    private static func readInt16LE(_ buf: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(buf[offset]) | (UInt16(buf[offset + 1]) << 8))
    }
}
