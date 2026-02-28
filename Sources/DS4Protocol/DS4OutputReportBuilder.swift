// DS4OutputReportBuilder.swift — Build USB and Bluetooth output reports
// Reference: docs/04-DS4-USB-Protocol.md Section 3, docs/05-DS4-Bluetooth-Protocol.md Section 6

/// Constructs HID output reports for controlling rumble motors, light bar, and flash.
public enum DS4OutputReportBuilder {

    /// Build a 32-byte USB output report (Report ID 0x05).
    ///
    /// Byte map (from docs/04-DS4-USB-Protocol.md Section 3.1):
    /// - Byte 0: Report ID (0x05)
    /// - Byte 1: Feature flags (0x07 = rumble + lightbar + flash)
    /// - Byte 2: Secondary flags (0x04 typical)
    /// - Byte 3: Reserved
    /// - Byte 4: Right/weak motor (0-255)
    /// - Byte 5: Left/strong motor (0-255)
    /// - Bytes 6-8: LED Red, Green, Blue (0-255 each)
    /// - Bytes 9-10: Flash On/Off duration (~10ms units)
    public static func buildUSB(_ state: DS4OutputState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: DS4ReportSize.usbOutput)
        report[0]  = DS4ReportID.usbOutput
        report[1]  = DS4FeatureFlag.standard.rawValue   // 0x07
        report[2]  = 0x04
        // Note: motor ordering is right(weak) then left(strong)
        report[4]  = state.rumbleLight                   // right/weak motor
        report[5]  = state.rumbleHeavy                   // left/strong motor
        report[6]  = state.ledRed
        report[7]  = state.ledGreen
        report[8]  = state.ledBlue
        report[9]  = state.flashOn
        report[10] = state.flashOff
        return report
    }

    /// Build a 78-byte Bluetooth output report (Report ID 0x11) with CRC-32.
    ///
    /// Byte map (from docs/05-DS4-Bluetooth-Protocol.md Section 6.2):
    /// Same fields as USB but shifted +2 for BT header bytes.
    /// - Byte 0: Report ID (0x11)
    /// - Byte 1: BT flags (0xC0 = EnableHID + EnableCRC)
    /// - Byte 2: Audio flags (0x00 for standard)
    /// - Byte 3: Feature flags (0x07)
    /// - Byte 4: Secondary flags (0x04)
    /// - Byte 5: Reserved
    /// - Byte 6: Right/weak motor
    /// - Byte 7: Left/strong motor
    /// - Bytes 8-10: LED RGB
    /// - Bytes 11-12: Flash On/Off
    /// - Bytes 74-77: CRC-32 (little-endian)
    public static func buildBluetooth(_ state: DS4OutputState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: DS4ReportSize.btOutput)
        report[0]  = DS4ReportID.btOutput
        report[1]  = 0xC0                               // EnableHID + EnableCRC
        report[2]  = 0x00                               // no audio
        report[3]  = DS4FeatureFlag.standard.rawValue   // 0x07
        report[4]  = 0x04
        report[6]  = state.rumbleLight                   // right/weak (+2 offset)
        report[7]  = state.rumbleHeavy                   // left/strong (+2 offset)
        report[8]  = state.ledRed
        report[9]  = state.ledGreen
        report[10] = state.ledBlue
        report[11] = state.flashOn
        report[12] = state.flashOff
        DS4CRC32.appendOutputCRC(&report)
        return report
    }
}
