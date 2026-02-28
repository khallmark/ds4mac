# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build (requires Xcode for IOKit headers)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

# Run all 122 tests (no hardware needed)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Run a single test class
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DS4InputReportParserTests

# Run a single test method
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DS4InputReportParserTests/testParseSticksCentered

# Run CLI tool (requires connected DS4 controller)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build && .build/debug/DS4Tool info --json
```

The `DEVELOPER_DIR` prefix is required because the CommandLineTools SDK version mismatches the Swift compiler. Without it, builds fail with "failed to build module 'Foundation'".

## Architecture

Two targets with a strict dependency boundary:

- **DS4Protocol** (`Sources/DS4Protocol/`) — Pure Swift library. Zero platform dependencies (no IOKit, no Foundation beyond Codable). Fully testable without hardware. This is where all protocol parsing, report construction, CRC, and calibration logic lives.
- **DS4Tool** (`Sources/DS4Tool/`) — macOS CLI tool. Depends on DS4Protocol + IOKit. Thin wrapper: device discovery via `IOHIDManager`, input report polling, output report sending, and argument dispatch.

Data flow: `IOHIDManager callback → raw [UInt8] → DS4InputReportParser.parse() → DS4InputState (Codable) → JSON/display`

### USB vs Bluetooth differences

The parser uses offset-based shared logic (`parseControllerState(_:dataOffset:)`) to handle both transports:
- **USB**: 64-byte report, Report ID 0x01, data starts at offset 1, no CRC
- **Bluetooth**: 78-byte report, Report ID 0x11, data starts at offset 3 (2 extra BT flag bytes), CRC-32 in last 4 bytes
- **BT mode switch**: Reading Feature Report 0x02 triggers the controller to switch from reduced 10-byte reports to full 78-byte extended reports
- **Calibration layout**: USB interleaves plus/minus per axis; BT groups all plus first, then all minus

## Protocol Gotchas

These are non-obvious behaviors documented in code that cause bugs if forgotten:

- **Touchpad active bit is inverted**: bit 7 = 0 means touching, 1 means not touching (`DS4InputReportParser.parseTouchFinger`)
- **Motor byte ordering**: right/weak motor comes before left/strong motor in the report — opposite of the `DS4OutputState` field naming (`DS4OutputReportBuilder`)
- **IOKit report ID inclusion varies**: The callback buffer may or may not include the report ID byte depending on macOS version. Detection logic is in `hidInputReportCallback` — check `buffer[0] == reportID && length == expectedFullSize`
- **CRC-32 seed bytes differ by direction**: 0xA1 for input reports, 0xA2 for output reports (`DS4CRCPrefix`)
- **Touch coordinates are 12-bit split across 3 bytes**: `x = byte1 | (byte2 & 0x0F) << 8`, `y = (byte2 >> 4) | (byte3 << 4)`

## Coding Conventions

- All DS4Protocol types are `Codable + Equatable + Sendable`
- Parsers and builders are `enum` types with static methods (no instance state)
- Error types use associated values for context: `ParseError.invalidLength(expected:, got:)`
- Source comments reference specific protocol doc sections (e.g., "docs/04-DS4-USB-Protocol.md Section 2.1")
- Constants live in `DS4Constants.swift` — never use magic numbers for VIDs, PIDs, report IDs, or sizes
- IOKit buffer pointers that outlive a closure must use `UnsafeMutablePointer.allocate()`, not `Array.withUnsafeMutableBufferPointer`

## Testing Patterns

- Test helpers in `TestHelpers.swift` build synthetic reports: `makeUSBReport(...)`, `makeBTReport(...)`, `makeTouchFingerBytes(...)`
- `makeBTReport` automatically computes and appends a valid CRC-32
- All tests use `@testable import DS4Protocol` for internal access
- Tests are pure Swift — no hardware, no IOKit, no external dependencies
- Binary fixtures from real hardware captured via `DS4Tool capture` are stored in `Tests/DS4ProtocolTests/Fixtures/`

## Reference Documentation

`docs/` contains 12 protocol specification documents (~17,500 lines total). Key references:
- `04-DS4-USB-Protocol.md` — USB report byte maps (Section 2.1 for input, Section 3 for output)
- `05-DS4-Bluetooth-Protocol.md` — BT differences, CRC-32 (Section 8), mode switching (Section 3.2)
- `08-Gyroscope-IMU-Feature.md` — IMU calibration formulas
- `DS4/` directory contains a legacy KEXT driver (deprecated, non-functional on Apple Silicon)
