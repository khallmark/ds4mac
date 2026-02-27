# USB Driver API Reference for DualShock 4 on macOS

> **Document 03** | DS4Mac Driver Project
> Last updated: 2026-02-27
> Cross-references: [01-DS4-Controller-Overview](./01-DS4-Controller-Overview.md) | [02-Core-Bluetooth-APIs](./02-Core-Bluetooth-APIs.md) | [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | [10-macOS-Driver-Architecture](./10-macOS-Driver-Architecture.md)

---

## Table of Contents

1. [Framework Evolution](#1-framework-evolution)
2. [DriverKit Overview](#2-driverkit-overview)
3. [USBDriverKit Classes](#3-usbdriverkit-classes)
4. [IOUSBHost Framework (App-Level)](#4-iousbhost-framework-app-level)
5. [HID over USB](#5-hid-over-usb)
6. [Device Matching](#6-device-matching)
7. [Data Transfer](#7-data-transfer)
8. [Driver Lifecycle](#8-driver-lifecycle)
9. [Code Examples](#9-code-examples)
10. [Legacy IOKit Reference](#10-legacy-iokit-reference)
11. [Entitlements and Provisioning](#11-entitlements-and-provisioning)
12. [App-Level Alternative](#12-app-level-alternative)

---

## 1. Framework Evolution

### The Migration Path: IOKit KEXTs to DriverKit System Extensions

Apple's driver architecture has undergone a fundamental shift. Understanding this evolution is critical for the DS4Mac project, as the existing codebase is a legacy IOKit KEXT that must be modernized.

```
Timeline:
  2000-2019    IOKit Kernel Extensions (KEXTs)
  ─────────────────────────────────────────────────
  2019         macOS Catalina (10.15) — DriverKit introduced, KEXTs deprecated
  2020         macOS Big Sur (11.0) — KEXTs using deprecated KPIs no longer load by default
  2021         macOS Monterey (12.0) — IOAudioFamily KPIs deprecated
  2022-2024    macOS Ventura/Sonoma — Continued migration, reduced security required for KEXTs
  2024-2025    macOS Sequoia — FSKit added; nearly all driver families have user-space alternatives
  ─────────────────────────────────────────────────
  Future       Full KEXT removal expected
```

### Why DriverKit Is Preferred

| Aspect | IOKit KEXT | DriverKit System Extension |
|--------|-----------|---------------------------|
| **Execution space** | Kernel | User space |
| **Crash impact** | Kernel panic / system crash | Driver process crash only; system unaffected |
| **Security** | Full kernel access; attack surface | Sandboxed; limited privileges |
| **Debugging** | Two-machine debug setup; kernel debugger | Single-machine LLDB attach |
| **Languages** | C, C++ only | C++, and Swift (for companion apps) |
| **Code signing** | Special Kext Signing Certificate | Standard Developer ID + notarization |
| **User installation** | Requires reboot + security approval | Install via app; approve in System Settings |
| **Distribution** | Standalone `.kext` or bundled in app | Embedded in `.app` bundle |
| **Apple Silicon** | Requires Reduced Security boot | Works with Full Security |
| **Future support** | Deprecated; removal imminent | Actively maintained and expanded |

### What This Means for DS4Mac

The existing DS4 driver (`DS4/DS4.cpp`, `DS4/DS4Service.cpp`) is an IOKit KEXT that:
- Subclasses `IOHIDDevice` and `IOService`
- Matches against `IOUSBDevice` by vendor/product ID (Sony `054C` / DS4 `05C4`)
- Provides a custom HID report descriptor
- Runs in the kernel

This driver **will not load on modern macOS** without reduced security and user approval at each boot. It must be migrated to one of:

1. **DriverKit System Extension** (`.dext`) -- Full driver replacement, best for production
2. **IOUSBHost app-level access** -- Good for prototyping, no driver needed
3. **HIDDriverKit** -- If we want to intercept at the HID level specifically

---

## 2. DriverKit Overview

### Architecture

DriverKit provides a user-space driver framework that mirrors IOKit's class hierarchy but executes outside the kernel. The system manages a kernel-side proxy for each user-space driver.

```
┌──────────────────────────────────────────────────────────────────┐
│                         User Space                                │
│                                                                    │
│  ┌─────────────────────┐    ┌─────────────────────────────────┐  │
│  │   DS4Mac.app         │    │   DS4Driver.dext                 │  │
│  │                       │    │                                   │  │
│  │  - Activates dext     │    │  - IOService subclass            │  │
│  │  - IOUSBHost access   │    │  - IOUSBHostInterface provider   │  │
│  │  - UI / Settings      │    │  - IOUSBHostPipe for I/O         │  │
│  │  - IOServiceOpen()    │    │  - OSAction callbacks            │  │
│  │    for UserClient     │    │  - Runs in own process           │  │
│  └──────────┬────────────┘    └──────────────┬────────────────────┘  │
│              │                                 │                      │
├──────────────┼─────────────────────────────────┼──────────────────────┤
│              │           Kernel                 │                      │
│              │                                 │                      │
│  ┌───────────▼─────────────────────────────────▼──────────────────┐  │
│  │                   IOKit Matching & Registry                     │  │
│  │                                                                  │  │
│  │  IOUSBHostDevice (kernel proxy)                                  │  │
│  │    └── IOUSBHostInterface (kernel proxy)                         │  │
│  │          └── Endpoint management                                 │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    USB Host Controller Driver                     │  │
│  │                    (xHCI / EHCI / OHCI)                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                │                                       │
└────────────────────────────────┼───────────────────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   DualShock 4 Hardware   │
                    │   VID: 054C  PID: 09CC   │
                    │   USB Full-Speed (12Mbps) │
                    └─────────────────────────┘
```

### Key Concepts

**IIG Files (`.iig`)**: Interface definition files processed by the IIG tool (analogous to `.idl` files). They define the class interface that bridges user space and kernel, with attributes like `kernel` and `local` controlling where methods execute.

**IMPL Macro**: Used in `.cpp` files to implement methods defined in `.iig` files. The macro enables the inter-process communication between the user-space driver and its kernel proxy.

**DispatchQueue**: Replaces IOKit's `IOWorkLoop`. Every `IOService` has a default dispatch queue. All methods -- including interrupts, timers, and completion callbacks -- are invoked on a queue, providing serialized access to driver state.

**OSAction**: Replaces C function pointer callbacks. Encapsulates an asynchronous callback with compile-time and runtime type checking. Used for all async I/O completions.

### Bundle Structure

```
DS4Mac.app/
  Contents/
    MacOS/
      DS4Mac                          # Main app binary
    Library/
      SystemExtensions/
        com.ds4mac.driver.DS4Driver.dext/      # Driver Extension
          Info.plist                            # Matching & personality
          MacOS/
            com.ds4mac.driver.DS4Driver         # Driver binary
```

Driver Extension bundles (`.dext`) do not have a `Contents/` subdirectory like standard `.app` bundles. Instead, the `Info.plist` sits at the bundle root and the binary resides in a `MacOS/` subdirectory (generated by Xcode). They use `OSBundle` keys in `Info.plist` rather than `CFBundle` keys for library dependencies.

---

## 3. USBDriverKit Classes

USBDriverKit provides the classes for USB device communication within a DriverKit system extension. All classes live in the `USBDriverKit` framework.

### 3.1 IOUSBHostDevice

Represents the USB device itself. This is the top-level provider object for USB drivers.

#### Key Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Open` | `kern_return_t Open(IOService* forClient, IOOptionBits options, uint8_t* arg)` | Open the device for exclusive access |
| `Close` | `kern_return_t Close(IOService* forClient, IOOptionBits options)` | Release exclusive access |
| `CopyDeviceDescriptor` | `const IOUSBDeviceDescriptor* CopyDeviceDescriptor()` | Get the USB device descriptor (VID, PID, class, etc.) |
| `CopyConfigurationDescriptor` | `const IOUSBConfigurationDescriptor* CopyConfigurationDescriptor()` | Get the active configuration descriptor |
| `CopyConfigurationDescriptorWithValue` | `const IOUSBConfigurationDescriptor* CopyConfigurationDescriptorWithValue(uint8_t configValue)` | Get a specific configuration descriptor |
| `CopyCapabilityDescriptors` | `const IOUSBBOSDescriptor* CopyCapabilityDescriptors()` | Get BOS capability descriptors |
| `CopyDescriptor` | `kern_return_t CopyDescriptor(uint8_t type, uint8_t index, uint16_t languageID, uint8_t requestType, IOMemoryDescriptor** descriptor, uint16_t length)` | Copy an arbitrary descriptor |
| `CopyStringDescriptor` | `const IOUSBStringDescriptor* CopyStringDescriptor(uint8_t index, uint16_t languageID)` | Get a string descriptor |
| `CopyInterface` | `kern_return_t CopyInterface(IOUSBHostInterface** interface)` | Get a specific interface object |
| `SetConfiguration` | `kern_return_t SetConfiguration(uint8_t configValue)` | Set the device configuration |
| `GetAddress` | `kern_return_t GetAddress(uint8_t* address)` | Get the USB device address |
| `GetSpeed` | `kern_return_t GetSpeed(uint8_t* speed)` | Get connection speed (Full/High/Super) |
| `GetFrameNumber` | `kern_return_t GetFrameNumber(uint64_t* frameNumber, uint64_t* timeStamp)` | Get the current USB frame number |
| `GetPortStatus` | `kern_return_t GetPortStatus(uint32_t* portStatus)` | Get port status flags |
| `DeviceRequest` | `kern_return_t DeviceRequest(IOService* forClient, uint8_t requestType, uint8_t request, uint16_t value, uint16_t index, uint16_t length, IOMemoryDescriptor* data, uint16_t* bytesTransferred)` | Synchronous control transfer |
| `AsyncDeviceRequest` | `kern_return_t AsyncDeviceRequest(IOService* forClient, uint8_t requestType, uint8_t request, uint16_t value, uint16_t index, uint16_t length, IOMemoryDescriptor* data, OSAction* completion)` | Asynchronous control transfer |
| `AbortDeviceRequests` | `kern_return_t AbortDeviceRequests(OSAction* action, IOOptionBits options)` | Abort pending device requests |
| `CreateIOBuffer` | `kern_return_t CreateIOBuffer(IOOptionBits options, uint64_t capacity, IOBufferMemoryDescriptor** buffer)` | Allocate a DMA-capable buffer |
| `CreateInterfaceIterator` | `kern_return_t CreateInterfaceIterator(IOUSBFindInterfaceRequest* request, io_iterator_t* iterator)` | Create iterator to enumerate interfaces |
| `DestroyInterfaceIterator` | `kern_return_t DestroyInterfaceIterator(io_iterator_t iterator)` | Destroy the interface iterator |
| `Reset` | `kern_return_t Reset()` | Reset the USB device |

### 3.2 IOUSBHostInterface

Manages a single USB interface. For the DS4, this is the HID interface (Interface 0). This is typically the **provider** object your driver matches against.

#### Key Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Open` | `kern_return_t Open(IOService* forClient, IOOptionBits options, uint8_t* arg)` | Open the interface for exclusive access |
| `Close` | `kern_return_t Close(IOService* forClient, IOOptionBits options)` | Release the interface |
| `CopyPipe` | `kern_return_t CopyPipe(uint8_t address, IOUSBHostPipe** pipe)` | Get the pipe for the given endpoint address |
| `SelectAlternateSetting` | `kern_return_t SelectAlternateSetting(uint8_t alternateSettingIndex)` | Switch to an alternate interface setting |
| `GetFrameNumber` | `kern_return_t GetFrameNumber(uint64_t* frameNumber, uint64_t* timeStamp)` | Get current USB frame number |
| `CreateIOBuffer` | `kern_return_t CreateIOBuffer(IOOptionBits options, uint64_t capacity, IOBufferMemoryDescriptor** buffer)` | Allocate a DMA-capable I/O buffer |
| `DeviceRequest` | `kern_return_t DeviceRequest(...)` | Send a control transfer through this interface |
| `AsyncDeviceRequest` | `kern_return_t AsyncDeviceRequest(...)` | Asynchronous control transfer through this interface |
| `AbortDeviceRequests` | `kern_return_t AbortDeviceRequests(...)` | Abort pending requests |

**DS4-Specific Usage**: Open Interface 0, then call `CopyPipe` with endpoint addresses `0x84` (Interrupt IN) and `0x03` (Interrupt OUT) to get the input and output pipes.

### 3.3 IOUSBHostPipe

Represents a USB endpoint (pipe). Used for all data transfers -- bulk, interrupt, and isochronous.

#### Key Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `IO` | `kern_return_t IO(IOMemoryDescriptor* data, uint32_t length, OSAction* completion, uint32_t completionTimeoutMs)` | Synchronous I/O on bulk or interrupt endpoint |
| `AsyncIO` | `kern_return_t AsyncIO(IOMemoryDescriptor* data, uint32_t length, OSAction* completion, uint32_t completionTimeoutMs)` | Asynchronous I/O on bulk or interrupt endpoint |
| `AsyncIOBundled` | `kern_return_t AsyncIOBundled(...)` | Bundled async I/O for efficiency |
| `IsochIO` | `kern_return_t IsochIO(IOMemoryDescriptor* data, IOUSBIsochronousFrame* frameList, uint32_t frameListCount, uint64_t firstFrameNumber)` | Isochronous I/O transfer |
| `Abort` | `kern_return_t Abort(IOOptionBits options)` | Abort pending I/O on this pipe |
| `ClearStall` | `kern_return_t ClearStall(bool withRequest)` | Clear a stall condition on the endpoint |
| `AdjustPipe` | `kern_return_t AdjustPipe(...)` | Modify pipe policy (max packet size, interval) |
| `GetDescriptors` | `kern_return_t GetDescriptors(IOUSBStandardEndpointDescriptors* descriptors)` | Get endpoint descriptors for this pipe |
| `GetDeviceAddress` | `kern_return_t GetDeviceAddress(uint8_t* address)` | Get parent device address |
| `GetSpeed` | `kern_return_t GetSpeed(uint8_t* speed)` | Get connection speed |
| `GetIdlePolicy` | `kern_return_t GetIdlePolicy(uint32_t* idleTimeoutMs)` | Get idle timeout policy |
| `SetIdlePolicy` | `kern_return_t SetIdlePolicy(uint32_t idleTimeoutMs)` | Set idle timeout policy |
| `CreateMemoryDescriptorRing` | `kern_return_t CreateMemoryDescriptorRing(uint32_t count)` | Create a ring buffer for I/O |
| `SetMemoryDescriptor` | `kern_return_t SetMemoryDescriptor(uint32_t index, IOMemoryDescriptor* descriptor)` | Set a descriptor in the ring |

#### Completion Callback

The async I/O completion callback has this signature:

```cpp
virtual void ReadComplete(
    OSAction*   action,
    IOReturn    status,
    uint32_t    actualByteCount,
    uint64_t    completionTimestamp
) TYPE(IOUSBHostPipe::CompleteAsyncIO);
```

### 3.4 Descriptor Helper Functions

USBDriverKit provides free functions for parsing USB descriptors:

| Function | Description |
|----------|-------------|
| `IOUSBGetEndpointAddress(descriptor)` | Extract endpoint address from descriptor |
| `IOUSBGetEndpointDirection(descriptor)` | Get endpoint direction (IN/OUT) |
| `IOUSBGetEndpointNumber(descriptor)` | Get endpoint number |
| `IOUSBGetEndpointType(descriptor)` | Get transfer type (Control/Bulk/Interrupt/Isoch) |
| `IOUSBGetEndpointMaxPacketSize(descriptor)` | Get max packet size |
| `IOUSBGetNextDescriptor(configDesc, current)` | Iterate to next descriptor |
| `IOUSBGetNextEndpointDescriptor(configDesc, ifDesc, current)` | Find next endpoint in interface |
| `IOUSBGetNextInterfaceDescriptor(configDesc, current)` | Find next interface descriptor |
| `IOUSBGetConfigurationMaxPowerMilliAmps(configDesc)` | Get max power draw |
| `IOUSBHostFreeDescriptor(descriptor)` | Free a copied descriptor |

### 3.5 Enumerations

**Connection Speed** (`IOUSBHostConnectionSpeed`):
- `kIOUSBHostConnectionSpeedNone`
- `kIOUSBHostConnectionSpeedFull` (12 Mbps) -- DS4 operates at this speed
- `kIOUSBHostConnectionSpeedLow` (1.5 Mbps)
- `kIOUSBHostConnectionSpeedHigh` (480 Mbps)
- `kIOUSBHostConnectionSpeedSuper` (5 Gbps)
- `kIOUSBHostConnectionSpeedSuperPlus` (10 Gbps)
- `kIOUSBHostConnectionSpeedSuperPlusby2` (20 Gbps)

**Port Status** (`IOUSBHostPortStatus`):
- `kIOUSBHostPortStatusConnected`
- `kIOUSBHostPortStatusEnabled`
- `kIOUSBHostPortStatusSuspended`
- `kIOUSBHostPortStatusOvercurrent`

**Abort Options** (`IOUSBHostAbortOptions`):
- `kIOUSBHostAbortOptionSynchronous`
- `kIOUSBHostAbortOptionAsynchronous`

---

## 4. IOUSBHost Framework (App-Level)

The `IOUSBHost` framework (not to be confused with USBDriverKit) provides **app-level** access to USB devices from user space without writing a driver. Available since macOS 10.15.

### Overview

```
Framework:    IOUSBHost.framework
Import:       import IOUSBHost       // Swift
              #import <IOUSBHost/IOUSBHost.h>  // Objective-C
Availability: macOS 10.15+
Entitlement:  com.apple.security.device.usb (for sandboxed apps)
```

### Classes

#### IOUSBHostDevice (App Framework)

```swift
class IOUSBHostDevice : IOUSBHostObject {
    // Discovery
    class func matching(vendorID: Int, productID: Int) -> [String: Any]
    class func matching(vendorID: Int, productID: Int,
                        bcdDevice: Int, deviceClass: Int,
                        deviceSubclass: Int, deviceProtocol: Int) -> [String: Any]

    // Device Information
    var deviceDescriptor: IOUSBDeviceDescriptor { get }
    var configurationDescriptor: IOUSBConfigurationDescriptor { get }
    func configurationDescriptor(with value: UInt8) -> IOUSBConfigurationDescriptor
    func stringDescriptor(at index: UInt8) -> String?

    // Interface Access
    func copyInterface(with request: IOUSBFindInterfaceRequest) -> IOUSBHostInterface?
}
```

#### IOUSBHostInterface (App Framework)

```swift
class IOUSBHostInterface : IOUSBHostObject {
    // Pipe Access
    func copyPipe(withAddress address: UInt8) -> IOUSBHostPipe?

    // Interface Control
    func selectAlternateSetting(_ setting: UInt8)

    // Descriptors
    var interfaceDescriptor: IOUSBInterfaceDescriptor { get }
}
```

#### IOUSBHostPipe (App Framework)

```swift
class IOUSBHostPipe : NSObject {
    // Synchronous I/O
    func sendIORequest(with data: NSMutableData) -> Int

    // Asynchronous I/O
    func enqueueIORequest(with data: NSMutableData,
                          completionHandler: @escaping (IOReturn, Int) -> Void)

    // Pipe Management
    func abort()
    func clearStall()

    // Properties
    var endpointDescriptor: IOUSBEndpointDescriptor { get }
}
```

### When to Use IOUSBHost vs DriverKit

| Consideration | IOUSBHost (App) | USBDriverKit (Dext) |
|--------------|----------------|---------------------|
| Complexity | Lower | Higher |
| System integration | App must be running | OS-managed lifecycle |
| Multi-app access | Single app exclusive | System-wide |
| Auto-launch on connect | No | Yes |
| HID report interception | Limited | Full |
| Prototyping speed | Fast | Slow |
| Production ready | For utilities | For drivers |

**Recommendation for DS4Mac**: Start with IOUSBHost in the companion app for rapid prototyping and validation. Then implement the DriverKit `.dext` for production.

---

## 5. HID over USB

### USB HID Protocol Basics

The DualShock 4 is a USB HID (Human Interface Device) class device. Understanding the HID protocol is essential for communication.

```
USB HID Device Class:
  bInterfaceClass:    0x03 (HID)
  bInterfaceSubClass: 0x00 (No Boot Interface)
  bInterfaceProtocol: 0x00 (None)
```

### Endpoint Architecture

```
DualShock 4 USB Endpoints:
┌─────────────────────────────────────────────────────────────┐
│ Endpoint 0 (Control)     - Default control pipe             │
│   Direction: Bidirectional                                   │
│   Transfer: Control                                          │
│   Usage: Feature reports (GET_REPORT / SET_REPORT)           │
│          Device configuration                                │
│                                                              │
│ Endpoint 0x84 (Interrupt IN)  - Input reports               │
│   Direction: Device → Host                                   │
│   Transfer: Interrupt                                        │
│   Max Packet: 64 bytes                                       │
│   Interval: Variable (USB polls at defined interval)         │
│   Usage: Controller state (buttons, sticks, IMU, touchpad)   │
│                                                              │
│ Endpoint 0x03 (Interrupt OUT) - Output reports              │
│   Direction: Host → Device                                   │
│   Transfer: Interrupt                                        │
│   Max Packet: 64 bytes                                       │
│   Usage: LED color, rumble, flash timing                     │
└─────────────────────────────────────────────────────────────┘
```

### HID Report Types

| Type | Direction | Pipe | DS4 Usage |
|------|-----------|------|-----------|
| **Input Report** | Device to Host | Interrupt IN | Button states, analog sticks, IMU, touchpad, battery |
| **Output Report** | Host to Device | Interrupt OUT | LED color, rumble motors, flash timing |
| **Feature Report** | Bidirectional | Control (EP0) | Calibration data, MAC address, firmware info |

### DS4 Report IDs

**Input Reports:**

| Report ID | Size (USB) | Description |
|-----------|-----------|-------------|
| `0x01` | 64 bytes | Standard input report (buttons, sticks, IMU, touchpad) |

**Output Reports:**

| Report ID | Size (USB) | Description |
|-----------|-----------|-------------|
| `0x05` | 32 bytes | LED + Rumble control |

**Feature Reports (via Control Endpoint):**

| Report ID | Size | Direction | Description |
|-----------|------|-----------|-------------|
| `0x02` | 37 bytes | GET | Calibration / mode data |
| `0x04` | 37 bytes | GET | Calibration data |
| `0x08` | 4 bytes | GET | Unknown |
| `0x10` | 5 bytes | GET | Unknown |
| `0x11` | 3 bytes | GET | Unknown |
| `0x12` | 16 bytes | GET | Device pairing info |
| `0x81` | 7 bytes | GET | MAC address |
| `0xA3` | 49 bytes | GET | Firmware version / date |

### USB Input Report Structure (Report ID 0x01, 64 bytes)

```
Offset  Size  Field
──────  ────  ─────
  0     1     Report ID (0x01)
  1     1     Left Stick X (0x00 = left, 0xFF = right)
  2     1     Left Stick Y (0x00 = up, 0xFF = down)
  3     1     Right Stick X
  4     1     Right Stick Y
  5     1     D-Pad + Face Buttons
                Bits 0-3: D-Pad (0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=released)
                Bit 4: Square
                Bit 5: Cross
                Bit 6: Circle
                Bit 7: Triangle
  6     1     Buttons
                Bit 0: L1
                Bit 1: R1
                Bit 2: L2 (digital)
                Bit 3: R2 (digital)
                Bit 4: Share
                Bit 5: Options
                Bit 6: L3
                Bit 7: R3
  7     1     PS + Touchpad + Counter
                Bit 0: PS Button
                Bit 1: Touchpad Click
                Bits 2-7: Counter
  8     1     L2 Trigger (analog, 0x00-0xFF)
  9     1     R2 Trigger (analog, 0x00-0xFF)
 10-11  2     Timestamp (5.33us units)
 12     1     Temperature
 13-14  2     Gyroscope Pitch (signed 16-bit LE)
 15-16  2     Gyroscope Yaw (signed 16-bit LE)
 17-18  2     Gyroscope Roll (signed 16-bit LE)
 19-20  2     Accelerometer X (signed 16-bit LE)
 21-22  2     Accelerometer Y (signed 16-bit LE)
 23-24  2     Accelerometer Z (signed 16-bit LE)
 25-29  5     External device / headphone status
 30     1     Battery + Connection
                Bits 0-3: Battery level (0-8 no USB, 0-11 with USB)
                Bit 4: USB connected
                Bit 5: Headphones
                Bit 6: Microphone
 31-32  2     Reserved
 33     1     Touch data count
 34     1     Touch Packet 0: Finger 0 ID + active
 35-37  3     Touch Packet 0: Finger 0 X,Y (12-bit each)
 38     1     Touch Packet 0: Finger 1 ID + active
 39-41  3     Touch Packet 0: Finger 1 X,Y
 42-63  22    Additional touch packets + padding
```

### USB Output Report Structure (Report ID 0x05, 32 bytes)

```
Offset  Size  Field
──────  ────  ─────
  0     1     Report ID (0x05)
  1     1     Flags / enable bits
                Bit 0: Enable rumble update
                Bit 1: Enable LED update
                Bit 2: Enable LED blink
  2     1     Reserved (0x00)
  3     1     Right Motor (weak/fast rumble, 0x00-0xFF)
  4     1     Left Motor (strong/slow rumble, 0x00-0xFF)
  5     1     LED Red (0x00-0xFF)
  6     1     LED Green (0x00-0xFF)
  7     1     LED Blue (0x00-0xFF)
  8     1     Flash On Duration (0xFF = 2.5 seconds)
  9     1     Flash Off Duration (0xFF = 2.5 seconds)
 10-31  22    Audio volume controls + padding
```

### HID Report Descriptor

The DS4's HID report descriptor (from `DS4/dualshock4hid.h`) defines:

| Usage | HID Usage Page | Report ID | Direction |
|-------|---------------|-----------|-----------|
| Game Pad | Generic Desktop (0x01) | 0x01 | Input |
| Analog Sticks | Generic Desktop: X, Y, Z, Rz | 0x01 | Input |
| Hat Switch | Generic Desktop (0x01) | 0x01 | Input |
| 14 Buttons | Button Page (0x09) | 0x01 | Input |
| Triggers | Generic Desktop: Rx, Ry | 0x01 | Input |
| Extended Data | Vendor (0xFF00) | 0x01 | Input |
| LED/Rumble | Vendor (0xFF00) | 0x05 | Output |
| Feature Reports | Vendor (0xFF00, 0xFF02, 0xFF05, 0xFF80) | Various | Feature |

---

## 6. Device Matching

### DS4 USB Device Identifiers

```
DualShock 4 V1 (CUH-ZCT1x):
  Vendor ID:   0x054C  (Sony Corp.)     = 1356 decimal
  Product ID:  0x05C4  (DS4 V1)         = 1476 decimal

DualShock 4 V2 (CUH-ZCT2x):
  Vendor ID:   0x054C  (Sony Corp.)     = 1356 decimal
  Product ID:  0x09CC  (DS4 V2)         = 2508 decimal

Sony Wireless Adapter:
  Vendor ID:   0x054C  (Sony Corp.)     = 1356 decimal
  Product ID:  0x0BA0  (Wireless Adapter) = 2976 decimal
```

### DriverKit Matching Dictionary (Info.plist)

```xml
<key>IOKitPersonalities</key>
<dict>
    <!-- DualShock 4 V1 -->
    <key>DS4v1</key>
    <dict>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>IOClass</key>
        <string>AppleUserUSBHostHIDDevice</string>
        <key>IOProviderClass</key>
        <string>IOUSBHostInterface</string>
        <key>IOUserClass</key>
        <string>DS4Driver</string>
        <key>IOUserServerName</key>
        <string>com.ds4mac.driver.DS4Driver</string>
        <key>idVendor</key>
        <integer>1356</integer>
        <key>idProduct</key>
        <integer>1476</integer>
        <key>bInterfaceClass</key>
        <integer>3</integer>
        <key>bInterfaceSubClass</key>
        <integer>0</integer>
        <key>bInterfaceProtocol</key>
        <integer>0</integer>
    </dict>

    <!-- DualShock 4 V2 -->
    <key>DS4v2</key>
    <dict>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>IOClass</key>
        <string>AppleUserUSBHostHIDDevice</string>
        <key>IOProviderClass</key>
        <string>IOUSBHostInterface</string>
        <key>IOUserClass</key>
        <string>DS4Driver</string>
        <key>IOUserServerName</key>
        <string>com.ds4mac.driver.DS4Driver</string>
        <key>idVendor</key>
        <integer>1356</integer>
        <key>idProduct</key>
        <integer>2508</integer>
        <key>bInterfaceClass</key>
        <integer>3</integer>
        <key>bInterfaceSubClass</key>
        <integer>0</integer>
        <key>bInterfaceProtocol</key>
        <integer>0</integer>
    </dict>
</dict>
```

### Key Differences from Legacy IOKit Matching

| Aspect | Legacy KEXT (existing DS4 code) | DriverKit |
|--------|--------------------------------|-----------|
| `IOProviderClass` | `IOUSBDevice` | `IOUSBHostInterface` |
| `IOClass` | `SonyPlaystationDualShock4` (driver class) | `AppleUserUSBHostHIDDevice` |
| `IOUserClass` | N/A | Your driver class name |
| `IOUserServerName` | N/A | Bundle identifier of the dext |
| VID/PID keys | `idVendor`, `idProduct` | Same, but often combined with interface class |
| Match level | Device level | Interface level (more specific) |

### Matching Hierarchy

DriverKit matching works in multiple phases:

```
Phase 1: Class Matching
  └── IOProviderClass must match the nub type in the IORegistry
      (IOUSBHostDevice for device-level, IOUSBHostInterface for interface-level)

Phase 2: Passive Matching (dictionary keys)
  └── idVendor, idProduct, bInterfaceClass, etc. compared to device nub

Phase 3: Probe Score
  └── Higher score wins if multiple drivers match
      Default score: 0
      Each matching key adds to score

Phase 4: Start
  └── Winning driver's Start() is called
```

---

## 7. Data Transfer

### Control Transfers (Feature Reports)

Control transfers use Endpoint 0 (the default control pipe) and are used for:
- Getting/setting HID feature reports
- Reading calibration data
- Reading the DS4's Bluetooth MAC address
- USB standard requests (Get Descriptor, Set Configuration, etc.)

**DriverKit (Synchronous):**

```cpp
// GET_REPORT: Read feature report 0x81 (MAC address)
uint8_t reportId = 0x81;
uint16_t reportLength = 7;

// bmRequestType: Device-to-host, Class, Interface
uint8_t requestType = 0xA1;  // USB_DIR_IN | USB_TYPE_CLASS | USB_RECIP_INTERFACE
uint8_t request = 0x01;       // HID_GET_REPORT
uint16_t value = (0x03 << 8) | reportId;  // Feature report type (3) + report ID
uint16_t index = 0;           // Interface number

uint16_t bytesTransferred = 0;
kern_return_t ret = ivars->interface->DeviceRequest(
    this,           // forClient
    requestType,    // bmRequestType
    request,        // bRequest
    value,          // wValue
    index,          // wIndex
    reportLength,   // wLength
    ivars->buffer,  // data (IOMemoryDescriptor)
    &bytesTransferred
);
```

**SET_REPORT: Write output report 0x05 (LED + Rumble):**

```cpp
uint8_t requestType = 0x21;  // USB_DIR_OUT | USB_TYPE_CLASS | USB_RECIP_INTERFACE
uint8_t request = 0x09;       // HID_SET_REPORT
uint16_t value = (0x02 << 8) | 0x05;  // Output report type (2) + report ID 5
uint16_t index = 0;
uint16_t length = 32;

kern_return_t ret = ivars->interface->DeviceRequest(
    this, requestType, request, value, index, length,
    ivars->outputBuffer, &bytesTransferred
);
```

### Interrupt Transfers (Input/Output Reports)

Interrupt transfers are the primary data path for real-time controller input and output.

**Reading Input Reports (Async):**

```cpp
// Enqueue an asynchronous read on the Interrupt IN pipe
kern_return_t ret = ivars->inPipe->AsyncIO(
    ivars->inBuffer,         // IOMemoryDescriptor with allocated buffer
    64,                       // Max bytes to read (DS4 USB report = 64 bytes)
    ivars->readCompleteAction, // OSAction for completion callback
    0                          // Timeout (0 = no timeout)
);
```

**Completion callback re-enqueues the next read:**

```cpp
void DS4Driver::ReadComplete(OSAction* action, IOReturn status,
                             uint32_t actualByteCount,
                             uint64_t completionTimestamp)
{
    if (status == kIOReturnSuccess && actualByteCount > 0) {
        // Process the input report
        ProcessInputReport(ivars->inBuffer, actualByteCount);
    }

    // Re-enqueue the next read (continuous polling)
    if (status != kIOReturnAborted) {
        ivars->inPipe->AsyncIO(ivars->inBuffer, 64,
                                ivars->readCompleteAction, 0);
    }
}
```

**Writing Output Reports (Async):**

```cpp
// Prepare output report in buffer
// [0] = 0xFF (flags), [3] = right rumble, [4] = left rumble,
// [5] = red, [6] = green, [7] = blue, [8] = flash on, [9] = flash off

kern_return_t ret = ivars->outPipe->AsyncIO(
    ivars->outBuffer,          // IOMemoryDescriptor with output data
    32,                         // Output report size
    ivars->writeCompleteAction, // OSAction for completion
    0                            // Timeout
);
```

### Transfer Type Summary

```
┌─────────────────┬──────────────┬──────────────┬──────────────────────┐
│ Transfer Type   │ Endpoint     │ Direction    │ DS4 Usage            │
├─────────────────┼──────────────┼──────────────┼──────────────────────┤
│ Control         │ EP 0         │ Bidirectional│ Feature reports      │
│                 │              │              │ (calibration, MAC)   │
├─────────────────┼──────────────┼──────────────┼──────────────────────┤
│ Interrupt IN    │ EP 0x84      │ Device→Host  │ Input reports        │
│                 │              │              │ (buttons, sticks,    │
│                 │              │              │  IMU, touchpad)      │
├─────────────────┼──────────────┼──────────────┼──────────────────────┤
│ Interrupt OUT   │ EP 0x03      │ Host→Device  │ Output reports       │
│                 │              │              │ (LED, rumble)        │
└─────────────────┴──────────────┴──────────────┴──────────────────────┘
```

---

## 8. Driver Lifecycle

### DriverKit IOService Lifecycle

```
                        ┌─────────────┐
                        │   Device     │
                        │  Plugged In  │
                        └──────┬──────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  IOKit Matching   │
                    │  (Kernel-side)    │
                    │                   │
                    │  1. Class match   │
                    │  2. Passive match │
                    │     (VID/PID)     │
                    │  3. Probe score   │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │   Process Launch  │
                    │                   │
                    │  macOS starts a   │
                    │  new process for  │
                    │  the .dext driver │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │      init()       │
                    │                   │
                    │  - Allocate IVARs │
                    │  - Zero state     │
                    │  - No I/O here    │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │     Start()       │
                    │                   │
                    │  - Validate       │
                    │    provider       │
                    │  - Open interface │
                    │  - CopyPipe()     │
                    │  - Allocate       │
                    │    buffers        │
                    │  - Create         │
                    │    OSActions      │
                    │  - Begin async    │
                    │    reads          │
                    │  - RegisterService│
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │   Running State   │
                    │                   │
                    │  - Async read     │
                    │    completions    │
                    │  - Process input  │
                    │  - Send output    │
                    │  - Handle user    │
                    │    client calls   │
                    └────────┬─────────┘
                             │
                      (device unplugged
                       or system request)
                             │
                             ▼
                    ┌──────────────────┐
                    │      Stop()       │
                    │                   │
                    │  - Abort pipes    │
                    │  - Close          │
                    │    interface      │
                    │  - Release        │
                    │    buffers        │
                    │  - Release        │
                    │    OSActions      │
                    │  - Call           │
                    │    super::Stop()  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │      free()       │
                    │                   │
                    │  - Deallocate     │
                    │    IVARs          │
                    │  - Process exits  │
                    └──────────────────┘
```

### Lifecycle Methods in Detail

#### `init()`

```cpp
kern_return_t IMPL(DS4Driver, init)
{
    kern_return_t ret;
    ret = init(/* properties */);  // Call super
    if (ret != kIOReturnSuccess) return ret;

    // Allocate instance variables
    ivars = IONewZero(DS4Driver_IVars, 1);
    if (!ivars) return kIOReturnNoMemory;

    // Initialize state (no I/O or provider access here)
    ivars->isRunning = false;

    return kIOReturnSuccess;
}
```

#### `Start(IOService* provider)`

This is the most important method -- where you set up USB communication.

```cpp
kern_return_t IMPL(DS4Driver, Start)
{
    kern_return_t ret;

    // 1. Call super
    ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;

    // 2. Get and validate the provider (IOUSBHostInterface)
    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) return kIOReturnBadArgument;

    // 3. Open the interface
    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) return ret;

    // 4. Get the pipes for our endpoints
    ret = ivars->interface->CopyPipe(0x84, &ivars->inPipe);   // Interrupt IN
    if (ret != kIOReturnSuccess) goto cleanup;

    ret = ivars->interface->CopyPipe(0x03, &ivars->outPipe);  // Interrupt OUT
    if (ret != kIOReturnSuccess) goto cleanup;

    // 5. Allocate I/O buffers
    ret = ivars->interface->CreateIOBuffer(
        kIOMemoryDirectionIn, 64, &ivars->inBuffer);
    if (ret != kIOReturnSuccess) goto cleanup;

    ret = ivars->interface->CreateIOBuffer(
        kIOMemoryDirectionOut, 32, &ivars->outBuffer);
    if (ret != kIOReturnSuccess) goto cleanup;

    // 6. Create OSAction for async read completion
    ret = OSAction::Create(this, DS4Driver_ReadComplete_ID,
                           IOUSBHostPipe_CompleteAsyncIO_ID,
                           0, &ivars->readCompleteAction);
    if (ret != kIOReturnSuccess) goto cleanup;

    // 7. Start the first async read
    ret = ivars->inPipe->AsyncIO(ivars->inBuffer, 64,
                                  ivars->readCompleteAction, 0);
    if (ret != kIOReturnSuccess) goto cleanup;

    ivars->isRunning = true;

    // 8. Register the service so clients can find us
    RegisterService();

    return kIOReturnSuccess;

cleanup:
    Stop(provider, SUPERDISPATCH);
    return ret;
}
```

#### `Stop(IOService* provider)`

```cpp
kern_return_t IMPL(DS4Driver, Stop)
{
    ivars->isRunning = false;

    // Abort any pending I/O
    if (ivars->inPipe) {
        ivars->inPipe->Abort(kIOUSBHostAbortOptionSynchronous);
    }
    if (ivars->outPipe) {
        ivars->outPipe->Abort(kIOUSBHostAbortOptionSynchronous);
    }

    // Close the interface
    if (ivars->interface) {
        ivars->interface->Close(this, 0);
    }

    // Release resources
    OSSafeReleaseNULL(ivars->readCompleteAction);
    OSSafeReleaseNULL(ivars->inBuffer);
    OSSafeReleaseNULL(ivars->outBuffer);
    OSSafeReleaseNULL(ivars->inPipe);
    OSSafeReleaseNULL(ivars->outPipe);

    return Stop(provider, SUPERDISPATCH);
}
```

#### `free()`

```cpp
void IMPL(DS4Driver, free)
{
    IOSafeDeleteNULL(ivars, DS4Driver_IVars, 1);
    free(SUPERDISPATCH);
}
```

---

## 9. Code Examples

> **Note:** The DriverKit code examples in this section show a raw `IOService`-based approach for educational purposes. The recommended production architecture uses `IOUserHIDDevice` (HIDDriverKit) as documented in [10-macOS-Driver-Architecture.md](./10-macOS-Driver-Architecture.md). The `IOUserHIDDevice` approach enables automatic GameController framework integration by publishing the DS4 as a standard HID gamepad to the system.

### 9.1 Complete DriverKit USB HID Driver (IIG Header)

> **Class naming note:** The examples below use the class name `DS4Driver` (an `IOService` subclass) for this educational raw-USB approach. The canonical class name for the production driver is **`DS4HIDDevice`** (an `IOUserHIDDevice` subclass), as defined in [10-macOS-Driver-Architecture.md](./10-macOS-Driver-Architecture.md).

```cpp
// DS4Driver.iig -- Interface definition

#ifndef DS4Driver_h
#define DS4Driver_h

#include <Availability.h>
#include <DriverKit/IOService.iig>
#include <USBDriverKit/IOUSBHostInterface.iig>
#include <USBDriverKit/IOUSBHostPipe.iig>

class DS4Driver : public IOService
{
public:
    // Lifecycle
    virtual bool init() override;
    virtual kern_return_t Start(IOService* provider) override;
    virtual kern_return_t Stop(IOService* provider) override;
    virtual void free() override;

    // Async I/O completion callbacks
    virtual void ReadComplete(
        OSAction*   action,
        IOReturn    status,
        uint32_t    actualByteCount,
        uint64_t    completionTimestamp
    ) TYPE(IOUSBHostPipe::CompleteAsyncIO);

    virtual void WriteComplete(
        OSAction*   action,
        IOReturn    status,
        uint32_t    actualByteCount,
        uint64_t    completionTimestamp
    ) TYPE(IOUSBHostPipe::CompleteAsyncIO);
};

#endif /* DS4Driver_h */
```

### 9.2 Complete DriverKit USB HID Driver (Implementation)

```cpp
// DS4Driver.cpp -- Implementation

#include <os/log.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSAction.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/IOUSBHostPipe.h>

#include "DS4Driver.h"

static const uint16_t DS4_VID = 0x054C;
static const uint16_t DS4_PID_V1 = 0x05C4;
static const uint16_t DS4_PID_V2 = 0x09CC;

static const uint8_t DS4_EP_IN  = 0x84;  // Interrupt IN
static const uint8_t DS4_EP_OUT = 0x03;  // Interrupt OUT

static const uint32_t DS4_INPUT_REPORT_SIZE  = 64;
static const uint32_t DS4_OUTPUT_REPORT_SIZE = 32;

struct DS4Driver_IVars {
    IOUSBHostInterface*         interface;
    IOUSBHostPipe*              inPipe;
    IOUSBHostPipe*              outPipe;
    IOBufferMemoryDescriptor*   inBuffer;
    IOBufferMemoryDescriptor*   outBuffer;
    OSAction*                   readCompleteAction;
    OSAction*                   writeCompleteAction;
    bool                        isRunning;
};

bool IMPL(DS4Driver, init)
{
    if (!init()) return false;

    ivars = IONewZero(DS4Driver_IVars, 1);
    if (!ivars) return false;

    os_log(OS_LOG_DEFAULT, "DS4Driver: initialized");
    return true;
}

kern_return_t IMPL(DS4Driver, Start)
{
    kern_return_t ret;

    ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: super Start failed: 0x%x", ret);
        return ret;
    }

    // Cast provider to IOUSBHostInterface
    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: provider is not IOUSBHostInterface");
        return kIOReturnBadArgument;
    }

    // Open the interface
    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to open interface: 0x%x", ret);
        return ret;
    }

    // Get the Interrupt IN pipe
    ret = ivars->interface->CopyPipe(DS4_EP_IN, &ivars->inPipe);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to copy IN pipe: 0x%x", ret);
        goto cleanup;
    }

    // Get the Interrupt OUT pipe
    ret = ivars->interface->CopyPipe(DS4_EP_OUT, &ivars->outPipe);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to copy OUT pipe: 0x%x", ret);
        goto cleanup;
    }

    // Allocate input buffer
    ret = ivars->interface->CreateIOBuffer(
        kIOMemoryDirectionIn, DS4_INPUT_REPORT_SIZE, &ivars->inBuffer);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to create input buffer: 0x%x", ret);
        goto cleanup;
    }

    // Allocate output buffer
    ret = ivars->interface->CreateIOBuffer(
        kIOMemoryDirectionOut, DS4_OUTPUT_REPORT_SIZE, &ivars->outBuffer);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to create output buffer: 0x%x", ret);
        goto cleanup;
    }

    // Create async read completion action
    ret = CreateActionReadComplete(0, &ivars->readCompleteAction);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to create read action: 0x%x", ret);
        goto cleanup;
    }

    // Create async write completion action
    ret = CreateActionWriteComplete(0, &ivars->writeCompleteAction);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to create write action: 0x%x", ret);
        goto cleanup;
    }

    // Start the first async read
    ret = ivars->inPipe->AsyncIO(
        ivars->inBuffer, DS4_INPUT_REPORT_SIZE,
        ivars->readCompleteAction, 0);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: failed to start async read: 0x%x", ret);
        goto cleanup;
    }

    ivars->isRunning = true;
    os_log(OS_LOG_DEFAULT, "DS4Driver: started successfully");

    RegisterService();
    return kIOReturnSuccess;

cleanup:
    Stop(provider, SUPERDISPATCH);
    return ret;
}

void IMPL(DS4Driver, ReadComplete)
{
    if (status == kIOReturnSuccess && actualByteCount > 0) {
        // Access the buffer data
        uint64_t address = 0;
        uint64_t length = 0;
        ivars->inBuffer->Map(0, 0, 0, 0, &address, &length);

        uint8_t* data = reinterpret_cast<uint8_t*>(address);

        // Parse the input report
        if (data[0] == 0x01) {  // Standard input report
            uint8_t leftStickX  = data[1];
            uint8_t leftStickY  = data[2];
            uint8_t rightStickX = data[3];
            uint8_t rightStickY = data[4];
            uint8_t buttons1    = data[5];
            uint8_t buttons2    = data[6];
            uint8_t l2Trigger   = data[8];
            uint8_t r2Trigger   = data[9];

            // Process and forward to clients...
            (void)leftStickX; (void)leftStickY;
            (void)rightStickX; (void)rightStickY;
            (void)buttons1; (void)buttons2;
            (void)l2Trigger; (void)r2Trigger;
        }
    }

    // Re-enqueue the next read unless aborted
    if (status != kIOReturnAborted && ivars->isRunning) {
        ivars->inPipe->AsyncIO(
            ivars->inBuffer, DS4_INPUT_REPORT_SIZE,
            ivars->readCompleteAction, 0);
    }
}

void IMPL(DS4Driver, WriteComplete)
{
    if (status != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, "DS4Driver: write failed: 0x%x", status);
    }
}

kern_return_t IMPL(DS4Driver, Stop)
{
    os_log(OS_LOG_DEFAULT, "DS4Driver: stopping");
    ivars->isRunning = false;

    if (ivars->inPipe) {
        ivars->inPipe->Abort(kIOUSBHostAbortOptionSynchronous);
    }
    if (ivars->outPipe) {
        ivars->outPipe->Abort(kIOUSBHostAbortOptionSynchronous);
    }
    if (ivars->interface) {
        ivars->interface->Close(this, 0);
    }

    OSSafeReleaseNULL(ivars->readCompleteAction);
    OSSafeReleaseNULL(ivars->writeCompleteAction);
    OSSafeReleaseNULL(ivars->inBuffer);
    OSSafeReleaseNULL(ivars->outBuffer);
    OSSafeReleaseNULL(ivars->inPipe);
    OSSafeReleaseNULL(ivars->outPipe);

    return Stop(provider, SUPERDISPATCH);
}

void IMPL(DS4Driver, free)
{
    IOSafeDeleteNULL(ivars, DS4Driver_IVars, 1);
    free(SUPERDISPATCH);
}
```

### 9.3 Setting LED Color and Rumble

```cpp
void DS4Driver::SetLEDAndRumble(uint8_t red, uint8_t green, uint8_t blue,
                                 uint8_t smallRumble, uint8_t bigRumble)
{
    if (!ivars->isRunning || !ivars->outBuffer) return;

    // Map the output buffer
    uint64_t address = 0;
    uint64_t length = 0;
    ivars->outBuffer->Map(0, 0, 0, 0, &address, &length);
    uint8_t* report = reinterpret_cast<uint8_t*>(address);

    // Clear the buffer
    memset(report, 0, DS4_OUTPUT_REPORT_SIZE);

    // Build output report (Report ID 0x05)
    report[0] = 0xFF;          // Enable flags (rumble + LED)
    report[1] = 0x00;          // Reserved
    report[2] = 0x00;          // Reserved
    report[3] = smallRumble;   // Right motor (weak/fast)
    report[4] = bigRumble;     // Left motor (strong/slow)
    report[5] = red;           // LED Red
    report[6] = green;         // LED Green
    report[7] = blue;          // LED Blue
    report[8] = 0x00;          // Flash on duration
    report[9] = 0x00;          // Flash off duration

    // Send asynchronously
    ivars->outPipe->AsyncIO(
        ivars->outBuffer, DS4_OUTPUT_REPORT_SIZE,
        ivars->writeCompleteAction, 0);
}
```

### 9.4 Reading Feature Report (MAC Address)

```cpp
kern_return_t DS4Driver::ReadMACAddress(uint8_t macAddress[6])
{
    // Feature report 0x81 returns 7 bytes: [report_id, mac[0..5]]
    uint16_t bytesTransferred = 0;

    // Create a buffer for the feature report
    IOBufferMemoryDescriptor* featureBuffer = nullptr;
    kern_return_t ret = ivars->interface->CreateIOBuffer(
        kIOMemoryDirectionIn, 7, &featureBuffer);
    if (ret != kIOReturnSuccess) return ret;

    // HID GET_REPORT: bmRequestType=0xA1, bRequest=0x01
    // wValue = (ReportType << 8) | ReportID = (3 << 8) | 0x81
    ret = ivars->interface->DeviceRequest(
        this,
        0xA1,                       // bmRequestType: IN, Class, Interface
        0x01,                       // bRequest: GET_REPORT
        (0x03 << 8) | 0x81,        // wValue: Feature(3) | ReportID(0x81)
        0,                          // wIndex: Interface 0
        7,                          // wLength
        featureBuffer,              // data buffer
        &bytesTransferred
    );

    if (ret == kIOReturnSuccess && bytesTransferred >= 7) {
        uint64_t address = 0;
        uint64_t length = 0;
        featureBuffer->Map(0, 0, 0, 0, &address, &length);
        uint8_t* data = reinterpret_cast<uint8_t*>(address);

        // MAC address is in bytes 1-6 (reversed)
        for (int i = 0; i < 6; i++) {
            macAddress[i] = data[6 - i];
        }
    }

    OSSafeReleaseNULL(featureBuffer);
    return ret;
}
```

---

## 10. Legacy IOKit Reference

This section documents the existing IOKit KEXT code for reference during migration.

### Existing Architecture

The current DS4 driver consists of two classes:

```
DS4Service : IOService
  └── Basic IOService that matches and loads
      File: DS4/DS4Service.h, DS4/DS4Service.cpp

SonyPlaystationDualShock4 : IOHIDDevice
  └── HID device driver that provides a report descriptor
      File: DS4/DS4.h, DS4/DS4.cpp
      Uses: DS4/dualshock4hid.h (HID report descriptor)
```

### Legacy Info.plist Matching

```xml
<!-- From DS4/Info.plist -->
<key>IOKitPersonalities</key>
<dict>
    <key>DS4</key>
    <dict>
        <key>IOMatchCategory</key>
        <string>SonyPlaystationDualShock4</string>
        <key>idVendor</key>
        <integer>1356</integer>          <!-- 0x054C = Sony -->
        <key>idProduct</key>
        <integer>1476</integer>          <!-- 0x05C4 = DS4 V1 -->
        <key>CFBundleIdentifier</key>
        <string>com.ds4mac.driver.DS4</string>
        <key>IOClass</key>
        <string>SonyPlaystationDualShock4</string>
        <key>IOProviderClass</key>
        <string>IOUSBDevice</string>     <!-- Device-level matching -->
        <key>IOKitDebug</key>
        <integer>65535</integer>
    </dict>
</dict>
```

### Legacy IOHIDDevice Subclass

```cpp
// DS4/DS4.h -- Legacy header
#include <IOKit/usb/IOUSBDevice.h>
#include <IOKit/hid/IOHIDDevice.h>

class SonyPlaystationDualShock4 : public IOHIDDevice
{
    OSDeclareDefaultStructors(SonyPlaystationDualShock4)
public:
    virtual bool init(OSDictionary *dictionary = 0);
    virtual void free(void);
    virtual IOService *probe(IOService *provider, SInt32 *score);
    virtual bool start(IOService *provider);
    virtual void stop(IOService *provider);
    virtual IOReturn newReportDescriptor(IOMemoryDescriptor **descriptor) const;
};
```

### Legacy Lifecycle

```cpp
// DS4/DS4.cpp -- Legacy lifecycle methods

OSDefineMetaClassAndStructors(SonyPlaystationDualShock4, IOHIDDevice)
#define super IOHIDDevice

bool SonyPlaystationDualShock4::init(OSDictionary *dict) {
    return super::init(dict);
}

IOService* SonyPlaystationDualShock4::probe(IOService *provider, SInt32 *score) {
    return IOHIDDevice::probe(provider, score);
}

bool SonyPlaystationDualShock4::start(IOService *provider) {
    return IOHIDDevice::start(provider);
}

void SonyPlaystationDualShock4::stop(IOService *provider) {
    super::stop(provider);
}

// The key method: provides the HID report descriptor to the system
IOReturn SonyPlaystationDualShock4::newReportDescriptor(
    IOMemoryDescriptor **descriptor) const
{
    IOBufferMemoryDescriptor *buffer =
        IOBufferMemoryDescriptor::inTaskWithOptions(
            kernel_task, 0, sizeof(HID_DS4::ReportDescriptor));
    if (!buffer) return kIOReturnNoResources;

    buffer->writeBytes(0, HID_DS4::ReportDescriptor,
                       sizeof(HID_DS4::ReportDescriptor));
    *descriptor = buffer;
    return kIOReturnSuccess;
}
```

### Migration Mapping: IOKit to DriverKit

| IOKit (Legacy) | DriverKit (Modern) | Notes |
|---------------|-------------------|-------|
| `IOService` | `IOService` (DriverKit) | Same name, different framework |
| `IOHIDDevice` | `IOUserHIDDevice` (HIDDriverKit) | Or handle HID in USBDriverKit directly |
| `IOUSBDevice` | `IOUSBHostDevice` | Provider class |
| `IOUSBInterface` | `IOUSBHostInterface` | Preferred matching level for DriverKit |
| `IOUSBPipe` | `IOUSBHostPipe` | Endpoint access |
| `IOMemoryDescriptor` | `IOMemoryDescriptor` (DriverKit) | Similar API, different implementation |
| `IOBufferMemoryDescriptor` | `IOBufferMemoryDescriptor` (DriverKit) | Must use `CreateIOBuffer()` |
| `IOWorkLoop` | `DispatchQueue` | GCD-based concurrency model |
| C function callbacks | `OSAction` | Type-safe async callbacks |
| `OSDictionary` / `OSArray` | `OSDictionary` / `OSArray` | Subset available in DriverKit |
| `IOLog()` | `os_log()` | User-space logging |
| `OSDefineMetaClassAndStructors` | `IMPL` macro + `.iig` | IIG generates boilerplate |
| `kernel_task` operations | Not available | DriverKit runs in user space |
| `kIOReturnSuccess` | `kIOReturnSuccess` | Same return codes |

---

## 11. Entitlements and Provisioning

### Required Entitlements

DriverKit system extensions require specific entitlements that must be provisioned through Apple Developer Program enrollment.

#### Driver Extension (`.dext`) Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: Base DriverKit entitlement -->
    <key>com.apple.developer.driverkit</key>
    <true/>

    <!-- Required: USB transport entitlement with vendor ID + product ID -->
    <key>com.apple.developer.driverkit.transport.usb</key>
    <array>
        <!-- Sony Corp. DS4 V1: VID 0x054C, PID 0x05C4 -->
        <dict>
            <key>idVendor</key>
            <integer>1356</integer>
            <key>idProduct</key>
            <integer>1476</integer>
        </dict>
        <!-- Sony Corp. DS4 V2: VID 0x054C, PID 0x09CC -->
        <dict>
            <key>idVendor</key>
            <integer>1356</integer>
            <key>idProduct</key>
            <integer>2508</integer>
        </dict>
    </array>

    <!-- Optional: HID family entitlement (if acting as HID device) -->
    <key>com.apple.developer.driverkit.family.hid.device</key>
    <true/>

    <!-- Optional: HID event service (for virtual HID events) -->
    <key>com.apple.developer.driverkit.family.hid.eventservice</key>
    <true/>

    <!-- Optional: Allow user clients to connect to the driver -->
    <key>com.apple.developer.driverkit.userclient-access</key>
    <array>
        <string>com.ds4mac.app</string>
    </array>
</dict>
</plist>
```

#### Container App Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: Permission to install system extensions -->
    <key>com.apple.developer.system-extension.install</key>
    <true/>

    <!-- Optional: USB device access from the app itself -->
    <key>com.apple.security.device.usb</key>
    <true/>

    <!-- Optional: Bluetooth access for DS4 Bluetooth transport in companion app -->
    <key>com.apple.security.device.bluetooth</key>
    <true/>

    <!-- Optional: If app is sandboxed -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

### Entitlement Summary

| Entitlement | Target | Required | Purpose |
|------------|--------|----------|---------|
| `com.apple.developer.driverkit` | dext | Yes | Base DriverKit permission |
| `com.apple.developer.driverkit.transport.usb` | dext | Yes | USB device access (specify VID) |
| `com.apple.developer.driverkit.family.hid.device` | dext | Conditional | If driver exposes HID services |
| `com.apple.developer.driverkit.family.hid.eventservice` | dext | Conditional | If driver posts HID events |
| `com.apple.developer.driverkit.userclient-access` | dext | Conditional | If app communicates with driver directly |
| `com.apple.developer.system-extension.install` | app | Yes | Install/activate system extensions |
| `com.apple.security.device.usb` | app | Conditional | Direct USB from app (sandboxed) |

### Provisioning Profile Requirements

1. **Apple Developer Program membership** is required (not free tier)
2. **Request DriverKit entitlements** through Apple Developer account:
   - Navigate to Certificates, Identifiers & Profiles
   - Create or edit your App ID
   - Under "Additional Capabilities", enable DriverKit
   - Request specific transport entitlements (USB with vendor IDs)
3. **Provisioning profile must include** all entitlements used by the `.dext`
4. **Your dext entitlements must be a subset** of those in the provisioning profile
5. **For distribution**: Notarize the app with `notarytool` before distribution

### Code Signing Requirements

| Build Type | Certificate | Notarization | User Approval |
|-----------|------------|--------------|--------------|
| Development | Development cert | Not required | Auto-approved in SIP disabled mode |
| Testing | Developer ID | Recommended | System Settings approval |
| Distribution | Developer ID | **Required** | System Settings approval |
| Mac App Store | App Store cert | Handled by store | Handled by store |

### Development Tips

- During development with SIP disabled (`csrutil disable`), you can use `systemextensionsctl developer on` to skip user approval
- Use `kmutil showloaded` to see loaded extensions
- Use `systemextensionsctl list` to see installed system extensions
- Logs: `log stream --predicate 'subsystem == "com.apple.SystemExtensions"'`

---

## 12. App-Level Alternative

For prototyping and rapid development, you can communicate with the DS4 directly from a macOS app using the `IOUSBHost` framework -- no system extension required.

### Swift IOUSBHost Example

```swift
import IOUSBHost
import Foundation

class DS4USBManager {
    // DS4 identifiers
    static let sonyVendorID: Int = 0x054C
    static let ds4v1ProductID: Int = 0x05C4
    static let ds4v2ProductID: Int = 0x09CC

    private var device: IOUSBHostDevice?
    private var interface: IOUSBHostInterface?
    private var inPipe: IOUSBHostPipe?
    private var outPipe: IOUSBHostPipe?
    private var readBuffer = Data(count: 64)

    // MARK: - Discovery

    /// Create a matching dictionary for the DS4
    static func createMatchingDictionary() -> [String: Any] {
        return IOUSBHostDevice.createMatchingDictionary(
            vendorID: sonyVendorID,
            productID: ds4v2ProductID
        )
    }

    // MARK: - Connection

    /// Open the DS4 device and set up pipes
    func open(device: IOUSBHostDevice) throws {
        self.device = device

        // Open the device
        try device.open()

        // Find the HID interface (class 3)
        var request = IOUSBFindInterfaceRequest()
        request.bInterfaceClass = 3      // HID
        request.bInterfaceSubClass = 0
        request.bInterfaceProtocol = 0

        guard let iface = device.copyInterface(with: request) else {
            throw DS4Error.interfaceNotFound
        }
        self.interface = iface

        // Open the interface
        try iface.open()

        // Get the pipes
        // Endpoint 0x84 = Interrupt IN (input reports)
        self.inPipe = iface.copyPipe(withAddress: 0x84)

        // Endpoint 0x03 = Interrupt OUT (output reports)
        self.outPipe = iface.copyPipe(withAddress: 0x03)

        guard inPipe != nil, outPipe != nil else {
            throw DS4Error.pipeNotFound
        }
    }

    // MARK: - Reading Input Reports

    /// Read a single input report (synchronous)
    func readInputReport() throws -> DS4InputReport {
        guard let pipe = inPipe else {
            throw DS4Error.notConnected
        }

        var buffer = Data(count: 64)
        let bytesRead = try buffer.withUnsafeMutableBytes { ptr -> Int in
            let mutableData = NSMutableData(
                bytesNoCopy: ptr.baseAddress!,
                length: 64,
                freeWhenDone: false
            )
            return pipe.sendIORequest(with: mutableData)
        }

        guard bytesRead >= 10 else {
            throw DS4Error.shortRead
        }

        return DS4InputReport(data: buffer)
    }

    /// Start continuous async reading
    func startReading(handler: @escaping (DS4InputReport) -> Void) {
        guard let pipe = inPipe else { return }

        let mutableData = NSMutableData(length: 64)!
        pipe.enqueueIORequest(with: mutableData) { [weak self] status, bytesRead in
            guard status == kIOReturnSuccess, bytesRead > 0 else { return }

            let data = Data(referencing: mutableData)
            let report = DS4InputReport(data: data)
            handler(report)

            // Re-enqueue
            self?.startReading(handler: handler)
        }
    }

    // MARK: - Writing Output Reports

    /// Set LED color and rumble
    func setLEDAndRumble(
        red: UInt8, green: UInt8, blue: UInt8,
        smallRumble: UInt8 = 0, bigRumble: UInt8 = 0
    ) throws {
        guard let pipe = outPipe else {
            throw DS4Error.notConnected
        }

        var report = Data(count: 32)
        report[0] = 0xFF          // Enable flags
        report[1] = 0x00
        report[2] = 0x00
        report[3] = smallRumble   // Right motor
        report[4] = bigRumble     // Left motor
        report[5] = red
        report[6] = green
        report[7] = blue
        report[8] = 0x00          // Flash on
        report[9] = 0x00          // Flash off

        let mutableData = NSMutableData(data: report)
        _ = pipe.sendIORequest(with: mutableData)
    }

    // MARK: - Feature Reports

    /// Read the DS4's Bluetooth MAC address
    func readMACAddress() throws -> String {
        guard let iface = interface else {
            throw DS4Error.notConnected
        }

        // HID GET_REPORT for feature report 0x81
        var buffer = Data(count: 7)
        try buffer.withUnsafeMutableBytes { ptr in
            let mutableData = NSMutableData(
                bytesNoCopy: ptr.baseAddress!,
                length: 7,
                freeWhenDone: false
            )
            // Use DeviceRequest for control transfers
            try iface.sendDeviceRequest(
                requestType: 0xA1,    // IN, Class, Interface
                request: 0x01,         // GET_REPORT
                value: 0x0381,         // Feature(3) | ReportID(0x81)
                index: 0,
                data: mutableData
            )
        }

        // Parse MAC (bytes 1-6, reversed)
        let mac = (1...6).reversed().map { String(format: "%02X", buffer[$0]) }
        return mac.joined(separator: ":")
    }

    // MARK: - Cleanup

    func close() {
        inPipe?.abort()
        outPipe?.abort()
        interface?.close()
        device?.close()
    }
}
```

### Input Report Parsing (Swift)

```swift
struct DS4InputReport {
    // Analog sticks (0-255, center = 128)
    let leftStickX: UInt8
    let leftStickY: UInt8
    let rightStickX: UInt8
    let rightStickY: UInt8

    // D-Pad
    let dpadUp: Bool
    let dpadDown: Bool
    let dpadLeft: Bool
    let dpadRight: Bool

    // Face buttons
    let cross: Bool
    let circle: Bool
    let square: Bool
    let triangle: Bool

    // Shoulder buttons
    let l1: Bool
    let r1: Bool
    let l2Digital: Bool
    let r2Digital: Bool

    // Triggers (analog)
    let l2Analog: UInt8
    let r2Analog: UInt8

    // Other buttons
    let share: Bool
    let options: Bool
    let l3: Bool
    let r3: Bool
    let ps: Bool
    let touchpadClick: Bool

    // IMU (signed 16-bit)
    let gyroPitch: Int16
    let gyroYaw: Int16
    let gyroRoll: Int16
    let accelX: Int16
    let accelY: Int16
    let accelZ: Int16

    // Battery
    let batteryLevel: UInt8
    let isUSBConnected: Bool

    init(data: Data) {
        leftStickX  = data[1]
        leftStickY  = data[2]
        rightStickX = data[3]
        rightStickY = data[4]

        let dpad = data[5] & 0x0F
        dpadUp    = (dpad == 0 || dpad == 1 || dpad == 7)
        dpadDown  = (dpad == 3 || dpad == 4 || dpad == 5)
        dpadLeft  = (dpad == 5 || dpad == 6 || dpad == 7)
        dpadRight = (dpad == 1 || dpad == 2 || dpad == 3)

        square   = (data[5] & 0x10) != 0
        cross    = (data[5] & 0x20) != 0
        circle   = (data[5] & 0x40) != 0
        triangle = (data[5] & 0x80) != 0

        l1        = (data[6] & 0x01) != 0
        r1        = (data[6] & 0x02) != 0
        l2Digital = (data[6] & 0x04) != 0
        r2Digital = (data[6] & 0x08) != 0
        share     = (data[6] & 0x10) != 0
        options   = (data[6] & 0x20) != 0
        l3        = (data[6] & 0x40) != 0
        r3        = (data[6] & 0x80) != 0

        ps           = (data[7] & 0x01) != 0
        touchpadClick = (data[7] & 0x02) != 0

        l2Analog = data[8]
        r2Analog = data[9]

        gyroPitch = Int16(data[13]) | (Int16(data[14]) << 8)
        gyroYaw   = Int16(data[15]) | (Int16(data[16]) << 8)
        gyroRoll  = Int16(data[17]) | (Int16(data[18]) << 8)
        accelX    = Int16(data[19]) | (Int16(data[20]) << 8)
        accelY    = Int16(data[21]) | (Int16(data[22]) << 8)
        accelZ    = Int16(data[23]) | (Int16(data[24]) << 8)

        batteryLevel  = data[30] & 0x0F
        isUSBConnected = (data[30] & 0x10) != 0
    }
}
```

### System Extension Activation (App Side)

```swift
import SystemExtensions

class ExtensionManager: NSObject, OSSystemExtensionRequestDelegate {
    static let dextIdentifier = "com.ds4mac.driver.DS4Driver"

    func activateDriver() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.dextIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivateDriver() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.dextIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace  // Always replace with newer version
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // User needs to approve in System Settings > Privacy & Security
        print("Please approve the driver extension in System Settings")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            print("Driver extension activated successfully")
        case .willCompleteAfterReboot:
            print("Driver extension will be active after reboot")
        @unknown default:
            print("Unknown result: \(result)")
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFailWithError error: Error) {
        print("Driver extension failed: \(error.localizedDescription)")
    }
}
```

### Choosing Your Approach

```
Development Phase Decision Tree:
─────────────────────────────────

Q: Do you need the driver to work without the app running?
  │
  ├── YES ──► DriverKit System Extension (.dext)
  │            - Matches and launches automatically on device connect
  │            - Requires Apple entitlements and provisioning
  │            - Full production solution
  │
  └── NO ──► App-Level USB Access
              │
              Q: Do you need to intercept/modify HID reports system-wide?
              │
              ├── YES ──► IOUSBHost + IOHIDManager (app-level)
              │            - Can claim device exclusively
              │            - Repost events via virtual HID
              │            - Requires app to be running
              │
              └── NO ──► IOUSBHost only (simplest)
                          - Direct USB communication from app
                          - Good for prototyping
                          - Good for standalone utility apps
```

---

## Appendix A: Quick Reference Card

### DS4 USB Constants

```cpp
// Device identification
#define DS4_VID              0x054C
#define DS4_PID_V1           0x05C4
#define DS4_PID_V2           0x09CC

// Endpoints
#define DS4_EP_IN            0x84   // Interrupt IN
#define DS4_EP_OUT           0x03   // Interrupt OUT

// Report IDs
#define DS4_REPORT_INPUT     0x01   // Standard input (64 bytes)
#define DS4_REPORT_OUTPUT    0x05   // LED + Rumble (32 bytes)
#define DS4_REPORT_MAC       0x81   // Feature: MAC address (7 bytes)
#define DS4_REPORT_CALIB     0x02   // Feature: Calibration (37 bytes)

// Report sizes
#define DS4_INPUT_REPORT_SIZE   64
#define DS4_OUTPUT_REPORT_SIZE  32

// HID class requests
#define HID_GET_REPORT       0x01
#define HID_SET_REPORT       0x09
#define HID_REPORT_TYPE_INPUT    1
#define HID_REPORT_TYPE_OUTPUT   2
#define HID_REPORT_TYPE_FEATURE  3

// USB interface class
#define USB_CLASS_HID        0x03
```

### Common `kern_return_t` Values

| Value | Name | Meaning |
|-------|------|---------|
| `0x0` | `kIOReturnSuccess` | Operation succeeded |
| `0xE00002BC` | `kIOReturnNoMemory` | Memory allocation failed |
| `0xE00002C2` | `kIOReturnNoDevice` | Device not found |
| `0xE00002ED` | `kIOReturnAborted` | Operation aborted |
| `0xE00002EB` | `kIOReturnTimeout` | Operation timed out |
| `0xE00002C0` | `kIOReturnBadArgument` | Invalid argument |
| `0xE00002BE` | `kIOReturnExclusiveAccess` | Exclusive access denied |
| `0xE0004057` | `kIOUSBPipeStalled` | Endpoint stall |
| `0xE0004000` | `kIOUSBUnknownPipeErr` | Unknown pipe error |

---

## Appendix B: Further Reading

### Apple Documentation
- [USBDriverKit Framework](https://developer.apple.com/documentation/usbdriverkit)
- [IOUSBHost Framework](https://developer.apple.com/documentation/iousbhost)
- [DriverKit Framework](https://developer.apple.com/documentation/driverkit)
- [HIDDriverKit Framework](https://developer.apple.com/documentation/hiddriverkit)
- [System Extensions and DriverKit (WWDC 2019)](https://developer.apple.com/videos/play/wwdc2019/702/)
- [Deprecated KEXTs and Alternatives](https://developer.apple.com/support/kernel-extensions/)
- [Installing System Extensions and Drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)
- [DriverKit Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.device)

### Community Resources
- [USBApp - DriverKit USB Sample (GitHub)](https://github.com/knightsc/USBApp)
- [DriverKitUserClientSample (GitHub)](https://github.com/DanBurkhardt/DriverKitUserClientSample)
- [ROG-HID - DriverKit HID Driver (GitHub)](https://github.com/black-dragon74/ROG-HID)
- [Karabiner-DriverKit-VirtualHIDDevice (GitHub)](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
- [deft-simple-usb - Swift IOUSBHost (GitHub)](https://github.com/didactek/deft-simple-usb)
- [DS4 Data Structures Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [MacOS Drivers Instruction (GitHub)](https://github.com/dariaomelkina/MacOS_drivers_instruction)

### DS4 Protocol References
- [DS4 Reverse Engineering Blog](https://blog.the.al/2023/01/01/ds4-reverse-engineering.html)
- [dsremap Reverse Engineering Docs](https://dsremap.readthedocs.io/en/latest/reverse.html)
- [DS4 on Gentoo Wiki](https://wiki.gentoo.org/wiki/Sony_DualShock)
- [GIMX DualShock 4 Wiki](https://gimx.fr/wiki/index.php?title=DualShock_4)
