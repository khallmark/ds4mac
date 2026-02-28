// DS4InputReportParser.swift — Parse USB and Bluetooth input reports into DS4InputState
// Reference: docs/04-DS4-USB-Protocol.md Section 2.1, docs/05-DS4-Bluetooth-Protocol.md Section 5

/// Parses raw HID input report bytes into structured DS4InputState.
public enum DS4InputReportParser {

    public enum ParseError: Error, Equatable, Sendable {
        case invalidLength(expected: Int, got: Int)
        case invalidReportID(expected: UInt8, got: UInt8)
        case crcMismatch
    }

    // MARK: - Public API

    /// Parse a 64-byte USB input report (Report ID 0x01).
    public static func parseUSB(_ data: [UInt8]) throws -> DS4InputState {
        guard data.count >= DS4ReportSize.usbInput else {
            throw ParseError.invalidLength(expected: DS4ReportSize.usbInput, got: data.count)
        }
        guard data[0] == DS4ReportID.usbInput else {
            throw ParseError.invalidReportID(expected: DS4ReportID.usbInput, got: data[0])
        }
        return parseControllerState(data, dataOffset: 1)
    }

    /// Parse a 78-byte Bluetooth extended input report (Report ID 0x11).
    /// The controller data starts at byte 3 (bytes 1-2 are BT-specific flags).
    public static func parseBluetooth(_ data: [UInt8], validateCRC: Bool = true) throws -> DS4InputState {
        guard data.count >= DS4ReportSize.btInput else {
            throw ParseError.invalidLength(expected: DS4ReportSize.btInput, got: data.count)
        }
        guard data[0] == DS4ReportID.btInput else {
            throw ParseError.invalidReportID(expected: DS4ReportID.btInput, got: data[0])
        }
        if validateCRC && !DS4CRC32.validateInputReport(data) {
            throw ParseError.crcMismatch
        }
        // BT controller data starts at byte 3, mapping to USB byte 1
        return parseControllerState(data, dataOffset: 3)
    }

    /// Auto-detect report type (USB vs BT) and parse.
    public static func parse(_ data: [UInt8]) throws -> DS4InputState {
        guard !data.isEmpty else {
            throw ParseError.invalidLength(expected: DS4ReportSize.usbInput, got: 0)
        }
        if data[0] == DS4ReportID.btInput && data.count >= DS4ReportSize.btInput {
            return try parseBluetooth(data)
        } else if data[0] == DS4ReportID.usbInput && data.count >= DS4ReportSize.usbInput {
            return try parseUSB(data)
        } else {
            throw ParseError.invalidReportID(expected: DS4ReportID.usbInput, got: data[0])
        }
    }

    // MARK: - Internal Parsing

    /// Shared parsing logic for both USB and BT reports.
    /// `dataOffset` is 1 for USB (after report ID) or 3 for BT (after report ID + 2 BT flag bytes).
    internal static func parseControllerState(_ buf: [UInt8], dataOffset o: Int) -> DS4InputState {
        // Sticks: bytes [o+0..o+3] → USB bytes 1-4
        let leftStick = DS4StickState(x: buf[o + 0], y: buf[o + 1])
        let rightStick = DS4StickState(x: buf[o + 2], y: buf[o + 3])

        // Buttons byte [o+4] → USB byte 5: D-pad (low nibble) + face buttons (high nibble)
        let dpadRaw = buf[o + 4] & 0x0F
        let dpad = DS4DPadDirection(rawValue: dpadRaw) ?? .neutral

        let square   = (buf[o + 4] & 0x10) != 0
        let cross    = (buf[o + 4] & 0x20) != 0
        let circle   = (buf[o + 4] & 0x40) != 0
        let triangle = (buf[o + 4] & 0x80) != 0

        // Buttons byte [o+5] → USB byte 6
        let l1      = (buf[o + 5] & 0x01) != 0
        let r1      = (buf[o + 5] & 0x02) != 0
        let l2Btn   = (buf[o + 5] & 0x04) != 0
        let r2Btn   = (buf[o + 5] & 0x08) != 0
        let share   = (buf[o + 5] & 0x10) != 0
        let options = (buf[o + 5] & 0x20) != 0
        let l3      = (buf[o + 5] & 0x40) != 0
        let r3      = (buf[o + 5] & 0x80) != 0

        // Byte [o+6] → USB byte 7: PS (bit 0), touchpad click (bit 1), frame counter (bits 7:2)
        let ps            = (buf[o + 6] & 0x01) != 0
        let touchpadClick = (buf[o + 6] & 0x02) != 0
        let frameCounter  = (buf[o + 6] & 0xFC) >> 2

        // Triggers: [o+7..o+8] → USB bytes 8-9
        let l2Trigger = buf[o + 7]
        let r2Trigger = buf[o + 8]

        // Timestamp: [o+9..o+10] → USB bytes 10-11 (uint16 LE)
        let timestamp = readUInt16LE(buf, o + 9)

        // Temperature byte at [o+11] → USB byte 12 (skipped, uncalibrated)

        // Gyroscope: [o+12..o+17] → USB bytes 13-18 (3× int16 LE)
        let gyroPitch = readInt16LE(buf, o + 12)
        let gyroYaw   = readInt16LE(buf, o + 14)
        let gyroRoll  = readInt16LE(buf, o + 16)

        // Accelerometer: [o+18..o+23] → USB bytes 19-24 (3× int16 LE)
        let accelX = readInt16LE(buf, o + 18)
        let accelY = readInt16LE(buf, o + 20)
        let accelZ = readInt16LE(buf, o + 22)

        // Extension data at [o+24..o+28] → USB bytes 25-29 (skipped)

        // Battery & peripherals: [o+29] → USB byte 30
        let batteryByte = buf[o + 29]
        let batteryLevel   = batteryByte & 0x0F
        let cableConnected = (batteryByte & 0x10) != 0
        let headphones     = (batteryByte & 0x20) != 0
        let microphone     = (batteryByte & 0x40) != 0

        // Bytes [o+30..o+31] → USB bytes 31-32 (status/reserved, skipped)

        // Touchpad: [o+32] → USB byte 33 (touch packet counter)
        let touchPktCounter = buf[o + 32]

        // Touch finger 0: [o+33..o+36] → USB bytes 34-37
        let touch0 = parseTouchFinger(buf, offset: o + 33)

        // Touch finger 1: [o+37..o+40] → USB bytes 38-41
        let touch1 = parseTouchFinger(buf, offset: o + 37)

        return DS4InputState(
            leftStick: leftStick,
            rightStick: rightStick,
            dpad: dpad,
            buttons: DS4Buttons(
                square: square, cross: cross, circle: circle, triangle: triangle,
                l1: l1, r1: r1, l2: l2Btn, r2: r2Btn,
                share: share, options: options, l3: l3, r3: r3,
                ps: ps, touchpadClick: touchpadClick
            ),
            l2Trigger: l2Trigger,
            r2Trigger: r2Trigger,
            touchpad: DS4TouchpadState(
                touch0: touch0, touch1: touch1, packetCounter: touchPktCounter
            ),
            imu: DS4IMUState(
                gyroPitch: gyroPitch, gyroYaw: gyroYaw, gyroRoll: gyroRoll,
                accelX: accelX, accelY: accelY, accelZ: accelZ
            ),
            battery: DS4BatteryState(
                level: batteryLevel, cableConnected: cableConnected,
                headphones: headphones, microphone: microphone
            ),
            timestamp: timestamp,
            frameCounter: frameCounter
        )
    }

    // MARK: - Helpers

    /// Parse a 4-byte touchpad finger entry.
    /// Byte 0: active (bit 7 inverted: 0=touching) | tracking ID (bits 6:0)
    /// Bytes 1-3: 12-bit X and 12-bit Y coordinates split across 3 bytes.
    private static func parseTouchFinger(_ buf: [UInt8], offset o: Int) -> DS4TouchFinger {
        let active     = (buf[o] & 0x80) == 0   // bit 7 inverted
        let trackingID = buf[o] & 0x7F
        let x = UInt16(buf[o + 1]) | (UInt16(buf[o + 2] & 0x0F) << 8)
        let y = UInt16(buf[o + 2] >> 4) | (UInt16(buf[o + 3]) << 4)
        return DS4TouchFinger(active: active, trackingID: trackingID, x: x, y: y)
    }

    private static func readInt16LE(_ buf: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(buf[offset]) | (UInt16(buf[offset + 1]) << 8))
    }

    private static func readUInt16LE(_ buf: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(buf[offset]) | (UInt16(buf[offset + 1]) << 8)
    }
}
