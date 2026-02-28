// DS4Constants.swift — DualShock 4 protocol constants
// Reference: docs/04-DS4-USB-Protocol.md, docs/05-DS4-Bluetooth-Protocol.md

/// Sony / DualShock 4 USB and Bluetooth device identifiers.
public enum DS4DeviceID {
    public static let vendorID: UInt16 = 0x054C       // Sony Corporation
    public static let ds4V1PID: UInt16 = 0x05C4       // DualShock 4 V1 (CUH-ZCT1x)
    public static let ds4V2PID: UInt16 = 0x09CC       // DualShock 4 V2 (CUH-ZCT2x)
    public static let donglePID: UInt16 = 0x0BA0      // Sony Wireless Adapter
}

/// HID report IDs used by the DS4.
public enum DS4ReportID {
    public static let usbInput: UInt8 = 0x01          // USB input report (64 bytes)
    public static let btInput: UInt8 = 0x11           // Bluetooth extended input (78 bytes)
    public static let btInputReduced: UInt8 = 0x01    // Bluetooth reduced input (10 bytes)
    public static let usbOutput: UInt8 = 0x05         // USB output report (32 bytes)
    public static let btOutput: UInt8 = 0x11          // Bluetooth output report (78 bytes)
    public static let calibrationUSB: UInt8 = 0x02    // IMU calibration (USB, feature)
    public static let calibrationBT: UInt8 = 0x05     // IMU calibration (BT, feature)
    public static let pairingInfo: UInt8 = 0x12       // Pairing info (feature)
    public static let firmwareInfo: UInt8 = 0xA3      // Firmware version (feature)
    public static let macAddress: UInt8 = 0x81        // MAC address (feature)
}

/// HID report sizes in bytes (including report ID byte).
public enum DS4ReportSize {
    public static let usbInput = 64
    public static let btInput = 78
    public static let btInputReduced = 10
    public static let usbOutput = 32
    public static let btOutput = 78
    public static let calibration = 37
}

/// Feature enable flags for output reports (byte 1 of USB, byte 3 of BT).
public struct DS4FeatureFlag: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let rumble   = DS4FeatureFlag(rawValue: 0x01)
    public static let lightbar = DS4FeatureFlag(rawValue: 0x02)
    public static let flash    = DS4FeatureFlag(rawValue: 0x04)

    /// Standard combination: rumble + lightbar + flash
    public static let standard: DS4FeatureFlag = [.rumble, .lightbar, .flash]
}

/// CRC-32 seed bytes prepended before checksum computation (BT only).
public enum DS4CRCPrefix {
    public static let input: UInt8 = 0xA1       // DATA + INPUT
    public static let output: UInt8 = 0xA2      // DATA + OUTPUT
    public static let getFeature: UInt8 = 0xA3  // GET_REPORT + FEATURE
    public static let setFeature: UInt8 = 0x53  // SET_REPORT + FEATURE
}
