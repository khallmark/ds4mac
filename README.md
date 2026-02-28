# DS4Mac

DualShock 4 controller tools for macOS — a modern Swift Package providing protocol parsing and a CLI tool for real-time controller interaction.

## Features

- **Full input parsing** — analog sticks, 14 buttons, d-pad, analog triggers, capacitive touchpad (2-finger), 6-axis IMU (gyro + accelerometer), battery status
- **Output control** — light bar RGB color, rumble motors (heavy + light), flash timing
- **Dual transport** — USB and Bluetooth support with auto-detection
- **JSON output** — all commands support `--json` for machine-readable output
- **Raw capture** — save binary HID reports as test fixtures
- **CRC-32 validation** — Bluetooth report integrity checking
- **IMU calibration** — gyroscope and accelerometer calibration data parsing
- **122 unit tests** — comprehensive protocol coverage, no hardware required to test

## Requirements

- macOS 14.0+
- Swift 5.9+
- Xcode (for IOKit SDK headers)

## Quick Start

```bash
# Build
swift build

# Connect a DualShock 4 via USB or Bluetooth, then:
.build/debug/DS4Tool info

# Stream live controller input
.build/debug/DS4Tool monitor --json --timeout 10
```

> **Note:** If you encounter SDK errors, prefix commands with:
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

## Commands

### `info` — Device Discovery

```bash
DS4Tool info --json
```
```json
{
  "connectionType": "usb",
  "manufacturer": "Sony Computer Entertainment",
  "product": "Wireless Controller",
  "productID": 1476,
  "transport": "USB",
  "vendorID": 1356,
  "versionNumber": 256
}
```

### `monitor` — Live Input Streaming

```bash
# JSON mode (one object per line, every report)
DS4Tool monitor --json --timeout 5

# Human-readable mode (live terminal display, ~10 Hz)
DS4Tool monitor --timeout 10
```

Parses and displays: stick positions, button states, trigger values, d-pad direction, IMU readings, touchpad coordinates, and battery level.

### `led` — Light Bar Control

```bash
# Set light bar to red
DS4Tool led 255 0 0

# Set to blue with JSON confirmation
DS4Tool led 0 0 255 --json
```

### `rumble` — Rumble Motors

```bash
# Heavy motor at 50%, light motor at 25% (runs for 2 seconds)
DS4Tool rumble 128 64 --json
```

### `capture` — Save Raw Reports

```bash
# Capture 10 binary HID reports to a directory
DS4Tool capture 10 --output ./fixtures --json
```

Saves raw `.bin` files that can be used as test fixtures.

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--json` | Machine-readable JSON output | Off |
| `--timeout <s>` | Duration for monitor (seconds) | 10 |
| `--output <dir>` | Output directory for capture | `.` |
| `--help` | Show usage information | — |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | No controller found |
| 2 | Connection error |
| 3 | Parse error |

## Project Structure

```
Package.swift
Sources/
  DS4Protocol/                      # Pure Swift library (no IOKit dependency)
    DS4Constants.swift              #   VID/PID, report IDs, sizes, feature flags
    DS4Types.swift                  #   Data model types (Codable + Equatable + Sendable)
    DS4InputReportParser.swift      #   USB + Bluetooth input report parsing
    DS4OutputReportBuilder.swift    #   USB + Bluetooth output report construction
    DS4CRC32.swift                  #   CRC-32 for Bluetooth report validation
    DS4CalibrationData.swift        #   IMU calibration from feature report 0x02
  DS4Tool/                          # CLI tool (requires IOKit)
    main.swift                      #   Entry point, arg parsing, command dispatch
    DS4HIDManager.swift             #   IOHIDManager wrapper for device I/O
Tests/
  DS4ProtocolTests/
    DS4ConstantsTests.swift         #   20 tests — constant values, types
    DS4InputReportParserTests.swift #   39 tests — USB/BT parsing, all fields
    DS4OutputReportBuilderTests.swift # 17 tests — output report construction
    DS4CRC32Tests.swift             #   12 tests — CRC validation, round-trips
    DS4CalibrationDataTests.swift   #   34 tests — calibration parsing
    TestHelpers.swift               #   Report construction helpers
    Fixtures/                       #   Binary .bin files from real hardware
docs/                               # 12 protocol specification documents
DS4/                                # Legacy KEXT driver (deprecated)
```

## DS4Protocol Library

The `DS4Protocol` target is a pure Swift library with no IOKit or platform dependencies. It can be used independently in any Swift project to parse or construct DualShock 4 HID reports:

```swift
import DS4Protocol

// Parse a 64-byte USB input report
let state = try DS4InputReportParser.parseUSB(reportBytes)
print(state.leftStick.x)       // 0-255
print(state.buttons.cross)     // true/false
print(state.imu.accelY)        // ~8192 at rest (1g)

// Build an output report to set LED color
let output = DS4OutputState(ledRed: 255, ledGreen: 0, ledBlue: 128)
let report = DS4OutputReportBuilder.buildUSB(output)
```

## Testing

```bash
swift test
```

Runs 122 tests across 5 test suites. All tests are pure-Swift and require no connected hardware.

## Documentation

The `docs/` directory contains 12 comprehensive protocol specification documents covering the DS4's USB protocol, Bluetooth protocol, light bar, touchpad, gyroscope/IMU, audio streaming, rumble/haptics, battery management, and macOS driver architecture.

## Legacy Driver

The `DS4/` directory contains the original IOKit KEXT driver. This approach is deprecated by Apple and does not function on Apple Silicon Macs. The modern `DS4Tool` CLI replaces it using user-space IOHIDManager APIs.

## Credits

- [360Controller](https://github.com/d235j/360Controller) by d235j
- [DS4Windows](https://github.com/Jays2Kings/DS4Windows) by Jays2Kings
