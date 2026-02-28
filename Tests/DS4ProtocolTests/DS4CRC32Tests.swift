import XCTest
@testable import DS4Protocol

final class DS4CRC32Tests: XCTestCase {

    // MARK: - Standard Test Vectors

    func testCRC32KnownVector() {
        // Standard CRC-32 test: "123456789" = 0xCBF43926
        let data = Array("123456789".utf8)
        XCTAssertEqual(DS4CRC32.compute(data), 0xCBF4_3926)
    }

    func testCRC32EmptyData() {
        // CRC-32 of empty data = 0x00000000
        XCTAssertEqual(DS4CRC32.compute([]), 0x0000_0000)
    }

    func testCRC32SingleByte() {
        // CRC-32 of [0x00] = 0xD202EF8D
        XCTAssertEqual(DS4CRC32.compute([0x00]), 0xD202_EF8D)
    }

    func testCRC32SeedByteA1() {
        // CRC-32 of just the input seed byte [0xA1]
        let crc = DS4CRC32.compute([0xA1])
        // This should be a deterministic value
        XCTAssertNotEqual(crc, 0)
    }

    // MARK: - Input Report Validation

    func testValidateInputReportValid() {
        let report = makeBTReport()
        XCTAssertTrue(DS4CRC32.validateInputReport(report))
    }

    func testValidateInputReportCorrupted() {
        var report = makeBTReport()
        report[10] ^= 0xFF  // flip some data bits
        XCTAssertFalse(DS4CRC32.validateInputReport(report))
    }

    func testValidateInputReportBadCRC() {
        var report = makeBTReport()
        report[74] ^= 0x01  // flip a CRC bit
        XCTAssertFalse(DS4CRC32.validateInputReport(report))
    }

    func testValidateInputReportTooShort() {
        let report = [UInt8](repeating: 0, count: 64)
        XCTAssertFalse(DS4CRC32.validateInputReport(report))
    }

    // MARK: - Output Report CRC

    func testAppendOutputCRC() {
        var report = [UInt8](repeating: 0, count: 78)
        report[0] = 0x11  // Report ID
        report[1] = 0xC0  // BT flags
        DS4CRC32.appendOutputCRC(&report)

        // Last 4 bytes should be non-zero CRC
        let crc = UInt32(report[74]) |
                  (UInt32(report[75]) << 8) |
                  (UInt32(report[76]) << 16) |
                  (UInt32(report[77]) << 24)
        XCTAssertNotEqual(crc, 0)

        // Validate the CRC we just wrote
        XCTAssertTrue(DS4CRC32.validateOutputReport(report))
    }

    func testAppendOutputCRCThenValidate() {
        var report = [UInt8](repeating: 0, count: 78)
        report[0] = 0x11
        report[1] = 0xC0
        report[3] = 0x07  // feature flags
        report[6] = 128   // rumble
        report[8] = 255   // LED red
        DS4CRC32.appendOutputCRC(&report)
        XCTAssertTrue(DS4CRC32.validateOutputReport(report))
    }

    func testOutputCRCChangeWithData() {
        var report1 = [UInt8](repeating: 0, count: 78)
        report1[0] = 0x11
        DS4CRC32.appendOutputCRC(&report1)

        var report2 = [UInt8](repeating: 0, count: 78)
        report2[0] = 0x11
        report2[8] = 0xFF  // different LED data
        DS4CRC32.appendOutputCRC(&report2)

        // CRCs should differ because data differs
        XCTAssertNotEqual(
            Array(report1[74...77]),
            Array(report2[74...77])
        )
    }

    // MARK: - Round-Trip

    func testCRCRoundTrip() {
        // Build a BT output report, append CRC, then validate
        let state = DS4OutputState(rumbleHeavy: 128, rumbleLight: 64,
                                   ledRed: 255, ledGreen: 0, ledBlue: 128)
        let report = DS4OutputReportBuilder.buildBluetooth(state)
        XCTAssertTrue(DS4CRC32.validateOutputReport(report))
    }
}
