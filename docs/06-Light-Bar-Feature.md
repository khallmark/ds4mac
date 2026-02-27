# DS4 Light Bar Feature Reference

## Related Documents

- **04-USB-Protocol.md** -- USB output report 0x05 structure (shared with this feature)
- **05-Bluetooth-Protocol.md** -- BT output report 0x11 structure and CRC-32 details
- **09-Audio-Streaming-Feature.md** -- Shares the same output reports (0x05 / 0x11) for volume fields

---

## Table of Contents

1. [Hardware Description](#1-hardware-description)
2. [Output Report Fields](#2-output-report-fields)
3. [Flash Patterns](#3-flash-patterns)
4. [Standard Colors](#4-standard-colors)
5. [Implementation Guide for macOS](#5-implementation-guide-for-macos)
6. [Color Presets Table](#6-color-presets-table)
7. [Battery Level Indication](#7-battery-level-indication)
8. [Use Cases](#8-use-cases)
9. [Code Examples](#9-code-examples)

---

## 1. Hardware Description

### Physical Characteristics

The DualShock 4 features an RGB LED light bar located on the **front face of the controller**, directly above the touchpad. The light bar is visible both to the player and to the PlayStation Camera for tracking purposes.

| Property | Detail |
|---|---|
| **LED Type** | RGB LED (24-bit color) |
| **Color Depth** | 8 bits per channel (256 levels per R/G/B) |
| **Total Colors** | 16,777,216 (256 x 256 x 256) |
| **Brightness Control** | Via RGB intensity values (0-255 per channel) |
| **Flash Support** | Hardware-driven on/off flash with configurable timing |

### Version Differences

| Feature | CUH-ZCT1 (v1, Original) | CUH-ZCT2 (v2, Slim/Pro era) |
|---|---|---|
| **Light bar visibility** | Front-facing only | Front-facing **and** a thin sliver visible through the top of the touchpad |
| **LED hardware** | Same RGB LED type | Same RGB LED type |
| **Protocol** | Identical output report format | Identical output report format |
| **Brightness** | Same range (0-255) | Same range (0-255) |

The v2 controller added a small light pipe that routes a portion of the light bar through the touchpad surface, making it visible to the player from above during normal gameplay. The protocol for controlling it is identical across both versions.

### How Brightness Works

The light bar has no separate brightness register. Brightness is controlled by the magnitude of the RGB values themselves. To dim a color while preserving its hue, scale all three channels proportionally:

```
Full brightness red:   R=255, G=0,   B=0
50% brightness red:    R=128, G=0,   B=0
25% brightness red:    R=64,  G=0,   B=0
Off:                   R=0,   G=0,   B=0
```

---

## 2. Output Report Fields

The DS4 uses HID output reports to control the light bar. The report structure differs between USB and Bluetooth connections, but the logical fields are the same.

### USB Output Report (Report ID 0x05)

Total length: **32 bytes** (1 byte report ID + 31 bytes payload)

```
Byte:  [0]   [1]      [2]    [3]   [4]       [5]       [6]    [7]     [8]     [9]       [10]
Field: RepID Features  0x04   0x00  RumbleR   RumbleL   Red    Green   Blue    FlashOn   FlashOff
Value: 0x05  0x07     0x04   0x00  0-255     0-255     0-255  0-255   0-255   0-255     0-255
```

| Byte Offset | Field | Range | Description |
|---|---|---|---|
| 0 | Report ID | `0x05` | Fixed USB output report identifier |
| 1 | Features Byte | `0x07` | Bitfield enabling output features (see below) |
| 2 | Unknown | `0x04` | Typically set to `0x04` |
| 3 | Padding | `0x00` | Reserved |
| 4 | Right Motor (weak) | 0-255 | High-frequency rumble motor intensity |
| 5 | Left Motor (strong) | 0-255 | Low-frequency rumble motor intensity |
| **6** | **LED Red** | **0-255** | **Red channel intensity** |
| **7** | **LED Green** | **0-255** | **Green channel intensity** |
| **8** | **LED Blue** | **0-255** | **Blue channel intensity** |
| **9** | **Flash On Duration** | **0-255** | **Time LED stays ON during flash cycle** |
| **10** | **Flash Off Duration** | **0-255** | **Time LED stays OFF during flash cycle** |
| 11-31 | Reserved | 0x00 | Padding / unused bytes |

### Bluetooth Output Report (Report ID 0x11)

Total length: **78 bytes** (report ID + 77 bytes payload, last 4 are CRC-32)

```
Byte:  [0]   [1]          [2]   [3]      [4]    [5]   [6]       [7]       [8]    [9]     [10]    [11]      [12]       ...  [74-77]
Field: RepID PollRate+Flags BTF2 Features 0x04   0x00  RumbleR   RumbleL   Red    Green   Blue    FlashOn   FlashOff   ...  CRC-32
Value: 0x11  0xC0|rate     0x00 0x07     0x04   0x00  0-255     0-255     0-255  0-255   0-255   0-255     0-255      ...  4 bytes
```

| Byte Offset | Field | Range | Description |
|---|---|---|---|
| 0 | Report ID | `0x11` | Bluetooth output report identifier |
| 1 | Poll Rate + Flags | `0xC0 \| rate` | Bits 7-6: flags (`0xC0`), Bits 3-0: BT poll rate (0-16) |
| 2 | BT Flags 2 | `0x00` | Typically 0x00 for standard control output (see BT Protocol doc for audio-specific flag values) |
| 3 | Features Byte | `0x07` | Same bitfield as USB (see below) |
| 4 | Unknown | `0x04` | Typically set to `0x04` |
| 5 | Padding | `0x00` | Reserved |
| 6 | Right Motor (weak) | 0-255 | High-frequency rumble motor intensity |
| 7 | Left Motor (strong) | 0-255 | Low-frequency rumble motor intensity |
| **8** | **LED Red** | **0-255** | **Red channel intensity** |
| **9** | **LED Green** | **0-255** | **Green channel intensity** |
| **10** | **LED Blue** | **0-255** | **Blue channel intensity** |
| **11** | **Flash On Duration** | **0-255** | **Time LED stays ON during flash cycle** |
| **12** | **Flash Off Duration** | **0-255** | **Time LED stays OFF during flash cycle** |
| 13-73 | Reserved | 0x00 | Padding / audio configuration |
| **74-77** | **CRC-32** | 4 bytes | **CRC-32 checksum (required for BT)** |

### Features Byte (Bit Flags)

The features byte controls which output subsystems are enabled:

| Bit | Value | Function |
|---|---|---|
| 0 | `0x01` | Enable rumble motors |
| 1 | `0x02` | Enable light bar color update |
| 2 | `0x04` | Enable light bar flash |
| 3 | `0x08` | Enable extension port write (EXT data) |
| 4 | `0x10` | Headphone volume L |
| 5 | `0x20` | Headphone volume R |
| 6 | `0x40` | Microphone volume |
| 7 | `0x80` | Speaker volume |

Common values:
- `0x07` = Enable rumble + light bar color + light bar flash (default)
- `0x03` = Enable rumble + light bar color only (used by some third-party controllers)
- `0xF7` = All features except speaker volume

### USB vs. Bluetooth Offset Summary

| Field | USB Offset | BT Offset | Difference |
|---|---|---|---|
| Report ID | 0 | 0 | Same byte, different value (`0x05` vs `0x11`) |
| Features byte | 1 | 3 | +2 bytes in BT (BT has poll rate + transaction header) |
| Right rumble motor | 4 | 6 | +2 |
| Left rumble motor | 5 | 7 | +2 |
| **LED Red** | **6** | **8** | **+2** |
| **LED Green** | **7** | **9** | **+2** |
| **LED Blue** | **8** | **10** | **+2** |
| **Flash On** | **9** | **11** | **+2** |
| **Flash Off** | **10** | **12** | **+2** |
| CRC-32 | N/A | 74-77 | BT only |

The general rule: **Bluetooth offsets = USB offsets + 2**, with the addition of a CRC-32 trailer.

### CRC-32 Calculation (Bluetooth Only)

Bluetooth output reports **must** include a valid CRC-32 checksum or the controller will reject the report. The CRC uses the standard polynomial `0x04C11DB7` (same as CRC-32/ISO-HDLC, also known as CRC-32b).

The CRC is seeded with the byte `0xA2` prepended to the report data:

1. Initialize CRC-32 with seed byte `0xA2`
2. Feed bytes 0 through (length - 5) of the output report into the CRC
3. Write the resulting 4-byte CRC in **little-endian** order into the last 4 bytes of the report

```
CRC input:  [0xA2] + outputReport[0 .. length-5]
CRC output: outputReport[length-4 .. length-1] (little-endian)
```

---

## 3. Flash Patterns

### How Flash Timing Works

The DS4 light bar supports hardware-driven flash/blink patterns using two duration values:

- **Flash On Duration**: How long the LED stays **on** during each cycle
- **Flash Off Duration**: How long the LED stays **off** during each cycle

The controller firmware handles the timing internally -- once set, the flash pattern continues autonomously without further host intervention.

### Timing Units

Each unit represents approximately **10 milliseconds**. The full range:

| Value | Duration |
|---|---|
| 0 | 0 ms (disabled) |
| 1 | ~10 ms |
| 10 | ~100 ms |
| 25 | ~250 ms |
| 50 | ~500 ms |
| 100 | ~1 second |
| 128 | ~1.28 seconds |
| 255 | ~2.55 seconds |

### Special Behavior

- **Both On and Off = 0**: Flash is disabled; the LED remains **solidly on** at the set color
- **On = 0, Off > 0**: LED remains **off** permanently
- **On > 0, Off = 0**: LED remains **on** permanently (same as solid)

### Duty Cycle

The duty cycle (percentage of time the LED is on) is:

```
duty_cycle = flash_on / (flash_on + flash_off) * 100%
```

### Common Flash Pattern Examples

| Pattern | On Value | Off Value | On Time | Off Time | Period | Description |
|---|---|---|---|---|---|---|
| Solid (no flash) | 0 | 0 | N/A | N/A | N/A | LED stays on continuously |
| Slow blink | 100 | 100 | 1.0s | 1.0s | 2.0s | Equal on/off, relaxed pace |
| Fast blink | 25 | 25 | 250ms | 250ms | 500ms | Rapid alternating |
| Quick flash | 10 | 90 | 100ms | 900ms | 1.0s | Brief flash, long off |
| Heartbeat-like | 25 | 75 | 250ms | 750ms | 1.0s | Short on, longer off |
| SOS-like | 50 | 50 | 500ms | 500ms | 1.0s | Medium symmetric |
| Warning pulse | 5 | 5 | 50ms | 50ms | 100ms | Very rapid strobe |
| Breathing (slow) | 200 | 56 | 2.0s | 560ms | 2.56s | Long on, short off |
| Nearly always on | 252 | 28 | 2.52s | 280ms | 2.80s | 90% on duty cycle |
| Barely on | 28 | 252 | 280ms | 2.52s | 2.80s | 10% on duty cycle |

### Battery Indicator Flash Durations (from DS4Windows)

DS4Windows uses a tiered flash pattern where the duty cycle reflects the battery percentage:

| Battery Level | On Duration | Off Duration | Duty Cycle |
|---|---|---|---|
| 0% | 28 | 252 | 10% |
| 10% | 28 | 252 | 10% |
| 20% | 56 | 224 | 20% |
| 30% | 84 | 196 | 30% |
| 40% | 112 | 168 | 40% |
| 50% | 140 | 140 | 50% |
| 60% | 168 | 112 | 60% |
| 70% | 196 | 84 | 70% |
| 80% | 224 | 56 | 80% |
| 90% | 252 | 28 | 90% |
| 100% / Charging | 0 | 0 | Solid (no flash) |

### Flash Pattern Timing Diagram

```
Slow Blink (On=100, Off=100):
    ____      ____      ____      ____
   |    |    |    |    |    |    |    |
   | ON |    | ON |    | ON |    | ON |
___|    |____|    |____|    |____|    |____
   1.0s  1.0s 1.0s  1.0s

Quick Flash (On=10, Off=90):
  __          __          __
 |  |        |  |        |  |
 |ON|        |ON|        |ON|
_|  |________|  |________|  |________
 100ms 900ms  100ms 900ms

Battery Low (On=28, Off=252):
  _                              _
 | |                            | |
 |O|                            |O|
_| |____________________________|N|____
 280ms        2520ms            280ms
```

---

## 4. Standard Colors

### PS4 Player Number Colors

The PS4 system assigns specific light bar colors for player identification:

| Player | Color Name | Red | Green | Blue | Hex Code | Preview |
|---|---|---|---|---|---|---|
| Player 1 | Blue | 0 | 0 | 64 | `#000040` | Dark Blue |
| Player 2 | Red | 64 | 0 | 0 | `#400000` | Dark Red |
| Player 3 | Green | 0 | 64 | 0 | `#004000` | Dark Green |
| Player 4 | Pink | 64 | 0 | 64 | `#400040` | Dark Pink/Magenta |

> **Note:** The PS4 system uses relatively dim values (64 rather than 255) to conserve battery. The actual perceived color on the controller is brighter than the hex codes suggest due to the LED optics.

### Full-Brightness Player Colors

For applications that want vivid player identification colors:

| Player | Color Name | Red | Green | Blue | Hex Code |
|---|---|---|---|---|---|
| Player 1 | Blue | 0 | 0 | 255 | `#0000FF` |
| Player 2 | Red | 255 | 0 | 0 | `#FF0000` |
| Player 3 | Green | 0 | 255 | 0 | `#00FF00` |
| Player 4 | Pink | 255 | 0 | 255 | `#FF00FF` |
| Player 5 | White | 255 | 255 | 255 | `#FFFFFF` |
| Player 6 | Cyan | 0 | 255 | 255 | `#00FFFF` |
| Player 7 | Orange | 255 | 165 | 0 | `#FFA500` |
| Player 8 | Yellow | 255 | 255 | 0 | `#FFFF00` |

### System Status Colors

Colors used by the PS4 system for various states:

| State | Color Name | Red | Green | Blue | Hex Code | Behavior |
|---|---|---|---|---|---|---|
| Charging | Orange/Amber | 255 | 165 | 0 | `#FFA500` | Slow pulse/blink |
| Fully Charged | Off | 0 | 0 | 0 | `#000000` | Light bar off |
| Low Battery | Current color | varies | varies | varies | varies | Flashing (see Section 7) |
| Pairing Mode | White (rapid) | 255 | 255 | 255 | `#FFFFFF` | Rapid double-blink |
| Disconnected | Off | 0 | 0 | 0 | `#000000` | Light bar off |
| Rest Mode Charging | Orange | 255 | 165 | 0 | `#FFA500` | Slow pulsing, then off when full |

---

## 5. Implementation Guide for macOS

### Setting the Light Bar Color via USB

On macOS, you interact with the DS4 through the IOKit HID framework. USB output reports use Report ID `0x05`.

```objc
#import <IOKit/hid/IOHIDManager.h>

// Set the DS4 light bar color via USB
void ds4_set_lightbar_usb(IOHIDDeviceRef device, uint8_t red, uint8_t green, uint8_t blue) {
    uint8_t report[32] = {0};

    report[0] = 0x05;  // Report ID
    report[1] = 0x07;  // Features: enable rumble + lightbar + flash
    report[2] = 0x04;  //
    report[3] = 0x00;  // Padding
    report[4] = 0x00;  // Right rumble motor (weak)
    report[5] = 0x00;  // Left rumble motor (strong)
    report[6] = red;   // LED Red
    report[7] = green; // LED Green
    report[8] = blue;  // LED Blue
    report[9] = 0x00;  // Flash on duration (0 = no flash)
    report[10] = 0x00; // Flash off duration (0 = no flash)

    IOHIDDeviceSetReport(device,
                         kIOHIDReportTypeOutput,
                         0x05,       // Report ID
                         report + 1, // Data starts after report ID for IOKit
                         31);        // Length excludes report ID
}
```

### Setting the Light Bar Color via Bluetooth

Bluetooth requires Report ID `0x11` and a CRC-32 checksum appended to the report.

```objc
#import <IOKit/hid/IOHIDManager.h>
#import <zlib.h> // For crc32()

// Set the DS4 light bar color via Bluetooth
void ds4_set_lightbar_bt(IOHIDDeviceRef device, uint8_t red, uint8_t green, uint8_t blue) {
    uint8_t report[78] = {0};

    report[0]  = 0x11;  // Report ID
    report[1]  = 0xC0;  // Poll rate flags (0xC0 = default)
    report[2]  = 0x00;  // BT Flags 2: typically 0x00 for standard control output
    report[3]  = 0x07;  // Features: enable rumble + lightbar + flash
    report[4]  = 0x04;  //
    report[5]  = 0x00;  // Padding
    report[6]  = 0x00;  // Right rumble motor (weak)
    report[7]  = 0x00;  // Left rumble motor (strong)
    report[8]  = red;   // LED Red
    report[9]  = green; // LED Green
    report[10] = blue;  // LED Blue
    report[11] = 0x00;  // Flash on duration
    report[12] = 0x00;  // Flash off duration
    // Bytes 13-73: zeros (reserved)

    // Calculate CRC-32
    // The CRC is seeded with 0xA2 prepended to the report data
    uint8_t seed = 0xA2;
    uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
    crc = (uint32_t)crc32(crc, &seed, 1);
    crc = (uint32_t)crc32(crc, report, 74);

    // Append CRC-32 in little-endian
    report[74] = (uint8_t)(crc & 0xFF);
    report[75] = (uint8_t)((crc >> 8) & 0xFF);
    report[76] = (uint8_t)((crc >> 16) & 0xFF);
    report[77] = (uint8_t)((crc >> 24) & 0xFF);

    // IOKit expects data after the report ID, with length excluding the report ID
    IOHIDDeviceSetReport(device,
                         kIOHIDReportTypeOutput,
                         0x11,       // Report ID
                         report + 1, // Data starts after report ID
                         77);        // Length excludes report ID
}
```

### Creating Flash Patterns

To flash the light bar, set both the color AND the flash timing values in the same report:

```objc
// Flash a red warning light: 250ms on, 750ms off
void ds4_flash_warning(IOHIDDeviceRef device, bool isBluetooth) {
    if (isBluetooth) {
        uint8_t report[78] = {0};
        report[0]  = 0x11;
        report[1]  = 0xC0;
        report[2]  = 0x00;  // BT Flags 2
        report[3]  = 0x07;  // Enable rumble + lightbar + flash
        report[4]  = 0x04;
        report[8]  = 255;   // Red
        report[9]  = 0;     // Green
        report[10] = 0;     // Blue
        report[11] = 25;    // Flash on: 25 * 10ms = 250ms
        report[12] = 75;    // Flash off: 75 * 10ms = 750ms

        // Calculate and append CRC-32
        uint8_t seed = 0xA2;
        uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
        crc = (uint32_t)crc32(crc, &seed, 1);
        crc = (uint32_t)crc32(crc, report, 74);
        report[74] = (uint8_t)(crc & 0xFF);
        report[75] = (uint8_t)((crc >> 8) & 0xFF);
        report[76] = (uint8_t)((crc >> 16) & 0xFF);
        report[77] = (uint8_t)((crc >> 24) & 0xFF);

        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, report + 1, 77);
    } else {
        uint8_t report[32] = {0};
        report[0]  = 0x05;
        report[1]  = 0x07;
        report[2]  = 0x04;
        report[6]  = 255;   // Red
        report[7]  = 0;     // Green
        report[8]  = 0;     // Blue
        report[9]  = 25;    // Flash on: 250ms
        report[10] = 75;    // Flash off: 750ms

        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x05, report + 1, 31);
    }
}
```

### Stopping a Flash Pattern

To stop flashing and return to a solid color, set the flash durations to zero. It is good practice to send the stop command **twice** -- once to stop the flash cycle, and once more to ensure the LED is solidly on:

```objc
void ds4_stop_flash(IOHIDDeviceRef device, uint8_t red, uint8_t green, uint8_t blue, bool isBluetooth) {
    // Send twice to reliably stop flashing
    for (int i = 0; i < 2; i++) {
        if (isBluetooth) {
            ds4_set_lightbar_bt(device, red, green, blue);
        } else {
            ds4_set_lightbar_usb(device, red, green, blue);
        }
    }
}
```

> This two-send approach is used by ds4drv and is necessary because the first send stops the flash state machine, and the second ensures the LED is set to the desired solid color.

### Smooth Color Transitions (Fade Effects)

The DS4 light bar does not support hardware fade/transition. To create smooth fading, you must send rapid color updates from the host. A linear interpolation at ~25 Hz (every 40ms) produces visually smooth results:

```objc
// Linear interpolation between two colors
typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} DS4Color;

DS4Color ds4_lerp_color(DS4Color from, DS4Color to, float t) {
    DS4Color result;
    result.red   = (uint8_t)(from.red   + (to.red   - from.red)   * t);
    result.green = (uint8_t)(from.green + (to.green - from.green) * t);
    result.blue  = (uint8_t)(from.blue  + (to.blue  - from.blue)  * t);
    return result;
}

// Fade from one color to another over `duration_ms` milliseconds
void ds4_fade_color(IOHIDDeviceRef device, bool isBluetooth,
                    DS4Color from, DS4Color to, uint32_t duration_ms) {
    const uint32_t step_ms = 40; // 25 Hz update rate
    uint32_t steps = duration_ms / step_ms;
    if (steps == 0) steps = 1;

    for (uint32_t i = 0; i <= steps; i++) {
        float t = (float)i / (float)steps;
        DS4Color color = ds4_lerp_color(from, to, t);

        if (isBluetooth) {
            ds4_set_lightbar_bt(device, color.red, color.green, color.blue);
        } else {
            ds4_set_lightbar_usb(device, color.red, color.green, color.blue);
        }

        usleep(step_ms * 1000);
    }
}
```

---

## 6. Color Presets Table

### Basic Colors

| Color Name | Red | Green | Blue | Hex Code | Notes |
|---|---|---|---|---|---|
| Red | 255 | 0 | 0 | `#FF0000` | Pure red |
| Green | 0 | 255 | 0 | `#00FF00` | Pure green |
| Blue | 0 | 0 | 255 | `#0000FF` | Pure blue |
| White | 255 | 255 | 255 | `#FFFFFF` | Maximum brightness |
| Off / Black | 0 | 0 | 0 | `#000000` | LED off |
| Yellow | 255 | 255 | 0 | `#FFFF00` | |
| Cyan | 0 | 255 | 255 | `#00FFFF` | |
| Magenta | 255 | 0 | 255 | `#FF00FF` | |
| Orange | 255 | 165 | 0 | `#FFA500` | System charging color |
| Purple | 128 | 0 | 255 | `#8000FF` | |
| Pink | 255 | 105 | 180 | `#FF69B4` | Hot pink |
| Lime | 50 | 205 | 50 | `#32CD32` | Lime green |

### Dimmed / Battery-Friendly Colors

These use lower values to conserve battery life:

| Color Name | Red | Green | Blue | Hex Code | Notes |
|---|---|---|---|---|---|
| Dim Blue | 0 | 0 | 64 | `#000040` | PS4 Player 1 (system) |
| Dim Red | 64 | 0 | 0 | `#400000` | PS4 Player 2 (system) |
| Dim Green | 0 | 64 | 0 | `#004000` | PS4 Player 3 (system) |
| Dim Magenta | 64 | 0 | 64 | `#400040` | PS4 Player 4 (system) |
| Dim White | 32 | 32 | 32 | `#202020` | Subtle indicator |
| Dim Orange | 64 | 40 | 0 | `#402800` | Low-power charging |
| Dim Cyan | 0 | 40 | 40 | `#002828` | Subtle cool indicator |
| Bluetooth Default | 32 | 64 | 64 | `#204040` | DS4Windows BT default |

### Game Notification Colors

| Use Case | Color Name | Red | Green | Blue | Hex Code |
|---|---|---|---|---|---|
| Health Full | Green | 0 | 255 | 0 | `#00FF00` |
| Health Medium | Yellow | 255 | 255 | 0 | `#FFFF00` |
| Health Low | Orange | 255 | 128 | 0 | `#FF8000` |
| Health Critical | Red | 255 | 0 | 0 | `#FF0000` |
| Shield Active | Cyan | 0 | 200 | 255 | `#00C8FF` |
| Damage Taken | Red Flash | 255 | 0 | 0 | `#FF0000` |
| Healing | Green Pulse | 0 | 255 | 128 | `#00FF80` |
| Power-Up | Gold | 255 | 215 | 0 | `#FFD700` |
| Stealth | Dark Purple | 30 | 0 | 50 | `#1E0032` |
| Alert / Warning | Amber | 255 | 191 | 0 | `#FFBF00` |
| Police Red | Red | 255 | 0 | 0 | `#FF0000` |
| Police Blue | Blue | 0 | 0 | 255 | `#0000FF` |
| Ice / Frozen | Light Blue | 100 | 180 | 255 | `#64B4FF` |
| Fire | Orange-Red | 255 | 80 | 0 | `#FF5000` |
| Poison | Toxic Green | 0 | 200 | 0 | `#00C800` |
| Magic / Mana | Purple | 150 | 0 | 255 | `#9600FF` |

### Rainbow / Hue Cycle Reference Points

For rainbow cycling, these are the primary hue stops:

| Hue Angle | Color | Red | Green | Blue |
|---|---|---|---|---|
| 0 | Red | 255 | 0 | 0 |
| 60 | Yellow | 255 | 255 | 0 |
| 120 | Green | 0 | 255 | 0 |
| 180 | Cyan | 0 | 255 | 255 |
| 240 | Blue | 0 | 0 | 255 |
| 300 | Magenta | 255 | 0 | 255 |
| 360 | Red (wrap) | 255 | 0 | 0 |

---

## 7. Battery Level Indication

### How the PS4 Uses Light Bar for Battery Status

The PS4 system uses the light bar to communicate battery state to the player through a combination of color and flash patterns.

### During Normal Gameplay (Wireless)

The player's assigned color (blue, red, green, or pink) is displayed solidly. When battery gets low, the system transitions:

1. **Battery Good (100%-20%)**: Solid player color, no flashing
2. **Battery Low (below ~20%)**: Player color begins flashing with increasing urgency
3. **Battery Critical (below ~10%)**: Rapid flashing

### While Charging (USB Connected)

| State | Light Bar Behavior |
|---|---|
| Charging, low battery | Slow amber/orange pulse |
| Charging, medium battery | Slow amber/orange pulse |
| Charging, nearly full | Slow amber/orange pulse |
| Fully charged | Light bar turns off (rest mode) or returns to player color (active) |

### DS4Windows Battery Flash Implementation

DS4Windows implements a sophisticated battery indicator where the flash duty cycle directly maps to the battery percentage. The battery level (0-100%) is divided into 10 tiers, and the on/off durations are chosen so the duty cycle approximates the charge level:

```
Battery  0-9%:   On=28,  Off=252   (10% duty cycle - mostly off)
Battery 10-19%:  On=28,  Off=252   (10% duty cycle)
Battery 20-29%:  On=56,  Off=224   (20% duty cycle)
Battery 30-39%:  On=84,  Off=196   (30% duty cycle)
Battery 40-49%:  On=112, Off=168   (40% duty cycle)
Battery 50-59%:  On=140, Off=140   (50% duty cycle)
Battery 60-69%:  On=168, Off=112   (60% duty cycle)
Battery 70-79%:  On=196, Off=84    (70% duty cycle)
Battery 80-89%:  On=224, Off=56    (80% duty cycle)
Battery 90-99%:  On=252, Off=28    (90% duty cycle)
Battery 100%:    On=0,   Off=0     (solid - no flash)
```

The total cycle time (On + Off) is always 280 units (~2.8 seconds), creating a consistent rhythm where only the on/off ratio changes.

### Charging Animation Types (DS4Windows)

DS4Windows supports multiple charging indicator styles:

| Type | Description |
|---|---|
| **Type 0** | Standard flash -- same battery tier flash pattern |
| **Type 1** | Pulse fade -- color fades smoothly between full and off over 4 seconds |
| **Type 2** | Rainbow cycle -- slowly cycles through hue spectrum while charging |
| **Type 3** | Custom color -- user-defined static charging color |

### Reading Battery Level from Input Reports

The battery level is available in the DS4 input report:

- **USB Input Report (0x01)**: Byte 30, lower nibble (bits 0-3) = battery level (0-10)
- **Bluetooth Input Report (0x11)**: Same position relative to data start (offset by 2 bytes for BT header)

Battery value mapping:
- Value 0-10 maps to 0%-100% in 10% increments
- Bit 4 of the same byte (`buf[30] & 0x10`) indicates USB power is connected
- The controller reports a value of 0-10, multiply by 10 for percentage

---

## 8. Use Cases

### Player Identification

The most fundamental use of the light bar. Assign a unique color to each connected controller so players can instantly identify which controller belongs to them:

```
Player 1: Blue    (0, 0, 255)
Player 2: Red     (255, 0, 0)
Player 3: Green   (0, 255, 0)
Player 4: Pink    (255, 0, 255)
```

This is especially useful in local multiplayer scenarios where multiple controllers are connected simultaneously.

### Game Health / Status Indicators

Map the light bar color to in-game health, shields, or other status:

```
100% health -> Green  (0, 255, 0)
 75% health -> Yellow (255, 255, 0)
 50% health -> Orange (255, 128, 0)
 25% health -> Red    (255, 0, 0)
 10% health -> Red    (255, 0, 0) + flashing
  0% health -> Off    (0, 0, 0)
```

### Environmental / Atmospheric Feedback

Match the light bar to the game world:
- **Underwater**: Deep blue with slow pulsing
- **On fire**: Orange/red with rapid flickering
- **In a dark cave**: Dim white or off
- **Poisoned**: Green pulsing
- **Frozen/ice area**: Light blue

### Notification Alerts

Use flash patterns to alert players without interrupting gameplay:
- **Incoming message**: Brief blue double-flash
- **Achievement unlocked**: Gold pulse
- **Timer running low**: Increasingly rapid red flash
- **Objective complete**: Green solid for 2 seconds

### Battery Monitoring

Display battery status through the light bar to prevent unexpected disconnections:
- Fade from green to red as battery depletes
- Flash warning when below 20%
- Show amber while charging

### Music Visualization

React to audio input by mapping frequency or amplitude to light bar colors:
- Bass hits: Red pulse
- Treble peaks: Blue flash
- Average amplitude: Brightness intensity
- Frequency spectrum: Hue rotation

### Police / Emergency Lights

Alternate between red and blue rapidly for racing games or action sequences:
- Alternate red/blue every 100-200ms
- Use maximum brightness for both colors

### Connection Status

Indicate the controller's connection state:
- **Bluetooth connected**: Subtle blue glow
- **USB connected**: Subtle green glow
- **Searching/pairing**: White rapid flash
- **Error**: Red rapid flash

---

## 9. Code Examples

### Complete Output Report Builder (C / Objective-C)

This is a comprehensive implementation covering both USB and Bluetooth, with all light bar features:

```objc
#import <IOKit/hid/IOHIDManager.h>
#import <zlib.h>

// ---------------------------------------------------------------------------
// Data Types
// ---------------------------------------------------------------------------

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} DS4LightBarColor;

typedef struct {
    uint8_t flashOn;   // Flash on duration (units of ~10ms, 0=no flash)
    uint8_t flashOff;  // Flash off duration (units of ~10ms, 0=no flash)
} DS4FlashPattern;

typedef struct {
    uint8_t rightMotor;  // Weak / high-frequency (0-255)
    uint8_t leftMotor;   // Strong / low-frequency (0-255)
} DS4Rumble;

typedef enum {
    DS4ConnectionUSB,
    DS4ConnectionBluetooth
} DS4ConnectionType;

typedef struct {
    DS4LightBarColor  color;
    DS4FlashPattern   flash;
    DS4Rumble         rumble;
} DS4OutputState;

// ---------------------------------------------------------------------------
// Output Report Construction
// ---------------------------------------------------------------------------

/// Build and send a complete DS4 output report.
/// Returns true on success.
bool ds4_send_output_report(IOHIDDeviceRef device,
                            DS4ConnectionType connType,
                            const DS4OutputState *state) {
    if (connType == DS4ConnectionUSB) {
        // --- USB Report (Report ID 0x05, 32 bytes total) ---
        uint8_t report[32] = {0};

        report[0]  = 0x05;               // Report ID
        report[1]  = 0x07;               // Features: rumble + lightbar + flash
        report[2]  = 0x04;               //
        report[3]  = 0x00;               // Padding
        report[4]  = state->rumble.rightMotor;  // Right rumble (weak)
        report[5]  = state->rumble.leftMotor;   // Left rumble (strong)
        report[6]  = state->color.red;          // LED Red
        report[7]  = state->color.green;        // LED Green
        report[8]  = state->color.blue;         // LED Blue
        report[9]  = state->flash.flashOn;      // Flash on duration
        report[10] = state->flash.flashOff;     // Flash off duration

        IOReturn result = IOHIDDeviceSetReport(device,
                                               kIOHIDReportTypeOutput,
                                               0x05,
                                               report + 1,  // Skip report ID
                                               31);
        return (result == kIOReturnSuccess);

    } else {
        // --- Bluetooth Report (Report ID 0x11, 78 bytes total) ---
        uint8_t report[78] = {0};

        report[0]  = 0x11;               // Report ID
        report[1]  = 0xC0;               // Poll rate flags
        report[2]  = 0x00;               // BT Flags 2: 0x00 for standard control output
        report[3]  = 0x07;               // Features: rumble + lightbar + flash
        report[4]  = 0x04;               //
        report[5]  = 0x00;               // Padding
        report[6]  = state->rumble.rightMotor;  // Right rumble (weak)
        report[7]  = state->rumble.leftMotor;   // Left rumble (strong)
        report[8]  = state->color.red;          // LED Red
        report[9]  = state->color.green;        // LED Green
        report[10] = state->color.blue;         // LED Blue
        report[11] = state->flash.flashOn;      // Flash on duration
        report[12] = state->flash.flashOff;     // Flash off duration

        // Calculate CRC-32 (seed with 0xA2)
        uint8_t seed = 0xA2;
        uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
        crc = (uint32_t)crc32(crc, &seed, 1);
        crc = (uint32_t)crc32(crc, report, 74);

        // Append CRC in little-endian
        report[74] = (uint8_t)(crc & 0xFF);
        report[75] = (uint8_t)((crc >> 8) & 0xFF);
        report[76] = (uint8_t)((crc >> 16) & 0xFF);
        report[77] = (uint8_t)((crc >> 24) & 0xFF);

        IOReturn result = IOHIDDeviceSetReport(device,
                                               kIOHIDReportTypeOutput,
                                               0x11,
                                               report + 1,  // Skip report ID
                                               77);
        return (result == kIOReturnSuccess);
    }
}

// ---------------------------------------------------------------------------
// Convenience Functions
// ---------------------------------------------------------------------------

/// Set a static light bar color (no flash, no rumble).
bool ds4_set_color(IOHIDDeviceRef device, DS4ConnectionType connType,
                   uint8_t red, uint8_t green, uint8_t blue) {
    DS4OutputState state = {0};
    state.color = (DS4LightBarColor){red, green, blue};
    return ds4_send_output_report(device, connType, &state);
}

/// Set a flashing light bar pattern.
bool ds4_set_flash(IOHIDDeviceRef device, DS4ConnectionType connType,
                   uint8_t red, uint8_t green, uint8_t blue,
                   uint8_t flashOn, uint8_t flashOff) {
    DS4OutputState state = {0};
    state.color = (DS4LightBarColor){red, green, blue};
    state.flash = (DS4FlashPattern){flashOn, flashOff};
    return ds4_send_output_report(device, connType, &state);
}

/// Turn the light bar off.
bool ds4_lightbar_off(IOHIDDeviceRef device, DS4ConnectionType connType) {
    return ds4_set_color(device, connType, 0, 0, 0);
}
```

### Setting a Static Color

```objc
// Set light bar to solid blue (Player 1 color)
ds4_set_color(device, DS4ConnectionUSB, 0, 0, 255);

// Set light bar to dim orange (battery-friendly charging indicator)
ds4_set_color(device, DS4ConnectionBluetooth, 64, 40, 0);

// Set light bar to white at 50% brightness
ds4_set_color(device, DS4ConnectionUSB, 128, 128, 128);
```

### Creating a Flash Pattern

```objc
// Red warning flash: 250ms on, 750ms off
ds4_set_flash(device, DS4ConnectionUSB, 255, 0, 0, 25, 75);

// Slow blue pulse: 1 second on, 1 second off
ds4_set_flash(device, DS4ConnectionBluetooth, 0, 0, 255, 100, 100);

// Rapid green strobe
ds4_set_flash(device, DS4ConnectionUSB, 0, 255, 0, 5, 5);

// Stop flashing (return to solid color)
ds4_set_color(device, DS4ConnectionUSB, 0, 0, 255);
```

### Battery Level Indicator

```objc
// Battery flash durations: index = battery_level / 10
static const uint8_t batteryFlashOn[11] =  {28,28,56,84,112,140,168,196,224,252,0};
static const uint8_t batteryFlashOff[11] = {252,252,224,196,168,140,112,84,56,28,0};

/// Update light bar based on battery level (0-100) and charging state.
void ds4_update_battery_indicator(IOHIDDeviceRef device,
                                  DS4ConnectionType connType,
                                  int batteryPercent,
                                  bool isCharging) {
    int level = batteryPercent / 10;
    if (level > 10) level = 10;

    if (isCharging) {
        // Charging: show amber, solid (no flash)
        ds4_set_color(device, connType, 255, 165, 0);
    } else if (batteryPercent <= 20) {
        // Low battery: red with appropriate flash rate
        ds4_set_flash(device, connType,
                      255, 0, 0,
                      batteryFlashOn[level],
                      batteryFlashOff[level]);
    } else {
        // Normal: interpolate green -> yellow -> red
        uint8_t red, green;
        if (batteryPercent >= 50) {
            // 50-100%: green to yellow transition
            float t = (float)(100 - batteryPercent) / 50.0f;
            red   = (uint8_t)(255.0f * t);
            green = 255;
        } else {
            // 0-50%: yellow to red transition
            float t = (float)batteryPercent / 50.0f;
            red   = 255;
            green = (uint8_t)(255.0f * t);
        }
        ds4_set_color(device, connType, red, green, 0);
    }
}
```

### Color Cycling Animation (Rainbow)

```objc
#include <math.h>

/// Convert hue (0-360) to RGB with given saturation (0-255).
DS4LightBarColor ds4_hue_to_rgb(float hue, uint8_t saturation) {
    DS4LightBarColor color = {0, 0, 0};
    uint8_t C = saturation;
    float X_f = C * (1.0f - fabsf(fmodf(hue / 60.0f, 2.0f) - 1.0f));
    uint8_t X = (uint8_t)X_f;

    if      (hue < 60)  { color.red = C; color.green = X; color.blue = 0; }
    else if (hue < 120) { color.red = X; color.green = C; color.blue = 0; }
    else if (hue < 180) { color.red = 0; color.green = C; color.blue = X; }
    else if (hue < 240) { color.red = 0; color.green = X; color.blue = C; }
    else if (hue < 300) { color.red = X; color.green = 0; color.blue = C; }
    else                { color.red = C; color.green = 0; color.blue = X; }

    return color;
}

/// Run a continuous rainbow cycle on the light bar.
/// cycleDurationSec: how many seconds for one full hue rotation.
/// totalDurationSec: how long to run the animation.
void ds4_rainbow_cycle(IOHIDDeviceRef device,
                       DS4ConnectionType connType,
                       float cycleDurationSec,
                       float totalDurationSec) {
    const uint32_t stepMs = 40; // 25 Hz update rate
    uint32_t totalSteps = (uint32_t)(totalDurationSec * 1000.0f / stepMs);
    float degreesPerStep = 360.0f / (cycleDurationSec * 1000.0f / stepMs);

    float hue = 0.0f;
    for (uint32_t i = 0; i < totalSteps; i++) {
        DS4LightBarColor color = ds4_hue_to_rgb(hue, 255);
        ds4_set_color(device, connType, color.red, color.green, color.blue);

        hue += degreesPerStep;
        if (hue >= 360.0f) hue -= 360.0f;

        usleep(stepMs * 1000);
    }
}
```

### Complete Swift Implementation

```swift
import IOKit.hid
import zlib

// MARK: - Data Types

struct DS4Color {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static let off     = DS4Color(red: 0,   green: 0,   blue: 0)
    static let red     = DS4Color(red: 255, green: 0,   blue: 0)
    static let green   = DS4Color(red: 0,   green: 255, blue: 0)
    static let blue    = DS4Color(red: 0,   green: 0,   blue: 255)
    static let white   = DS4Color(red: 255, green: 255, blue: 255)
    static let orange  = DS4Color(red: 255, green: 165, blue: 0)
    static let yellow  = DS4Color(red: 255, green: 255, blue: 0)
    static let cyan    = DS4Color(red: 0,   green: 255, blue: 255)
    static let magenta = DS4Color(red: 255, green: 0,   blue: 255)
    static let purple  = DS4Color(red: 128, green: 0,   blue: 255)

    // PS4 system player colors (dimmed)
    static let player1 = DS4Color(red: 0,  green: 0,  blue: 64)
    static let player2 = DS4Color(red: 64, green: 0,  blue: 0)
    static let player3 = DS4Color(red: 0,  green: 64, blue: 0)
    static let player4 = DS4Color(red: 64, green: 0,  blue: 64)

    /// Linearly interpolate between two colors.
    func lerp(to target: DS4Color, t: Float) -> DS4Color {
        let t = min(max(t, 0), 1)
        return DS4Color(
            red:   UInt8(Float(red)   + Float(Int(target.red)   - Int(red))   * t),
            green: UInt8(Float(green) + Float(Int(target.green) - Int(green)) * t),
            blue:  UInt8(Float(blue)  + Float(Int(target.blue)  - Int(blue))  * t)
        )
    }

    /// Create a color from a hue value (0-360 degrees) and saturation (0-255).
    static func fromHue(_ hue: Float, saturation: UInt8 = 255) -> DS4Color {
        let c = Float(saturation)
        let x = c * (1.0 - abs(fmod(hue / 60.0, 2.0) - 1.0))
        let xi = UInt8(x)
        let ci = saturation

        switch hue {
        case 0..<60:    return DS4Color(red: ci, green: xi, blue: 0)
        case 60..<120:  return DS4Color(red: xi, green: ci, blue: 0)
        case 120..<180: return DS4Color(red: 0,  green: ci, blue: xi)
        case 180..<240: return DS4Color(red: 0,  green: xi, blue: ci)
        case 240..<300: return DS4Color(red: xi, green: 0,  blue: ci)
        case 300..<360: return DS4Color(red: ci, green: 0,  blue: xi)
        default:        return .red
        }
    }

    /// Scale brightness while preserving hue (0.0 = off, 1.0 = full).
    func withBrightness(_ brightness: Float) -> DS4Color {
        let b = min(max(brightness, 0), 1)
        return DS4Color(
            red:   UInt8(Float(red)   * b),
            green: UInt8(Float(green) * b),
            blue:  UInt8(Float(blue)  * b)
        )
    }
}

struct DS4FlashPattern {
    var onDuration: UInt8   // Units of ~10ms
    var offDuration: UInt8  // Units of ~10ms

    static let none = DS4FlashPattern(onDuration: 0, offDuration: 0)
    static let slowBlink = DS4FlashPattern(onDuration: 100, offDuration: 100)
    static let fastBlink = DS4FlashPattern(onDuration: 25, offDuration: 25)
    static let quickFlash = DS4FlashPattern(onDuration: 10, offDuration: 90)
    static let warningPulse = DS4FlashPattern(onDuration: 5, offDuration: 5)
}

enum DS4ConnectionType {
    case usb
    case bluetooth
}

// MARK: - Light Bar Controller

class DS4LightBar {

    // Battery flash durations (index = batteryLevel / 10)
    private static let batteryFlashOn:  [UInt8] = [28,28,56,84,112,140,168,196,224,252,0]
    private static let batteryFlashOff: [UInt8] = [252,252,224,196,168,140,112,84,56,28,0]

    /// Send a complete output report to the DS4.
    static func sendOutputReport(device: IOHIDDevice,
                                 connectionType: DS4ConnectionType,
                                 color: DS4Color,
                                 flash: DS4FlashPattern = .none,
                                 rumbleRight: UInt8 = 0,
                                 rumbleLeft: UInt8 = 0) -> Bool {
        switch connectionType {
        case .usb:
            return sendUSBReport(device: device, color: color, flash: flash,
                                 rumbleRight: rumbleRight, rumbleLeft: rumbleLeft)
        case .bluetooth:
            return sendBluetoothReport(device: device, color: color, flash: flash,
                                       rumbleRight: rumbleRight, rumbleLeft: rumbleLeft)
        }
    }

    // MARK: USB Report

    private static func sendUSBReport(device: IOHIDDevice,
                                      color: DS4Color,
                                      flash: DS4FlashPattern,
                                      rumbleRight: UInt8,
                                      rumbleLeft: UInt8) -> Bool {
        var report = [UInt8](repeating: 0, count: 32)

        report[0]  = 0x05  // Report ID
        report[1]  = 0x07  // Features: rumble + lightbar + flash
        report[2]  = 0x04
        report[3]  = 0x00
        report[4]  = rumbleRight
        report[5]  = rumbleLeft
        report[6]  = color.red
        report[7]  = color.green
        report[8]  = color.blue
        report[9]  = flash.onDuration
        report[10] = flash.offDuration

        // Note: IOKit expects data starting after the report ID byte, with
        // length excluding the report ID. This is the standard IOKit HID pattern.
        let result = IOHIDDeviceSetReport(device,
                                          kIOHIDReportTypeOutput,
                                          0x05,
                                          &report[1],  // Skip report ID
                                          31)
        return result == kIOReturnSuccess
    }

    // MARK: Bluetooth Report

    private static func sendBluetoothReport(device: IOHIDDevice,
                                            color: DS4Color,
                                            flash: DS4FlashPattern,
                                            rumbleRight: UInt8,
                                            rumbleLeft: UInt8) -> Bool {
        var report = [UInt8](repeating: 0, count: 78)

        report[0]  = 0x11  // Report ID
        report[1]  = 0xC0  // Poll rate flags
        report[2]  = 0x00  // BT Flags 2: typically 0x00 for standard control output
        report[3]  = 0x07  // Features: rumble + lightbar + flash
        report[4]  = 0x04
        report[5]  = 0x00
        report[6]  = rumbleRight
        report[7]  = rumbleLeft
        report[8]  = color.red
        report[9]  = color.green
        report[10] = color.blue
        report[11] = flash.onDuration
        report[12] = flash.offDuration

        // Calculate CRC-32 seeded with 0xA2
        // Note: zlib's crc32() returns UInt on 64-bit Swift platforms, not UInt32.
        // Explicit truncation to UInt32 may be needed depending on usage context.
        var crc = UInt32(0)
        var seed: [UInt8] = [0xA2]
        crc = UInt32(crc32(0, &seed, 1))
        crc = UInt32(crc32(uLong(crc), &report, 74))

        // Append CRC in little-endian
        report[74] = UInt8(crc & 0xFF)
        report[75] = UInt8((crc >> 8) & 0xFF)
        report[76] = UInt8((crc >> 16) & 0xFF)
        report[77] = UInt8((crc >> 24) & 0xFF)

        // Note: IOKit expects data starting after the report ID byte, with
        // length excluding the report ID. This is the standard IOKit HID pattern.
        let result = IOHIDDeviceSetReport(device,
                                          kIOHIDReportTypeOutput,
                                          0x11,
                                          &report[1],
                                          77)
        return result == kIOReturnSuccess
    }

    // MARK: Battery Indicator

    /// Update the light bar to indicate battery level.
    static func showBatteryLevel(device: IOHIDDevice,
                                 connectionType: DS4ConnectionType,
                                 batteryPercent: Int,
                                 isCharging: Bool) -> Bool {
        let level = min(batteryPercent / 10, 10)

        if isCharging {
            return sendOutputReport(device: device,
                                    connectionType: connectionType,
                                    color: .orange)
        }

        if batteryPercent <= 20 {
            return sendOutputReport(
                device: device,
                connectionType: connectionType,
                color: .red,
                flash: DS4FlashPattern(
                    onDuration: batteryFlashOn[level],
                    offDuration: batteryFlashOff[level]
                )
            )
        }

        // Interpolate green -> yellow -> red
        let color: DS4Color
        if batteryPercent >= 50 {
            let t = Float(100 - batteryPercent) / 50.0
            color = DS4Color(red: UInt8(255.0 * t), green: 255, blue: 0)
        } else {
            let t = Float(batteryPercent) / 50.0
            color = DS4Color(red: 255, green: UInt8(255.0 * t), blue: 0)
        }

        return sendOutputReport(device: device,
                                connectionType: connectionType,
                                color: color)
    }

    // MARK: Color Cycling

    /// Run a rainbow color cycle animation.
    /// - Parameters:
    ///   - cycleDuration: Seconds for one full hue rotation.
    ///   - totalDuration: Total seconds to run the animation.
    ///   - updateRate: Milliseconds between updates (default 40ms = 25Hz).
    static func rainbowCycle(device: IOHIDDevice,
                             connectionType: DS4ConnectionType,
                             cycleDuration: Float = 5.0,
                             totalDuration: Float = 30.0,
                             updateRate: UInt32 = 40) {
        let totalSteps = Int(totalDuration * 1000.0 / Float(updateRate))
        let degreesPerStep = 360.0 / (cycleDuration * 1000.0 / Float(updateRate))

        var hue: Float = 0
        for _ in 0..<totalSteps {
            let color = DS4Color.fromHue(hue, saturation: 255)
            _ = sendOutputReport(device: device,
                                 connectionType: connectionType,
                                 color: color)

            hue += degreesPerStep
            if hue >= 360.0 { hue -= 360.0 }

            usleep(updateRate * 1000)
        }
    }

    // MARK: Color Fade

    /// Smoothly fade from one color to another.
    static func fadeColor(device: IOHIDDevice,
                          connectionType: DS4ConnectionType,
                          from: DS4Color,
                          to: DS4Color,
                          durationMs: UInt32) {
        let stepMs: UInt32 = 40
        let steps = max(durationMs / stepMs, 1)

        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let color = from.lerp(to: to, t: t)
            _ = sendOutputReport(device: device,
                                 connectionType: connectionType,
                                 color: color)
            usleep(stepMs * 1000)
        }
    }
}
```

### Usage Examples (Swift)

```swift
// Set solid blue for Player 1
DS4LightBar.sendOutputReport(device: myDevice,
                             connectionType: .usb,
                             color: .player1)

// Set a custom color
DS4LightBar.sendOutputReport(device: myDevice,
                             connectionType: .bluetooth,
                             color: DS4Color(red: 255, green: 128, blue: 0))

// Flash red warning
DS4LightBar.sendOutputReport(device: myDevice,
                             connectionType: .usb,
                             color: .red,
                             flash: .fastBlink)

// Show battery at 35%
DS4LightBar.showBatteryLevel(device: myDevice,
                             connectionType: .usb,
                             batteryPercent: 35,
                             isCharging: false)

// Rainbow cycle for 10 seconds with 3-second rotation
DS4LightBar.rainbowCycle(device: myDevice,
                         connectionType: .usb,
                         cycleDuration: 3.0,
                         totalDuration: 10.0)

// Fade from red to blue over 2 seconds
DS4LightBar.fadeColor(device: myDevice,
                      connectionType: .usb,
                      from: .red,
                      to: .blue,
                      durationMs: 2000)

// Turn off the light bar
DS4LightBar.sendOutputReport(device: myDevice,
                             connectionType: .usb,
                             color: .off)

// Set color with rumble simultaneously
DS4LightBar.sendOutputReport(device: myDevice,
                             connectionType: .usb,
                             color: .red,
                             flash: .quickFlash,
                             rumbleRight: 128,
                             rumbleLeft: 200)
```

---

## References

- [Sony DualShock 4 - Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Sony DualShock 4 Data Structures - Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [DualShock 4 - GIMX Wiki](https://gimx.fr/wiki/index.php?title=DualShock_4)
- [DualShock 4 - Eleccelerator Wiki](http://eleccelerator.com/wiki/index.php?title=DualShock_4)
- [DS4-USB - PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-USB)
- [DS4-BT - PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-BT)
- [DS4Windows Source Code (Ryochan7)](https://github.com/Ryochan7/DS4Windows) - `DS4LightBar.cs`, `DS4Device.cs`
- [ds4drv (chrippa)](https://github.com/chrippa/ds4drv) - `device.py`, `actions/led.py`, `actions/battery.py`
