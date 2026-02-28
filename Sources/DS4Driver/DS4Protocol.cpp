// DS4Protocol.cpp — USB report parsing and output report construction
// Port of DS4InputReportParser.swift and DS4OutputReportBuilder.swift for DriverKit (C++)
// Reference: docs/04-DS4-USB-Protocol.md Section 2.1 (input), Section 3 (output)

#include "DS4Protocol.h"

#include <string.h>  // memset

// MARK: - Little-Endian Helpers

static inline int16_t readInt16LE(const uint8_t *buf, uint32_t offset) {
    return (int16_t)((uint16_t)buf[offset] | ((uint16_t)buf[offset + 1] << 8));
}

static inline uint16_t readUInt16LE(const uint8_t *buf, uint32_t offset) {
    return (uint16_t)buf[offset] | ((uint16_t)buf[offset + 1] << 8);
}

// MARK: - Shared Parsing Logic

/// Parse controller state from a report buffer at the given data offset.
/// For USB: dataOffset = 1 (after report ID byte).
/// For BT:  dataOffset = 3 (after report ID + 2 BT flag bytes).
/// This mirrors DS4InputReportParser.parseControllerState() in Swift.
static void parseControllerState(const uint8_t *buf, uint32_t o,
                                  DS4InputState *state) {
    // Sticks: bytes [o+0..o+3]
    state->leftStick.x  = buf[o + 0];
    state->leftStick.y  = buf[o + 1];
    state->rightStick.x = buf[o + 2];
    state->rightStick.y = buf[o + 3];

    // Buttons byte [o+4]: D-pad (low nibble) + face buttons (high nibble)
    uint8_t dpadRaw = buf[o + 4] & 0x0F;
    state->dpad = (dpadRaw <= DS4DPadNorthWest)
                    ? (DS4DPadDirection)dpadRaw
                    : DS4DPadNeutral;

    state->buttons.square   = (buf[o + 4] & 0x10) != 0;
    state->buttons.cross    = (buf[o + 4] & 0x20) != 0;
    state->buttons.circle   = (buf[o + 4] & 0x40) != 0;
    state->buttons.triangle = (buf[o + 4] & 0x80) != 0;

    // Buttons byte [o+5]: shoulder + misc
    state->buttons.l1      = (buf[o + 5] & 0x01) != 0;
    state->buttons.r1      = (buf[o + 5] & 0x02) != 0;
    state->buttons.l2      = (buf[o + 5] & 0x04) != 0;
    state->buttons.r2      = (buf[o + 5] & 0x08) != 0;
    state->buttons.share   = (buf[o + 5] & 0x10) != 0;
    state->buttons.options = (buf[o + 5] & 0x20) != 0;
    state->buttons.l3      = (buf[o + 5] & 0x40) != 0;
    state->buttons.r3      = (buf[o + 5] & 0x80) != 0;

    // Byte [o+6]: PS (bit 0), touchpad click (bit 1), frame counter (bits 7:2)
    state->buttons.ps           = (buf[o + 6] & 0x01) != 0;
    state->buttons.touchpadClick = (buf[o + 6] & 0x02) != 0;
    state->frameCounter         = (buf[o + 6] & 0xFC) >> 2;

    // Triggers: [o+7..o+8]
    state->l2Trigger = buf[o + 7];
    state->r2Trigger = buf[o + 8];

    // Timestamp: [o+9..o+10] (uint16 LE)
    state->timestamp = readUInt16LE(buf, o + 9);

    // Byte [o+11]: temperature (skipped)

    // Gyroscope: [o+12..o+17] (3× int16 LE)
    state->imu.gyroPitch = readInt16LE(buf, o + 12);
    state->imu.gyroYaw   = readInt16LE(buf, o + 14);
    state->imu.gyroRoll  = readInt16LE(buf, o + 16);

    // Accelerometer: [o+18..o+23] (3× int16 LE)
    state->imu.accelX = readInt16LE(buf, o + 18);
    state->imu.accelY = readInt16LE(buf, o + 20);
    state->imu.accelZ = readInt16LE(buf, o + 22);

    // Bytes [o+24..o+28]: extension data (skipped)

    // Battery & peripherals: [o+29]
    uint8_t batteryByte = buf[o + 29];
    state->battery.level          = batteryByte & 0x0F;
    state->battery.cableConnected = (batteryByte & 0x10) != 0;
    state->battery.headphones     = (batteryByte & 0x20) != 0;
    state->battery.microphone     = (batteryByte & 0x40) != 0;

    // Bytes [o+30..o+31]: status/reserved (skipped)

    // Touchpad: [o+32] packet counter
    state->touchpad.packetCounter = buf[o + 32];

    // Touch finger 0: [o+33..o+36]
    // Byte 0: active (bit 7 inverted: 0=touching) | tracking ID (bits 6:0)
    // Bytes 1-3: 12-bit X and 12-bit Y split across 3 bytes
    state->touchpad.touch0.active     = (buf[o + 33] & 0x80) == 0;
    state->touchpad.touch0.trackingID = buf[o + 33] & 0x7F;
    state->touchpad.touch0.x = (uint16_t)buf[o + 34] |
                               ((uint16_t)(buf[o + 35] & 0x0F) << 8);
    state->touchpad.touch0.y = ((uint16_t)(buf[o + 35] >> 4)) |
                               ((uint16_t)buf[o + 36] << 4);

    // Touch finger 1: [o+37..o+40]
    state->touchpad.touch1.active     = (buf[o + 37] & 0x80) == 0;
    state->touchpad.touch1.trackingID = buf[o + 37] & 0x7F;
    state->touchpad.touch1.x = (uint16_t)buf[o + 38] |
                               ((uint16_t)(buf[o + 39] & 0x0F) << 8);
    state->touchpad.touch1.y = ((uint16_t)(buf[o + 39] >> 4)) |
                               ((uint16_t)buf[o + 40] << 4);
}

// MARK: - Public API

bool ds4_parse_usb_input_report(const uint8_t *data, uint32_t length,
                                 DS4InputState *outState) {
    if (!data || !outState) {
        return false;
    }
    if (length < DS4_USB_INPUT_REPORT_SIZE) {
        return false;
    }
    if (data[0] != DS4_REPORT_ID_USB_INPUT) {
        return false;
    }

    ds4_input_state_init(outState);
    parseControllerState(data, 1, outState);
    return true;
}

void ds4_build_usb_output_report(const DS4OutputState *state,
                                  uint8_t *outReport) {
    memset(outReport, 0, DS4_USB_OUTPUT_REPORT_SIZE);

    outReport[0]  = DS4_REPORT_ID_USB_OUTPUT;   // 0x05
    outReport[1]  = DS4_FLAG_STANDARD;           // 0x07
    outReport[2]  = 0x04;                        // secondary flags
    // Note: motor byte ordering — right/weak comes before left/strong
    outReport[4]  = state->rumbleLight;           // right/weak motor
    outReport[5]  = state->rumbleHeavy;           // left/strong motor
    outReport[6]  = state->ledRed;
    outReport[7]  = state->ledGreen;
    outReport[8]  = state->ledBlue;
    outReport[9]  = state->flashOn;
    outReport[10] = state->flashOff;
}

void ds4_input_state_init(DS4InputState *state) {
    memset(state, 0, sizeof(DS4InputState));
    state->leftStick.x  = 128;
    state->leftStick.y  = 128;
    state->rightStick.x = 128;
    state->rightStick.y = 128;
    state->dpad = DS4DPadNeutral;
}

void ds4_output_state_init(DS4OutputState *state) {
    memset(state, 0, sizeof(DS4OutputState));
}
