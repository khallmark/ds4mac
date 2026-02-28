# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build (requires Xcode for IOKit headers)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build

# Run all tests (no hardware needed)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Run a single test class
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DS4InputReportParserTests

# Run a single test method
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DS4InputReportParserTests/testParseSticksCentered

# Run CLI tool (requires connected DS4 controller)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build && .build/debug/DS4Tool info --json

# Run SwiftUI app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build && .build/debug/DS4Mac
```

The `DEVELOPER_DIR` prefix is required because the CommandLineTools SDK version mismatches the Swift compiler. Without it, builds fail with "failed to build module 'Foundation'".

## Architecture

Four targets with a strict dependency graph:

```
DS4Protocol (pure Swift, no platform deps)
    ^
    |
DS4Transport (IOKit, depends on DS4Protocol)
    ^            ^
    |            |
DS4Tool (CLI)   DS4Mac (SwiftUI app)
```

- **DS4Protocol** (`Sources/DS4Protocol/`) — Pure Swift library. Zero platform dependencies (no IOKit, no Foundation beyond Codable). Fully testable without hardware. All protocol parsing, report construction, CRC, and calibration logic.
- **DS4Transport** (`Sources/DS4Transport/`) — Transport abstraction layer. Defines `DS4TransportProtocol` interface with implementations: `DS4USBTransport` (IOKit), `DS4MockTransport` (testing/previews). `DS4TransportManager` is a `@MainActor ObservableObject` that bridges transport events to SwiftUI `@Published` properties with 30 Hz throttling.
- **DS4Tool** (`Sources/DS4Tool/`) — macOS CLI tool. Commands: `info`, `monitor`, `led`, `rumble`, `capture`. Uses `DS4USBTransport` for device communication.
- **DS4Mac** (`Sources/DS4Mac/`) — SwiftUI companion app. Navigation sidebar with Status, Controller visualization, Touchpad visualization, Monitor, Light Bar, Rumble, and Settings views.

Data flow: `IOHIDManager callback → DS4USBTransport → DS4TransportEvent.inputReport([UInt8]) → DS4TransportManager → DS4InputReportParser.parse() → @Published DS4InputState → SwiftUI views`

### Transport Protocol Pattern

`DS4TransportProtocol` is the strategy interface. Key methods: `connect() throws`, `disconnect()`, `startInputReportPolling()`, `sendOutputReport(_:) throws`, `readFeatureReport(reportID:length:)`. Events flow through `onEvent: ((DS4TransportEvent) -> Void)?` callback.

`DS4TransportManager` wraps any transport implementation and throttles 250 Hz input reports to 30 Hz `@Published` updates via a `Timer` + `pendingState` buffer.

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
- **IOKit report ID inclusion varies**: The callback buffer may or may not include the report ID byte depending on macOS version. Detection logic is in `hidUSBInputReportCallback` — check `buffer[0] == reportID && length == expectedFullSize`
- **CRC-32 seed bytes differ by direction**: 0xA1 for input reports, 0xA2 for output reports (`DS4CRCPrefix`)
- **Touch coordinates are 12-bit split across 3 bytes**: `x = byte1 | (byte2 & 0x0F) << 8`, `y = (byte2 >> 4) | (byte3 << 4)`
- **C callback lifetime**: `DS4USBTransport` uses `Unmanaged<DS4USBTransport>.passUnretained(self).toOpaque()` — transport must not be deallocated while callback is registered
- **Hot-plug**: `DS4USBTransport` uses `cleanupDevice()` (keeps IOHIDManager alive for reconnection) vs `cleanupManager()` (full teardown including manager)

## Coding Conventions

- All DS4Protocol types are `Codable + Equatable + Sendable`
- Parsers and builders are `enum` types with static methods (no instance state)
- Error types use associated values for context: `ParseError.invalidLength(expected:, got:)`
- Source comments reference specific protocol doc sections (e.g., "docs/04-DS4-USB-Protocol.md Section 2.1")
- Constants live in `DS4Constants.swift` — never use magic numbers for VIDs, PIDs, report IDs, or sizes
- IOKit buffer pointers that outlive a closure must use `UnsafeMutablePointer.allocate()`, not `Array.withUnsafeMutableBufferPointer`
- SwiftUI views use `@EnvironmentObject var manager: DS4TransportManager`

## Testing Patterns

- **DS4ProtocolTests** (`Tests/DS4ProtocolTests/`): 122 tests for pure protocol logic
  - Test helpers in `TestHelpers.swift` build synthetic reports: `makeUSBReport(...)`, `makeBTReport(...)`, `makeTouchFingerBytes(...)`
  - `makeBTReport` automatically computes and appends a valid CRC-32
  - Binary fixtures from real hardware captured via `DS4Tool capture` are stored in `Fixtures/`
- **DS4TransportTests** (`Tests/DS4TransportTests/`): 22 tests for transport layer
  - `DS4MockTransportTests` — mock transport protocol conformance
  - `DS4TransportManagerTests` — `@MainActor` tests using `await Task.yield()` for async event dispatch
- All tests use `@testable import` for internal access
- Tests are pure Swift — no hardware, no IOKit, no external dependencies

## Reference Documentation

`docs/` contains 12 protocol specification documents (~17,500 lines total). Key references:
- `04-DS4-USB-Protocol.md` — USB report byte maps (Section 2.1 for input, Section 3 for output)
- `05-DS4-Bluetooth-Protocol.md` — BT differences, CRC-32 (Section 8), mode switching (Section 3.2)
- `08-Gyroscope-IMU-Feature.md` — IMU calibration formulas
- `10-macOS-Driver-Architecture.md` — Migration plan (Phase 1 complete, Phase 2 complete, Phase 3 pending)
- `DS4/` directory contains a legacy KEXT driver (deprecated, non-functional on Apple Silicon)
