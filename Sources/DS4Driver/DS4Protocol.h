// DS4Protocol.h — C++ types and parsing for the DualShock 4 protocol
// Port of DS4Types.swift and DS4Constants.swift for use in DriverKit (C++ only)
// Reference: docs/04-DS4-USB-Protocol.md, docs/05-DS4-Bluetooth-Protocol.md

#ifndef DS4Protocol_h
#define DS4Protocol_h

#include <stdint.h>
#include <stdbool.h>

// MARK: - Device Identifiers

#define DS4_VENDOR_ID           0x054C  // Sony Corporation
#define DS4_V1_PRODUCT_ID      0x05C4  // DualShock 4 V1 (CUH-ZCT1x)
#define DS4_V2_PRODUCT_ID      0x09CC  // DualShock 4 V2 (CUH-ZCT2x)
#define DS4_DONGLE_PRODUCT_ID  0x0BA0  // Sony Wireless Adapter

// MARK: - Report IDs

#define DS4_REPORT_ID_USB_INPUT     0x01  // USB input report (64 bytes)
#define DS4_REPORT_ID_BT_INPUT      0x11  // Bluetooth extended input (78 bytes)
#define DS4_REPORT_ID_USB_OUTPUT    0x05  // USB output report (32 bytes)
#define DS4_REPORT_ID_BT_OUTPUT     0x11  // Bluetooth output report (78 bytes)
#define DS4_REPORT_ID_CALIBRATION   0x02  // IMU calibration (USB feature)

// MARK: - Report Sizes

#define DS4_USB_INPUT_REPORT_SIZE   64
#define DS4_BT_INPUT_REPORT_SIZE    78
#define DS4_USB_OUTPUT_REPORT_SIZE  32
#define DS4_BT_OUTPUT_REPORT_SIZE   78

// MARK: - Feature Flags (output report byte 1)

#define DS4_FLAG_RUMBLE     0x01
#define DS4_FLAG_LIGHTBAR   0x02
#define DS4_FLAG_FLASH      0x04
#define DS4_FLAG_STANDARD   (DS4_FLAG_RUMBLE | DS4_FLAG_LIGHTBAR | DS4_FLAG_FLASH)  // 0x07

// MARK: - D-Pad Direction

enum DS4DPadDirection : uint8_t {
    DS4DPadNorth     = 0,
    DS4DPadNorthEast = 1,
    DS4DPadEast      = 2,
    DS4DPadSouthEast = 3,
    DS4DPadSouth     = 4,
    DS4DPadSouthWest = 5,
    DS4DPadWest      = 6,
    DS4DPadNorthWest = 7,
    DS4DPadNeutral   = 8,
};

// MARK: - Analog Stick State

struct DS4StickState {
    uint8_t x;  // 0=left, 128=center, 255=right
    uint8_t y;  // 0=up, 128=center, 255=down
};

// MARK: - Button State (14 digital buttons)

struct DS4Buttons {
    bool square;
    bool cross;
    bool circle;
    bool triangle;
    bool l1;
    bool r1;
    bool l2;           // digital trigger button
    bool r2;           // digital trigger button
    bool share;
    bool options;
    bool l3;           // left stick click
    bool r3;           // right stick click
    bool ps;           // PlayStation button
    bool touchpadClick;
};

// MARK: - Touch Finger

// Active bit is inverted in raw report: bit 7 = 0 means touching.
// Coordinates: X 0-1919 (12-bit), Y 0-942 (12-bit).
struct DS4TouchFinger {
    bool    active;
    uint8_t trackingID;  // 7-bit ID (0-127)
    uint16_t x;          // 0-1919
    uint16_t y;          // 0-942
};

// MARK: - Touchpad State

struct DS4TouchpadState {
    DS4TouchFinger touch0;
    DS4TouchFinger touch1;
    uint8_t packetCounter;
};

// MARK: - IMU State (raw signed 16-bit, uncalibrated)

struct DS4IMUState {
    int16_t gyroPitch;  // X-axis rotation
    int16_t gyroYaw;    // Y-axis rotation
    int16_t gyroRoll;   // Z-axis rotation
    int16_t accelX;
    int16_t accelY;
    int16_t accelZ;
};

// MARK: - Battery State

struct DS4BatteryState {
    uint8_t level;          // 0-8 (wireless), 0-11 (wired/charging)
    bool cableConnected;
    bool headphones;
    bool microphone;
};

// MARK: - Complete Input State

struct DS4InputState {
    DS4StickState    leftStick;
    DS4StickState    rightStick;
    DS4DPadDirection dpad;
    DS4Buttons       buttons;
    uint8_t          l2Trigger;     // analog trigger 0-255
    uint8_t          r2Trigger;     // analog trigger 0-255
    DS4TouchpadState touchpad;
    DS4IMUState      imu;
    DS4BatteryState  battery;
    uint16_t         timestamp;
    uint8_t          frameCounter;
};

// MARK: - Output State

struct DS4OutputState {
    uint8_t rumbleHeavy;    // left/strong motor (0-255)
    uint8_t rumbleLight;    // right/weak motor (0-255)
    uint8_t ledRed;
    uint8_t ledGreen;
    uint8_t ledBlue;
    uint8_t flashOn;        // ~10ms units
    uint8_t flashOff;       // ~10ms units
};

// MARK: - Parsing and Building Functions

#ifdef __cplusplus
extern "C" {
#endif

/// Parse a 64-byte USB input report into DS4InputState.
/// Returns true on success, false if data is invalid.
/// The report buffer must contain at least DS4_USB_INPUT_REPORT_SIZE bytes.
bool ds4_parse_usb_input_report(const uint8_t *data, uint32_t length,
                                 DS4InputState *outState);

/// Build a 32-byte USB output report from DS4OutputState.
/// The output buffer must be at least DS4_USB_OUTPUT_REPORT_SIZE bytes.
void ds4_build_usb_output_report(const DS4OutputState *state,
                                  uint8_t *outReport);

/// Initialize a DS4InputState with default values (sticks centered, nothing pressed).
void ds4_input_state_init(DS4InputState *state);

/// Initialize a DS4OutputState with all zeros.
void ds4_output_state_init(DS4OutputState *state);

#ifdef __cplusplus
}
#endif

#endif /* DS4Protocol_h */
