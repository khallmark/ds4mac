// TestHelpers.swift — Utilities for constructing test HID reports

import Foundation
@testable import DS4Protocol

/// Build a minimal valid 64-byte USB input report with configurable fields.
/// Unspecified fields default to neutral/zero state.
func makeUSBReport(
    leftStickX: UInt8 = 0x80, leftStickY: UInt8 = 0x80,
    rightStickX: UInt8 = 0x80, rightStickY: UInt8 = 0x80,
    buttons0: UInt8 = 0x08,   // d-pad neutral (8) + no face buttons
    buttons1: UInt8 = 0x00,   // no shoulder/misc buttons
    buttons2: UInt8 = 0x00,   // no PS/touchpad, counter = 0
    l2: UInt8 = 0, r2: UInt8 = 0,
    timestampLo: UInt8 = 0, timestampHi: UInt8 = 0,
    gyroPitchLo: UInt8 = 0, gyroPitchHi: UInt8 = 0,
    gyroYawLo: UInt8 = 0, gyroYawHi: UInt8 = 0,
    gyroRollLo: UInt8 = 0, gyroRollHi: UInt8 = 0,
    accelXLo: UInt8 = 0, accelXHi: UInt8 = 0,
    accelYLo: UInt8 = 0, accelYHi: UInt8 = 0,
    accelZLo: UInt8 = 0, accelZHi: UInt8 = 0,
    batteryByte: UInt8 = 0x00,
    touchPacketCount: UInt8 = 0,
    touchPacketCounter: UInt8 = 0,
    touch0: [UInt8] = [0x80, 0, 0, 0],  // inactive (bit 7 set)
    touch1: [UInt8] = [0x80, 0, 0, 0]   // inactive
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 64)
    report[0]  = 0x01  // Report ID
    report[1]  = leftStickX
    report[2]  = leftStickY
    report[3]  = rightStickX
    report[4]  = rightStickY
    report[5]  = buttons0
    report[6]  = buttons1
    report[7]  = buttons2
    report[8]  = l2
    report[9]  = r2
    report[10] = timestampLo
    report[11] = timestampHi
    // byte 12 = temperature (skip)
    report[13] = gyroPitchLo
    report[14] = gyroPitchHi
    report[15] = gyroYawLo
    report[16] = gyroYawHi
    report[17] = gyroRollLo
    report[18] = gyroRollHi
    report[19] = accelXLo
    report[20] = accelXHi
    report[21] = accelYLo
    report[22] = accelYHi
    report[23] = accelZLo
    report[24] = accelZHi
    // bytes 25-29 = extension data (skip)
    report[30] = batteryByte
    // bytes 31-32 = reserved
    report[33] = touchPacketCount       // USB byte 33: touch packet count
    report[34] = touchPacketCounter     // USB byte 34: touch packet counter/timestamp
    report[35] = touch0[0]; report[36] = touch0[1]  // USB bytes 35-38: finger 0
    report[37] = touch0[2]; report[38] = touch0[3]
    report[39] = touch1[0]; report[40] = touch1[1]  // USB bytes 39-42: finger 1
    report[41] = touch1[2]; report[42] = touch1[3]
    return report
}

/// Build a 78-byte Bluetooth input report with valid CRC-32.
/// Wraps a USB-style payload with BT headers and appends CRC.
func makeBTReport(
    btFlags1: UInt8 = 0xC0,
    btFlags2: UInt8 = 0x00,
    leftStickX: UInt8 = 0x80, leftStickY: UInt8 = 0x80,
    rightStickX: UInt8 = 0x80, rightStickY: UInt8 = 0x80,
    buttons0: UInt8 = 0x08,
    buttons1: UInt8 = 0x00,
    buttons2: UInt8 = 0x00,
    l2: UInt8 = 0, r2: UInt8 = 0,
    batteryByte: UInt8 = 0x00,
    touch0: [UInt8] = [0x80, 0, 0, 0],
    touch1: [UInt8] = [0x80, 0, 0, 0]
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 78)
    report[0] = 0x11  // Report ID
    report[1] = btFlags1
    report[2] = btFlags2
    // Controller data at offset 3 (maps to USB offset 1)
    report[3]  = leftStickX
    report[4]  = leftStickY
    report[5]  = rightStickX
    report[6]  = rightStickY
    report[7]  = buttons0
    report[8]  = buttons1
    report[9]  = buttons2
    report[10] = l2
    report[11] = r2
    // bytes 12-13 = timestamp
    // byte 14 = temperature
    // bytes 15-26 = IMU
    report[32] = batteryByte    // battery at BT offset 32 = USB offset 30 + 2
    report[35] = 0              // BT byte 35 = USB byte 33: touch packet count
    report[36] = 0              // BT byte 36 = USB byte 34: touch packet counter/timestamp
    report[37] = touch0[0]; report[38] = touch0[1]  // BT bytes 37-40: finger 0
    report[39] = touch0[2]; report[40] = touch0[3]
    report[41] = touch1[0]; report[42] = touch1[1]  // BT bytes 41-44: finger 1
    report[43] = touch1[2]; report[44] = touch1[3]
    // Compute and append valid CRC-32
    let crcInput = [DS4CRCPrefix.input] + Array(report[0..<74])
    let crc = DS4CRC32.compute(crcInput)
    report[74] = UInt8(crc & 0xFF)
    report[75] = UInt8((crc >> 8) & 0xFF)
    report[76] = UInt8((crc >> 16) & 0xFF)
    report[77] = UInt8((crc >> 24) & 0xFF)
    return report
}

/// Encode a signed Int16 as two little-endian bytes.
func int16LEBytes(_ value: Int16) -> (lo: UInt8, hi: UInt8) {
    let bits = UInt16(bitPattern: value)
    return (UInt8(bits & 0xFF), UInt8(bits >> 8))
}

/// Encode a 12-bit touchpad coordinate pair into 4 touch finger bytes.
/// active: true = touching (bit 7 clear), false = not touching (bit 7 set).
func makeTouchFingerBytes(active: Bool, trackingID: UInt8, x: UInt16, y: UInt16) -> [UInt8] {
    let byte0 = (active ? 0x00 : 0x80) | (trackingID & 0x7F)
    let byte1 = UInt8(x & 0xFF)
    let byte2 = UInt8((x >> 8) & 0x0F) | UInt8((y & 0x0F) << 4)
    let byte3 = UInt8(y >> 4)
    return [byte0, byte1, byte2, byte3]
}
