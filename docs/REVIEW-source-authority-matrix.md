# Source Authority Matrix

Review date: 2026-02-27
Scope: DS4 macOS documentation modernization

## Rule of authority

1. Apple documentation is authoritative for API capability, platform scope, entitlements, and deployment behavior.
2. Example repositories are implementation references for report layout, parser behavior, and practical edge cases.
3. Reverse-engineering sources are corroborative for protocol details not published by Apple.
4. Any unresolved disagreement must be marked "verified vs speculative" in target docs.

## Source Catalog

### Apple API families
- CoreBluetooth
- IOBluetooth
- IOBluetoothUI
- ExternalAccessory
- USBDriverKit
- IOUSBHost
- DriverKit
- HIDDriverKit
- GameController
- SystemExtensions

### Example code repositories
- `Example Code/ds4drv-chrippa`
- `Example Code/ds4drv-clearpathrobotics`
- `Example Code/DS4Windows`
- `Example Code/DS4AudioStreamer`

### Reverse-engineering sources
- controllers.fandom DS4 overview
- controllers.fandom DS4 data structures
- psdevwiki DS4 USB notes
- PCGamingWiki DS4 support matrix
- Gentoo DS4 wiki and forum material

## Document-to-source mapping

| Target doc | Apple authority | Example repos | RE sources | Primary use |
|---|---|---|---|---|
| `01-DS4-Controller-Overview.md` | GameController, DriverKit scope statements | DS4Windows, ds4drv | Fandom, PCGamingWiki | Device identity, variants, capability matrix |
| `02-Core-Bluetooth-APIs.md` | IOBluetooth, IOBluetoothUI, CoreBluetooth, ExternalAccessory | ds4drv, DS4Windows | Gentoo BT usage notes | BT framework applicability and transport model |
| `03-USB-Driver-APIs.md` | DriverKit, USBDriverKit, IOUSBHost, HIDDriverKit | DS4Windows, ds4drv | psdevwiki USB notes | USB stack choices and API decisions |
| `04-DS4-USB-Protocol.md` | N/A (protocol not specified by Apple) | DS4Windows, ds4drv | Fandom, psdevwiki | USB report maps and semantics |
| `05-DS4-Bluetooth-Protocol.md` | N/A (protocol not specified by Apple) | DS4Windows, ds4drv | Fandom, Gentoo | BT report maps, mode switch, CRC |
| `06-Light-Bar-Feature.md` | HID output path context | DS4Windows, ds4drv | Fandom | LED fields, patterns, behavior |
| `07-Touchpad-Feature.md` | HID input path context | DS4Windows, ds4drv | Fandom | Touch data decoding and gestures |
| `08-Gyroscope-IMU-Feature.md` | HID/input timing context | DS4Windows, ds4drv | Fandom | IMU parsing and calibration notes |
| `09-Audio-Streaming-Feature.md` | Core Audio integration boundaries | DS4AudioStreamer, DS4Windows | Fandom, Gentoo | SBC framing and BT audio path |
| `10-macOS-Driver-Architecture.md` | DriverKit, SystemExtensions, IOBluetooth, GameController | DS4Windows architecture patterns | All corroborative | End-to-end macOS architecture |
| `11-Rumble-Haptics-Feature.md` | GameController/Core Haptics scope notes | DS4Windows, ds4drv | Fandom | Motor control semantics and mapping |
| `12-Battery-Power-Management.md` | IOPower/system integration context | DS4Windows, ds4drv | Fandom, Gentoo | Battery status parsing and policy |
| `13-HIDDriverKit-Integration.md` | HIDDriverKit, DriverKit | DS4Windows (logical mapping only) | N/A | HID provider integration path |
| `14-System-Extensions-Framework.md` | SystemExtensions, DriverKit entitlements | N/A | N/A | Activation, approval, deployment |
| `15-GameController-Framework.md` | GameController | N/A | PCGamingWiki (support behavior) | Native gamepad exposure strategy |
| `16-Companion-App-Architecture.md` | IOBluetooth, IOUSBHost, SystemExtensions | DS4Windows service-model inspiration | N/A | App/dext responsibility split |
| `17-Build-Distribution-Guide.md` | Xcode signing/notarization + DriverKit constraints | N/A | N/A | Build, sign, package, distribute |
| `18-Testing-Debugging-Guide.md` | DriverKit diagnostics tooling | All repos for test vectors | Gentoo troubleshooting notes | Validation strategy and diagnostics |
| `19-Migration-Guide.md` | DriverKit migration direction from Apple | Legacy project + DS4Windows as target quality bar | N/A | Old prototype to modern architecture |
| `20-Troubleshooting-Common-Issues.md` | Platform behavior references | All repos | Gentoo + RE behavior notes | Operational issue resolution |

## Known conflict zones to reconcile

- BT report sizing conventions (hidraw vs raw L2CAP perspective).
- Calibration field ordering between USB/BT descriptions.
- BT output control byte semantics (`BT Flags 1`, `BT Flags 2` naming and values).
- Output report examples that disagree on report-ID inclusion conventions.
- API applicability boundaries (CoreBluetooth and ExternalAccessory for DS4).
