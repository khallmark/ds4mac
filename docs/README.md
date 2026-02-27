# DS4Mac Documentation

Comprehensive reference documentation for building a DualShock 4 controller driver for macOS.

## Document Index

### Controller & Protocol Reference

| # | Document | Lines | Description |
|---|----------|-------|-------------|
| 01 | [DS4 Controller Overview](01-DS4-Controller-Overview.md) | 869 | Hardware revisions, VID/PIDs, feature matrix, physical specs, macOS compatibility |
| 04 | [DS4 USB Protocol](04-DS4-USB-Protocol.md) | 1,596 | Complete USB HID report format — input 0x01, output 0x05, all feature reports, calibration |
| 05 | [DS4 Bluetooth Protocol](05-DS4-Bluetooth-Protocol.md) | 1,569 | Bluetooth HID protocol — report 0x11, CRC-32, pairing, mode switching, authentication |

### Apple Framework APIs

| # | Document | Lines | Description |
|---|----------|-------|-------------|
| 02 | [Core Bluetooth APIs](02-Core-Bluetooth-APIs.md) | 1,637 | IOBluetooth, CoreBluetooth, ExternalAccessory — framework comparison, L2CAP, HID profile |
| 03 | [USB Driver APIs](03-USB-Driver-APIs.md) | 2,016 | DriverKit, USBDriverKit, IOUSBHost — migration from IOKit KEXTs, complete API reference |

### Feature Guides

| # | Document | Lines | Description |
|---|----------|-------|-------------|
| 06 | [Light Bar Feature](06-Light-Bar-Feature.md) | 1,329 | RGB LED control, flash patterns, battery indicators, color presets, code examples |
| 07 | [Touchpad Feature](07-Touchpad-Feature.md) | 1,484 | Capacitive touchpad — coordinate parsing, gesture recognition, mouse emulation |
| 08 | [Gyroscope/IMU Feature](08-Gyroscope-IMU-Feature.md) | 1,646 | BMI055 6-axis IMU — calibration, sensor fusion (Madgwick), motion controls |
| 09 | [Audio Streaming Feature](09-Audio-Streaming-Feature.md) | 1,116 | Speaker/mic/headphone — SBC codec, BT-only audio, volume control, Core Audio |
| 11 | [Rumble/Haptics Feature](11-Rumble-Haptics-Feature.md) | 1,272 | Dual ERM motors — haptic patterns, Core Haptics integration, game effects |
| 12 | [Battery & Power Management](12-Battery-Power-Management.md) | 1,157 | Battery monitoring, charging detection, power saving, IOPowerManagement |

### Architecture & Design

| # | Document | Lines | Description |
|---|----------|-------|-------------|
| 10 | [macOS Driver Architecture](10-macOS-Driver-Architecture.md) | 1,814 | Hybrid DriverKit + companion app architecture, project structure, migration plan |

### Review Records

| Document | Description |
|----------|-------------|
| [REVIEW-protocol-consistency.md](REVIEW-protocol-consistency.md) | Protocol docs cross-reference audit (13 issues found & fixed) |
| [REVIEW-feature-consistency.md](REVIEW-feature-consistency.md) | Feature docs cross-reference audit (15 issues found & fixed) |
| [REVIEW-api-architecture-consistency.md](REVIEW-api-architecture-consistency.md) | API/architecture docs audit (33 issues found & fixed) |

## Total Documentation

- **12 main documents** — 17,505 lines of technical documentation
- **3 review records** — 1,508 lines of audit findings
- **Grand total** — 19,013 lines across 15 files

## Key Architectural Decisions

1. **DriverKit over IOKit** — The legacy KEXT approach is deprecated; modern macOS requires DriverKit System Extensions
2. **Hybrid architecture** — DriverKit (.dext) handles USB; companion app handles Bluetooth via IOBluetooth.framework (DriverKit cannot access IOBluetooth)
3. **IOUserHIDDevice** — Subclass `IOUserHIDDevice` (HIDDriverKit) for automatic GameController framework integration
4. **Audio is Bluetooth-only** — The DS4 has no USB audio endpoints; speaker/mic require Bluetooth HID reports with SBC encoding

## Sources Compiled

### Apple Developer Documentation
- CoreBluetooth, IOBluetooth, IOBluetoothUI, ExternalAccessory
- USBDriverKit, IOUSBHost, DriverKit
- AccessorySetupKit, GameController

### Reverse Engineering References
- [controllers.fandom.com — Sony DualShock 4](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [controllers.fandom.com — DS4 Data Structures](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [psdevwiki.com — DS4-USB](https://www.psdevwiki.com/ps4/DS4-USB)
- [pcgamingwiki.com — DualShock 4](https://www.pcgamingwiki.com/wiki/Controller:DualShock_4)
- [wiki.gentoo.org — Sony DualShock](https://wiki.gentoo.org/wiki/Sony_DualShock#DualShock_4)

### Example Code Analyzed
- **DS4Windows** (C#) — Best Windows DS4 implementation
- **ds4drv-chrippa** (Python) — Linux DS4 driver
- **ds4drv-clearpathrobotics** (Python) — Fork with 54 additional commits
- **DS4AudioStreamer** — Audio streaming reference implementation
