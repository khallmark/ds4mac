// DS4CRC32.swift — CRC-32 calculation for Bluetooth DS4 reports
// Reference: docs/05-DS4-Bluetooth-Protocol.md Section 8
// Polynomial: 0x04C11DB7 (reflected: 0xEDB88320)

/// CRC-32 computation and validation for DS4 Bluetooth HID reports.
public enum DS4CRC32 {

    /// CRC-32 lookup table (reflected polynomial 0xEDB88320).
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
            }
            return crc
        }
    }()

    /// Compute CRC-32 of a byte sequence.
    public static func compute(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// Validate CRC-32 of a Bluetooth input report (78 bytes).
    /// Prepends seed byte 0xA1, computes CRC over bytes [0..73], compares to LE uint32 at [74..77].
    public static func validateInputReport(_ report: [UInt8]) -> Bool {
        guard report.count >= DS4ReportSize.btInput else { return false }
        let crcInput = [DS4CRCPrefix.input] + Array(report[0..<74])
        let computed = compute(crcInput)
        let stored = readUInt32LE(report, 74)
        return computed == stored
    }

    /// Compute and write CRC-32 into the last 4 bytes of a Bluetooth output report.
    /// Prepends seed byte 0xA2, computes CRC over bytes [0..73], writes LE uint32 at [74..77].
    public static func appendOutputCRC(_ report: inout [UInt8]) {
        guard report.count >= DS4ReportSize.btOutput else { return }
        let crcInput = [DS4CRCPrefix.output] + Array(report[0..<74])
        let crc = compute(crcInput)
        report[74] = UInt8(crc & 0xFF)
        report[75] = UInt8((crc >> 8) & 0xFF)
        report[76] = UInt8((crc >> 16) & 0xFF)
        report[77] = UInt8((crc >> 24) & 0xFF)
    }

    /// Validate CRC-32 of a Bluetooth output report (78 bytes, seed 0xA2).
    public static func validateOutputReport(_ report: [UInt8]) -> Bool {
        guard report.count >= DS4ReportSize.btOutput else { return false }
        let crcInput = [DS4CRCPrefix.output] + Array(report[0..<74])
        let computed = compute(crcInput)
        let stored = readUInt32LE(report, 74)
        return computed == stored
    }

    private static func readUInt32LE(_ buf: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buf[offset]) |
        (UInt32(buf[offset + 1]) << 8) |
        (UInt32(buf[offset + 2]) << 16) |
        (UInt32(buf[offset + 3]) << 24)
    }
}
