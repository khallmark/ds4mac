# DS4 Bluetooth Protocol Reference

> Comprehensive reverse-engineered protocol documentation for the Sony DualShock 4 (DS4) controller over Bluetooth Classic.
> Compiled from psdevwiki, controllers.fandom.com, GIMX wiki, eleccelerator wiki, dsremap, ds4drv (chrippa + clearpathrobotics), DS4Windows source code, and original firmware analysis.
> Cross-references: [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | [02-Core-Bluetooth-APIs](./02-Core-Bluetooth-APIs.md) | [06-Light-Bar-Feature](./06-Light-Bar-Feature.md)

> **Size Convention:** All report sizes in this document INCLUDE the Report ID byte unless explicitly noted otherwise.

---

## Table of Contents

1. [Bluetooth Profile and Transport](#1-bluetooth-profile-and-transport)
2. [Pairing Process](#2-pairing-process)
3. [Connection Initialization and Mode Switching](#3-connection-initialization-and-mode-switching)
4. [Input Report 0x01 (Reduced Mode)](#4-input-report-0x01-reduced-mode)
5. [Input Report 0x11 (Full Mode)](#5-input-report-0x11-full-mode)
6. [Output Report 0x11 (Bluetooth)](#6-output-report-0x11-bluetooth)
7. [Feature Reports over Bluetooth](#7-feature-reports-over-bluetooth)
8. [CRC-32 Calculation](#8-crc-32-calculation)
9. [Authentication Protocol](#9-authentication-protocol)
10. [Connection Management](#10-connection-management)
11. [Audio Reports](#11-audio-reports)
12. [USB vs Bluetooth Comparison](#12-usb-vs-bluetooth-comparison)
13. [Code Examples](#13-code-examples)

---

## 1. Bluetooth Profile and Transport

### 1.1 Bluetooth Hardware

The DS4 uses a **Qualcomm Atheros AR3002-BL3D** Bluetooth module communicating at **3 Mbit/s UART baud rate** with **8N1** framing. It operates over **Bluetooth Classic** (BR/EDR), not Bluetooth Low Energy (BLE).

### 1.2 Device Identification

| Field | Value | Description |
|-------|-------|-------------|
| Vendor ID (VID) | `0x054C` | Sony Corporation |
| Product ID (PID) v1 | `0x05C4` | DualShock 4 [CUH-ZCT1x] |
| Product ID (PID) v2 | `0x09CC` | DualShock 4 [CUH-ZCT2x] |
| Device Name | `Wireless Controller` | Bluetooth device name for game controller |
| Class of Device (Game) | `0x002508` | Peripheral / Gamepad |
| Class of Device (Audio) | `0x200404` | Audio/Video / Wearable Headset |

The DS4 advertises as **two separate Bluetooth services**: a game controller (CoD `0x002508`) and an audio device (CoD `0x200404`). The game controller service is the primary HID interface.

**Class of Device breakdown (Game Controller -- `0x002508`):**
```
Bits 23-13: Major Service Class = 0x002 (Limited Discoverable Mode)
Bits 12-8:  Major Device Class  = 0x05  (Peripheral)
Bits  7-2:  Minor Device Class  = 0x02  (Gamepad)
Bits  1-0:  Reserved            = 0x00
```

### 1.3 HID over Bluetooth Classic

The DS4 uses the standard **Bluetooth HID Profile (HID-P)**, which operates over the **L2CAP** (Logical Link Control and Adaptation Protocol) layer.

#### L2CAP Channels (PSM)

| PSM | Channel Name | Purpose |
|-----|-------------|---------|
| `0x0011` (17) | HID Control | Feature reports (GET/SET REPORT), control commands |
| `0x0013` (19) | HID Interrupt | Input reports (controller state), output reports (rumble/LED) |

These are the standard Protocol Service Multiplexer values defined by the Bluetooth HID Profile specification. Both channels must be connected for full functionality.

**From ds4drv source code:**
```python
L2CAP_PSM_HIDP_CTRL = 0x11  # HID Control channel
L2CAP_PSM_HIDP_INTR = 0x13  # HID Interrupt channel
```

#### L2CAP Channel IDs (CID)

In HCI-level captures, the L2CAP channels appear with dynamically assigned CIDs. Typical observed values:

| CID | Usage |
|-----|-------|
| `0x0040` | HID Interrupt (input reports) |
| `0x0042` | HID Control (feature/command reports) |

### 1.4 HID Transaction Header

Every HID report sent over Bluetooth includes a transaction header byte prepended to the data. This header byte encodes the transaction type and report type.

```
Header byte format:
  Bits 7-4: Transaction Type
  Bits 3-2: Parameter
  Bits 1-0: Report Type (for DATA transactions)

Transaction Types:
  0x04 = GET_REPORT
  0x05 = SET_REPORT
  0x0A = DATA

Report Types:
  0x01 = INPUT
  0x02 = OUTPUT
  0x03 = FEATURE
```

| HID Header | Meaning | Direction |
|------------|---------|-----------|
| `0xA1` | DATA + INPUT (`0x0A << 4 | 0x01`) | DS4 -> Host (interrupt channel) |
| `0xA2` | DATA + OUTPUT (`0x0A << 4 | 0x02`) | Host -> DS4 (interrupt channel) |
| `0x43` | GET_REPORT + FEATURE (`0x04 << 4 | 0x03`) | Host -> DS4 (control channel) |
| `0x53` | SET_REPORT + FEATURE (`0x05 << 4 | 0x03`) | Host -> DS4 (control channel) |
| `0x52` | SET_REPORT + OUTPUT (`0x05 << 4 | 0x02`) | Host -> DS4 (control channel) |

**Important:** When computing CRC-32 checksums for Bluetooth reports, the HID transaction header byte (`0xA1`, `0xA2`, `0xA3`, or `0x53`) is included in the CRC calculation as a prefix, even though it is not part of the HID report data itself. This is a critical distinction from USB mode.

### 1.5 SDP Records

The DS4 provides Service Discovery Protocol (SDP) records that describe its HID capabilities. SDP uses a request/response model:

| PDU Type | Value | Description |
|----------|-------|-------------|
| Search Request | `0x02` | Search for service records |
| Search Response | `0x03` | Returns matching service handles |
| Search Attribute Request | `0x06` | Search for specific attributes |
| Search Attribute Response | `0x07` | Returns attribute values |

SDP data elements use a Type-Length-Value (TLV) encoding:
```
Byte 0: [Type (3 bits)][Length descriptor (5 bits)]
Type values:
  0 = Nil
  1 = Unsigned Integer
  3 = UUID
  4 = Text String
  6 = Data Element Sequence
  7 = Data Element Alternative
```

### 1.6 Report Rates

The Bluetooth report rate depends on the number of active controllers and communication mode:

| Controllers | Input+Output | Output Only | Input Only |
|-------------|-------------|-------------|------------|
| 1 | ~800 Hz (1.25 ms) | ~400 Hz (2.50 ms) | ~125 Hz (8 ms) |
| 2 | ~400 Hz (2.50 ms) | ~200 Hz (5 ms) | ~62.5 Hz (16 ms) |
| 4 | ~200 Hz (5 ms) | ~100 Hz (10 ms) | ~31.25 Hz (32 ms) |

Typical report interval is approximately **1.3 ms** with occasional gaps reaching **15 ms** due to Bluetooth scheduling. This is notably faster than USB mode (~4 ms / 250 Hz).

---

## 2. Pairing Process

### 2.1 Entering Pairing Mode

The DS4 enters Bluetooth pairing (discoverable) mode by:

1. **Hold PS + Share buttons simultaneously** until the light bar starts flashing rapidly (double-blink pattern)
2. The controller remains in pairing mode for approximately 60 seconds
3. During pairing mode, the light bar blinks white in rapid double pulses

### 2.2 Standard Bluetooth Pairing Flow

The DS4 uses **Bluetooth SSP (Secure Simple Pairing)** with no PIN requirement on modern Bluetooth stacks:

```
1. Host scans for devices (discovers "Wireless Controller")
2. Host initiates L2CAP connection to DS4 BD_ADDR
3. Bluetooth stack performs SSP authentication
4. Host connects L2CAP PSM 0x0011 (HID Control)
5. Host connects L2CAP PSM 0x0013 (HID Interrupt)
6. Host reads Feature Report 0x02 (calibration) -- triggers mode switch
7. DS4 begins sending full 0x11 input reports
```

### 2.3 Link Key and PS4-Style Pairing

When pairing via USB to a PS4 (or host application), the pairing information is exchanged through feature reports:

| Report | Direction | Purpose |
|--------|-----------|---------|
| `0x12` (GET) | DS4 -> Host | Read DS4 MAC (bytes 1-6) and paired Host MAC (bytes 10-15) |
| `0x13` (SET) | Host -> DS4 | Write Host MAC (bytes 1-6) + Link Key (bytes 7-22) |
| `0x14` (SET) | Host -> DS4 | Pairing command: `0x01` = pair, `0x02` = unpair |

**Feature Report 0x12 structure (16 bytes):**
```
Byte 0:     Report ID (0x12)
Bytes 1-6:  DS4 Bluetooth MAC address (6 bytes, reversed byte order)
Bytes 7-9:  Hardware-specific bytes
Bytes 10-15: Paired host Bluetooth MAC address (0x00 if unpaired)
```

**Feature Report 0x13 structure (23 bytes):**
```
Byte 0:     Report ID (0x13)
Bytes 1-6:  Host Bluetooth MAC address to pair with
Bytes 7-22: 16-byte link key for Bluetooth authentication
```

The 16-byte link key is the shared secret used for Bluetooth authentication. This key is transmitted over USB during initial pairing and stored by both devices for subsequent Bluetooth connections.

### 2.4 Linux/macOS Pairing Procedure

On a standard computer using BlueZ or macOS CoreBluetooth:

```
1. Power on the Bluetooth adapter
2. Put DS4 in pairing mode (PS + Share until rapid blinking)
3. Scan for "Wireless Controller"
4. Initiate pairing (no PIN required)
5. Authorize HID service if prompted
6. Trust the device for auto-reconnection
```

**BlueZ configuration note:** The file `/etc/bluetooth/input.conf` may need `UserspaceHID=true` for proper driver loading on Linux.

### 2.5 Reconnection via BD_ADDR Spoofing

The PS4 can be woken from standby by a previously paired DS4. Spoofing the BD_ADDR and class of a paired controller allows programmatic wake:

```bash
# Set adapter to DS4's BD_ADDR and class
sudo hcitool cc <PS4_BD_ADDR>
```

This works because the PS4 checks the incoming BD_ADDR against its list of paired controllers.

---

## 3. Connection Initialization and Mode Switching

### 3.1 Initial Connection State

When a DS4 first connects over Bluetooth, it sends **reduced input reports** using Report ID `0x01` (9-10 bytes, varies by firmware; Report ID not included in this count). These contain only basic stick and button data -- no IMU, no touchpad, no battery information.

### 3.2 Triggering Full Report Mode

To switch the DS4 from reduced `0x01` reports to full `0x11` reports, the host must read a **calibration feature report**:

| Connection | Feature Report | Report ID |
|-----------|---------------|-----------|
| Bluetooth | Calibration | `0x05` (41 bytes: 1 ID + 36 data + 4 CRC) |
| USB | Calibration | `0x02` (37 bytes: 1 ID + 36 data) |
| Dongle | Calibration | `0x02` |

**From ds4drv (hidraw backend):**
```python
class HidrawBluetoothDS4Device(HidrawDS4Device):
    report_size = 78
    valid_report_id = 0x11

    def set_operational(self):
        # Reading feature report 0x02 triggers the mode switch
        self.read_feature_report(0x02, 37)
```

**From ds4drv (raw Bluetooth backend):**
```python
class BluetoothDS4Device(DS4Device):
    def set_operational(self):
        # For raw L2CAP, setting the LED is sufficient to establish
        # bidirectional communication and trigger mode switch
        self.set_led(255, 255, 255)
```

### 3.3 Mode Switch Behavior

```
Before calibration read:    DS4 sends Report 0x01 (reduced, 9-10 bytes + Report ID)
                            No IMU data, no touchpad, no battery

After calibration read:     DS4 sends Reports 0x11-0x19 (full, 78-547 bytes)
                            Full controller state, IMU, touchpad, battery
                            Reports include CRC-32 validation
```

The mode switch is one-way: once triggered, the DS4 does not revert to `0x01` reports until it disconnects and reconnects.

---

## 4. Input Report 0x01 (Reduced Mode)

This truncated report is sent over Bluetooth before the calibration feature report is read. It contains only basic controller state.

### 4.1 Byte Map (Bluetooth 0x01)

The raw data on the HID interrupt channel includes the HID transaction header:

| Byte | Field | Description |
|------|-------|-------------|
| 0 | HID Header | `0xA1` (DATA + INPUT) -- on raw L2CAP only |
| 1 | Report ID | `0x01` |
| 2 | Left Stick X | 0x00 = left, 0x80 = center, 0xFF = right |
| 3 | Left Stick Y | 0x00 = up, 0x80 = center, 0xFF = down |
| 4 | Right Stick X | Same range |
| 5 | Right Stick Y | Same range |
| 6 | Buttons [0] | D-Pad (bits 3:0) + Face buttons (bits 7:4) |
| 7 | Buttons [1] | L1, R1, L2, R2, Share, Options, L3, R3 |
| 8 | Buttons [2] | PS (bit 0), Touchpad Click (bit 1), Counter (bits 7:2) |
| 9 | L2 Trigger | Analog value 0x00-0xFF |
| 10 | R2 Trigger | Analog value 0x00-0xFF |

**Total size:** 9-10 bytes (varies by firmware; Report ID not included in this count, excluding HID header)

**Note:** This report has the same field layout as the first bytes of the USB 0x01 report, but is truncated -- it lacks timestamp, IMU, battery, and touchpad data.

---

## 5. Input Report 0x11 (Full Mode)

This is the primary input report sent over Bluetooth after the calibration feature report has been read. It contains complete controller state including IMU data, touchpad, and battery information, protected by a CRC-32 checksum.

### 5.1 Report Structure Overview

```
Total Bluetooth report: 78 bytes (as seen by HID layer / hidraw)

  [0]      Report ID (0x11)
  [1]      BT Header Byte 1 (flags)
  [2]      BT Header Byte 2 (flags)
  [3-76]   Controller state data (74 bytes, same layout as USB 0x01 bytes 0-63+)
  [74-77]  CRC-32 checksum (4 bytes, little-endian)
```

On raw L2CAP (not hidraw), an additional HID transaction header `0xA1` precedes byte [0], making the total 79 bytes.

### 5.2 Bluetooth Header Bytes

The first two bytes after the Report ID are Bluetooth-specific header/flag bytes that do not exist in the USB report:

**Byte [1] -- BT Flags 1:**
```
Bit 7:   EnableHID -- controller state data is present
Bit 6:   EnableCRC -- CRC-32 checksum is appended
Bits 5-0: Reserved / polling flags
```

Typical value: `0xC0` (both HID and CRC enabled)

**Byte [2] -- BT Flags 2:**
```
Bit 7:   EnableAudio -- audio data is present (for reports 0x11-0x19)
Bits 6-0: Reserved / sequence data
```

Typical value: `0x00` for standard input reports

**Important:** The `EnableHID` bit must be checked before parsing controller state data. If it is not set, the report may contain only audio data. All Bluetooth input reports (except the reduced 0x01) must verify this flag.

### 5.3 Offset Mapping: Bluetooth vs USB

The controller state data within the BT report starts at byte [3], which maps to the USB report starting at byte [1] (after the Report ID). This creates a **+2 byte offset** when comparing field positions between the BT and USB report byte indices.

For code that uses `hidraw` (which strips the HID header but includes the report ID), the BT report is 78 bytes with:
- Byte [0] = Report ID `0x11`
- Bytes [1-2] = BT-specific flags
- Bytes [3+] = Controller data (equivalent to USB bytes [1+])

For code that uses raw L2CAP sockets (as in ds4drv's bluetooth backend), the full frame is 79 bytes with:
- Byte [0] = HID transaction header `0xA1`
- Byte [1] = Report ID `0x11`
- Byte [2] = BT flags 1 (e.g., `0xC0`)
- Bytes [3+] = Controller data

**ds4drv's approach -- stripping the BT header:**
```python
# bluetooth.py: Raw L2CAP -- skip first 3 bytes (HID header + report ID + flags)
buf = zero_copy_slice(self.buf, 3)
return self.parse_report(buf)

# hidraw.py: HID layer -- skip first 2 bytes (report ID + first flag byte)
if self.type == "bluetooth":
    buf = zero_copy_slice(self.buf, 2)
```

After stripping, the same `parse_report()` function works for both USB and Bluetooth data, since the controller state fields align.

### 5.4 Complete Byte Map (BT Input Report 0x11)

This table shows the byte positions as seen in the **hidraw** view (78 bytes total, byte [0] = Report ID).

| BT Byte | USB Byte | Type | Field | Description |
|---------|----------|------|-------|-------------|
| 0 | -- | uint8 | Report ID | `0x11` (BT) vs `0x01` (USB) |
| 1 | -- | uint8 | BT Flags 1 | `0xC0`: EnableHID + EnableCRC |
| 2 | -- | uint8 | BT Flags 2 | `0x00`: No audio |
| 3 | 1 | uint8 | Left Stick X | 0x00=left, 0x80=center, 0xFF=right |
| 4 | 2 | uint8 | Left Stick Y | 0x00=up, 0x80=center, 0xFF=down |
| 5 | 3 | uint8 | Right Stick X | Same range |
| 6 | 4 | uint8 | Right Stick Y | Same range |
| 7 | 5 | uint8 | Buttons [0] | D-Pad (bits 3:0) + Face (bits 7:4) |
| 8 | 6 | uint8 | Buttons [1] | L1, R1, L2, R2, Share, Options, L3, R3 |
| 9 | 7 | uint8 | Buttons [2] + Counter | PS (bit 0), Touchpad (bit 1), Counter (bits 7:2) |
| 10 | 8 | uint8 | L2 Trigger | Analog 0x00-0xFF |
| 11 | 9 | uint8 | R2 Trigger | Analog 0x00-0xFF |
| 12-13 | 10-11 | uint16 | Timestamp | ~5.33 us/unit, LE |
| 14 | 12 | uint8 | Temperature | Sensor temperature |
| 15-16 | 13-14 | int16 | Gyroscope Pitch | Angular velocity X (signed, LE) |
| 17-18 | 15-16 | int16 | Gyroscope Yaw | Angular velocity Y (signed, LE) |
| 19-20 | 17-18 | int16 | Gyroscope Roll | Angular velocity Z (signed, LE) |
| 21-22 | 19-20 | int16 | Accelerometer X | Linear acceleration (signed, LE) |
| 23-24 | 21-22 | int16 | Accelerometer Y | Linear acceleration (signed, LE) |
| 25-26 | 23-24 | int16 | Accelerometer Z | Linear acceleration (signed, LE) |
| 27-31 | 25-29 | uint8[5] | External Data | Extension port / headset data |
| 32 | 30 | uint8 | Power/Status | Battery (bits 3:0) + Flags (bits 7:4) |
| 33 | 31 | uint8 | Status2 | Connection / extension info |
| 34 | 32 | uint8 | Reserved | Unknown / padding |
| 35 | 33 | uint8 | Touch Count | Number of touch data packets (0-4 on BT) |
| 36 | 34 | uint8 | Touch Pkt Counter | Sequence number for touch packet 0 |
| 37 | 35 | uint8 | Touch 0 ID+Active | Finger 0: Active (bit 7=0), ID (bits 6:0) |
| 38 | 36 | uint8 | Touch 0 X [7:0] | Finger 0 X low byte |
| 39 | 37 | uint8 | Touch 0 XY | X[11:8] (bits 3:0) + Y[3:0] (bits 7:4) |
| 40 | 38 | uint8 | Touch 0 Y [11:4] | Finger 0 Y high byte |
| 41 | 39 | uint8 | Touch 1 ID+Active | Finger 1: Active (bit 7=0), ID (bits 6:0) |
| 42 | 40 | uint8 | Touch 1 X [7:0] | Finger 1 X low byte |
| 43 | 41 | uint8 | Touch 1 XY | X[11:8] (bits 3:0) + Y[3:0] (bits 7:4) |
| 44 | 42 | uint8 | Touch 1 Y [11:4] | Finger 1 Y high byte |
| 45 | 43 | uint8 | Touch Pkt Counter 2 | Sequence number for touch packet 1 |
| 46-53 | 44-51 | uint8[8] | Touch Packet 1 | Previous/second touch frame |
| 54 | 52 | uint8 | Touch Pkt Counter 3 | Sequence number for touch packet 2 |
| 55-62 | 53-60 | uint8[8] | Touch Packet 2 | Third touch frame |
| 63 | -- | uint8 | Touch Pkt Counter 4 | BT-only: Fourth touch packet counter |
| 64-71 | -- | uint8[8] | Touch Packet 3 | BT-only: Fourth touch frame |
| 72-73 | 61-62 | uint8[2] | Reserved | `0x00 0x00` or `0x00 0x01` |
| 74-77 | -- | uint8[4] | CRC-32 | Checksum (little-endian) |

**Key differences from USB:**
- Bluetooth supports **4 touch packets** per report (USB supports 3)
- CRC-32 is **mandatory** on Bluetooth (not present on USB input reports)
- BT-specific flag bytes at positions [1] and [2]
- Total size: 78 bytes (BT hidraw) vs 64 bytes (USB)

### 5.5 Button Bitmask Layout

The button layout is identical to USB once you account for the +2 byte offset. See [04-DS4-USB-Protocol Section 2.3](./04-DS4-USB-Protocol.md) for full bitmask documentation.

**Quick reference at BT byte positions:**

**Byte [7] (BT) / Byte [5] (USB) -- D-Pad + Face Buttons:**
```
Bit:    7         6        5       4       3    2    1    0
     +--------+--------+-------+--------+----+----+----+----+
     |Triangle| Circle | Cross | Square |    D-Pad State    |
     +--------+--------+-------+--------+-------------------+
```

D-Pad values: 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=Released

**Byte [8] (BT) / Byte [6] (USB) -- Shoulder/Trigger/System:**
```
Bit:  7    6      5        4      3    2    1    0
    +----+----+---------+-------+----+----+----+----+
    | R3 | L3 | Options | Share | R2 | L2 | R1 | L1 |
    +----+----+---------+-------+----+----+----+----+
```

**Byte [9] (BT) / Byte [7] (USB) -- PS/Touchpad/Counter:**
```
Bit:  7    6    5    4    3    2    1          0
    +----+----+----+----+----+----+----------+--------+
    |        Counter (6 bits)     | Touchpad |   PS   |
    +----+----+----+----+----+----+----------+--------+
```

### 5.6 Power/Status Byte

**Byte [32] (BT) / Byte [30] (USB):**

```
Bits 3:0  Battery Level
          BT (no cable):  0x00-0x08 (0=empty, 8=full)
          BT (charging):  0x01-0x0B (11=full+charging)
Bit 4     USB Cable Connected (0x10)
Bit 5     Headphones Connected (0x20)
Bit 6     Microphone Connected (0x40)
Bit 7     Extension Device Connected (0x80)
```

**Battery percentage calculation:**
```c
bool charging = (status_byte & 0x10) != 0;
int max_value = charging ? 11 : 8;
int battery_raw = status_byte & 0x0F;
int battery_pct = min(battery_raw * 100 / max_value, 100);
```

### 5.7 Touchpad Data Encoding

Each touch entry is 4 bytes (within a 9-byte touch packet that includes a 1-byte counter):

```
Touch entry (4 bytes):
  Byte 0: [bit 7: NotTouching (1=lifted, 0=touching)] [bits 6:0: Finger ID]
  Byte 1: X coordinate [7:0]
  Byte 2: [bits 3:0: X[11:8]] [bits 7:4: Y[3:0]]
  Byte 3: Y coordinate [11:4]

Touchpad resolution: 1920 x 943 pixels (X: 0-1919, Y: 0-942)
```

**Decoding X and Y:**
```c
uint16_t x = buf[1] | ((buf[2] & 0x0F) << 8);   // 12-bit X
uint16_t y = ((buf[2] & 0xF0) >> 4) | (buf[3] << 4);  // 12-bit Y
bool active = (buf[0] & 0x80) == 0;  // Active-low
uint8_t finger_id = buf[0] & 0x7F;
```

---

## 6. Output Report 0x11 (Bluetooth)

The output report controls the DS4's rumble motors, light bar color, light bar flash timing, and audio settings. Over Bluetooth, it requires CRC-32 validation or the controller will ignore it.

### 6.1 Report Structure Overview

```
Bluetooth Output Report (via hidraw): 78 bytes
  [0]      Report ID (0x11)
  [1]      BT Flags / Polling Rate
  [2]      BT Flags 2
  [3]      Feature Enable Flags 1
  [4]      Feature Enable Flags 2
  [5]      Reserved
  [6]      Right Rumble (weak/fast motor)
  [7]      Left Rumble (strong/slow motor)
  [8]      LED Red
  [9]      LED Green
  [10]     LED Blue
  [11]     Flash On Duration
  [12]     Flash Off Duration
  [13-73]  Reserved / Audio settings
  [74-77]  CRC-32 checksum (little-endian)

Raw L2CAP Output Report: 79 bytes
  (Prepend 0xA2 HID header before byte [0])
```

### 6.2 Complete Byte Map (BT Output Report 0x11)

| BT Byte | USB Byte | Field | Description |
|---------|----------|-------|-------------|
| 0 | 0 | Report ID | `0x11` (BT) vs `0x05` (USB) |
| 1 | -- | BT HID Flags | `0xC0 | btPollRate`: EnableCRC (bit 6) + EnableHID (bit 7), with optional poll rate in lower bits |
| 2 | -- | BT Flags 2 | Microphone enable bits (for audio), typically `0x00` for non-audio output |
| 3 | 1 | Feature Enable 1 | Bit flags: rumble (0x01), lightbar (0x02), flash (0x04) |
| 4 | 2 | Feature Enable 2 | `0x04` (typically) |
| 5 | 3 | Reserved | `0x00` |
| 6 | 4 | Right Rumble | Weak/fast motor intensity (0x00-0xFF) |
| 7 | 5 | Left Rumble | Strong/slow motor intensity (0x00-0xFF) |
| 8 | 6 | LED Red | Red channel (0x00-0xFF) |
| 9 | 7 | LED Green | Green channel (0x00-0xFF) |
| 10 | 8 | LED Blue | Blue channel (0x00-0xFF) |
| 11 | 9 | Flash On | LED on duration (0-255, 255 = ~2.5 sec) |
| 12 | 10 | Flash Off | LED off duration (0-255, 255 = ~2.5 sec) |
| 13-21 | -- | Audio Config | Volume L/R, Mic volume, Speaker volume, etc. |
| 22-73 | -- | Reserved | Padding (zeros) |
| 74-77 | -- | CRC-32 | Checksum of header + report data (LE) |

### 6.3 BT Flags Byte [1]

```
Bit 7:   EnableHID (1 = controller state control data present)
Bit 6:   EnableCRC (1 = CRC-32 is appended)
Bits 5-0: Polling rate (0 is clamped to 1; higher = slower polling)
```

Typical value: `0xC0` (both HID and CRC enabled, poll rate = 0)

From DS4Windows:
```csharp
outReportBuffer[1] = (byte)(0xC0 | btPollRate); // input report rate
```

### 6.4 Feature Enable Byte [3]

```
Bit 0: Enable Rumble (0x01)
Bit 1: Enable Lightbar Color (0x02)
Bit 2: Enable Lightbar Flash (0x04)
Bit 3: Enable Headphone Volume Left (0x08)  [DS4Windows uses 0x10]
Bit 4: Enable Headphone Volume Right (0x10) [DS4Windows uses 0x20]
Bit 5: Enable Microphone Volume (0x20)      [DS4Windows uses 0x40]
Bit 6: Enable Speaker Volume (0x40)         [DS4Windows uses 0x80]
Bit 7: Reserved
```

Default value for rumble + LED + flash: `0x07`

**From DS4Windows:**
```csharp
outReportBuffer[3] = outputFeaturesByte; // e.g., 0x07
outReportBuffer[4] = 0x04;              // Additional enable flags
```

### 6.5 Offset Difference from USB

The USB output report uses Report ID `0x05` and has no BT-specific header bytes. The field positions shift by **+2 bytes** on Bluetooth:

| Field | USB Byte (Report 0x05) | BT Byte (Report 0x11) | Shift |
|-------|----------------------|---------------------|-------|
| Feature Enable | 1 | 3 | +2 |
| Reserved | 2 | 4 | +2 |
| Reserved | 3 | 5 | +2 |
| Right Rumble (weak) | 4 | 6 | +2 |
| Left Rumble (strong) | 5 | 7 | +2 |
| LED Red | 6 | 8 | +2 |
| LED Green | 7 | 9 | +2 |
| LED Blue | 8 | 10 | +2 |
| Flash On | 9 | 11 | +2 |
| Flash Off | 10 | 12 | +2 |

**From ds4drv -- shared control() with offset:**
```python
def control(self, big_rumble=0, small_rumble=0,
            led_red=0, led_green=0, led_blue=0,
            flash_led1=0, flash_led2=0):
    if self.type == "bluetooth":
        pkt = bytearray(77)
        pkt[0] = 128    # 0x80 -- EnableHID flag
        pkt[2] = 255    # 0xFF -- Feature enable all
        offset = 2       # BT offset
        report_id = 0x11
    elif self.type == "usb":
        pkt = bytearray(31)
        pkt[0] = 255    # 0xFF -- Feature enable all
        offset = 0       # No offset for USB
        report_id = 0x05

    pkt[offset+3] = min(small_rumble, 255)  # Right/weak motor
    pkt[offset+4] = min(big_rumble, 255)    # Left/strong motor
    pkt[offset+5] = min(led_red, 255)
    pkt[offset+6] = min(led_green, 255)
    pkt[offset+7] = min(led_blue, 255)
    pkt[offset+8] = min(flash_led1, 255)    # Flash on duration
    pkt[offset+9] = min(flash_led2, 255)    # Flash off duration

    self.write_report(report_id, pkt)
```

### 6.6 Sending Output Reports over Bluetooth

Output reports are sent differently depending on the transport:

**Via raw L2CAP (control channel):**
```python
# ds4drv bluetooth backend
HIDP_TRANS_SET_REPORT = 0x50
HIDP_DATA_RTYPE_OUTPUT = 0x02

def write_report(self, report_id, data):
    hid = bytearray((HIDP_TRANS_SET_REPORT | HIDP_DATA_RTYPE_OUTPUT,
                     report_id))
    self.ctl_sock.sendall(hid + data)
```

**Via hidraw (HID layer handles framing):**
```python
def write_report(self, report_id, data):
    hid = bytearray((report_id,))
    self.fd.write(hid + data)
```

### 6.7 Alternative Output Report IDs

While `0x11` is the standard output report, larger reports can combine control data with audio:

| Report ID | Size | Contents |
|-----------|------|----------|
| `0x11` | 78 bytes | Rumble + LED control only |
| `0x15` | 334 bytes | Rumble + LED + audio data |
| `0x17` | 462 bytes | Audio (4 SBC frames) |
| `0x18` | 526 bytes | Audio (6 SBC frames) |
| `0x19` | 547 bytes | Rumble + LED + multi-frame audio |

DS4Windows defaults to `0x11` (78-byte) for output:
```csharp
private const int BT_OUTPUT_REPORT_0x11_LENGTH = 78;
protected const int BT_OUTPUT_REPORT_LENGTH = 334;  // 0x15 length
```

---

## 7. Feature Reports over Bluetooth

Feature reports over Bluetooth differ from USB in several important ways:

1. **Different Report IDs** for the same data (e.g., calibration: `0x05` on BT vs `0x02` on USB)
2. **CRC-32 is mandatory** on most BT feature reports
3. **HID transaction header prefix** is included in CRC calculation
4. **GET REPORT uses `0xA3`** and **SET REPORT uses `0x53`** as the CRC prefix byte

### 7.1 Feature Report Summary

| Function | USB Report ID | BT Report ID | Size (BT) | CRC-32 |
|----------|--------------|--------------|-----------|--------|
| Calibration | `0x02` | `0x05` | 41 bytes | Yes (last 4 bytes) |
| Version/Date | `0xA3` | `0x06` | 49 bytes | Yes |
| MAC Address | `0x12` / `0x81` | `0x09` | 20 bytes | Yes |
| Auth Challenge (set) | -- | `0xF0` | 65 bytes | Yes |
| Auth Response (get) | -- | `0xF1` | 65 bytes | Yes |
| Auth Status (get) | -- | `0xF2` | 17 bytes | Yes |
| Debug Command | `0x08` | `0x08` | 48 bytes | Yes |

### 7.2 Calibration Report (BT 0x05 / USB 0x02)

**Bluetooth Feature Report 0x05 (41 bytes: 1-byte Report ID + 36 bytes data + 4-byte CRC-32):**

> **Gyro calibration field ordering note:** The ordering of the gyro Plus/Minus calibration
> fields (bytes 7-18) differs between USB and Bluetooth. The Bluetooth report uses the
> "paired-per-axis" ordering shown below (PitchPlus, PitchMinus, YawPlus, YawMinus,
> RollPlus, RollMinus). The USB calibration report (0x02) uses a "grouped" ordering
> (PitchPlus, YawPlus, RollPlus, PitchMinus, YawMinus, RollMinus) -- see doc 04.
> DS4Windows implements a `useAltGyroCalib` flag to handle this discrepancy: when set,
> it swaps to the alternative ordering. If calibration values look incorrect,
> try the alternative ordering.

| Byte(s) | Field | Type |
|---------|-------|------|
| 0 | Report ID | `0x05` |
| 1-2 | Gyro Pitch Bias | int16 LE |
| 3-4 | Gyro Yaw Bias | int16 LE |
| 5-6 | Gyro Roll Bias | int16 LE |
| 7-8 | Gyro Pitch Plus | int16 LE |
| 9-10 | Gyro Pitch Minus | int16 LE |
| 11-12 | Gyro Yaw Plus | int16 LE |
| 13-14 | Gyro Yaw Minus | int16 LE |
| 15-16 | Gyro Roll Plus | int16 LE |
| 17-18 | Gyro Roll Minus | int16 LE |
| 19-20 | Gyro Speed Plus | int16 LE |
| 21-22 | Gyro Speed Minus | int16 LE |
| 23-24 | Accel X Plus | int16 LE |
| 25-26 | Accel X Minus | int16 LE |
| 27-28 | Accel Y Plus | int16 LE |
| 29-30 | Accel Y Minus | int16 LE |
| 31-32 | Accel Z Plus | int16 LE |
| 33-34 | Accel Z Minus | int16 LE |
| 35-36 | Unknown | int16 LE |
| 37-40 | CRC-32 | uint32 LE |

**Alternative "grouped" interpretation (bytes 7-18, matching USB doc 04):**

| Byte(s) | Field | Type |
|---------|-------|------|
| 7-8 | Gyro Pitch Plus | int16 LE |
| 9-10 | Gyro Yaw Plus | int16 LE |
| 11-12 | Gyro Roll Plus | int16 LE |
| 13-14 | Gyro Pitch Minus | int16 LE |
| 15-16 | Gyro Yaw Minus | int16 LE |
| 17-18 | Gyro Roll Minus | int16 LE |

**CRC calculation for calibration:**
The CRC is computed over `0xA3` (GET_REPORT header) + bytes [0..36] of the report:

```csharp
// DS4Windows calibration CRC verification
uint calcCrc32 = ~Crc32Algorithm.Compute(new byte[] { 0xA3 });
calcCrc32 = ~Crc32Algorithm.CalculateBasicHash(ref calcCrc32,
    ref calibration, 0, DS4_FEATURE_REPORT_5_LEN - 4);
```

### 7.3 Version/Date Report (BT 0x06 / USB 0xA3)

Contains manufacturing date/time and firmware version information. Over Bluetooth, this is Report ID `0x06` with CRC-32 appended; over USB, it is `0xA3` without CRC.

| Byte(s) | Field |
|---------|-------|
| 0 | Report ID (`0x06`) |
| 1-16 | Date string (e.g., "Aug  3 2013\0\0\0\0\0") |
| 17-32 | Time string (e.g., "07:01:12\0\0\0\0\0\0\0\0") |
| 33-34 | Hardware version major (uint16 LE) |
| 35-36 | Hardware version minor (uint16 LE, must be >= `0x3100` for Remote Play) |
| 37-40 | Software version major (uint32 LE) |
| 41-42 | Software version minor (uint16 LE) |
| 43-44 | Software series (uint16 LE) |
| 45-48 | Code size (uint32 LE) |
| 49-52 | CRC-32 (uint32 LE) |

---

## 8. CRC-32 Calculation

### 8.1 Algorithm

The DS4 uses the standard **CRC-32** algorithm with the polynomial **`0xEDB88320`** (reflected representation of `0x04C11DB7`). This is the same CRC-32 used in Ethernet, PKZIP, and many other protocols (sometimes called "CRC-32b" or "CRC-32/ISO-HDLC").

**Parameters:**
| Parameter | Value |
|-----------|-------|
| Polynomial | `0xEDB88320` (reflected) / `0x04C11DB7` (normal) |
| Initial Value (Seed) | `0xFFFFFFFF` |
| Final XOR | `0xFFFFFFFF` (result is inverted) |
| Input Reflected | Yes |
| Output Reflected | Yes |
| Width | 32 bits |

### 8.2 What Bytes Are Included in the CRC

This is the most critical detail and the most common source of errors: **the HID transaction header byte is included in the CRC calculation**, prepended before the report data.

```
CRC input for INPUT reports:   [0xA1] + [report_id] + [report_data...] (excluding CRC bytes)
CRC input for OUTPUT reports:  [0xA2] + [report_id] + [report_data...] (excluding CRC bytes)
CRC input for GET FEATURE:     [0xA3] + [report_id] + [report_data...] (excluding CRC bytes)
CRC input for SET FEATURE:     [0x53] + [report_id] + [report_data...] (excluding CRC bytes)
```

**The CRC bytes themselves are NOT included in the CRC calculation.** The CRC is stored in the last 4 bytes of the report as a little-endian uint32.

### 8.3 CRC Prefix Byte by Report Direction

| Report Type | HID Transaction | CRC Prefix Byte |
|-------------|----------------|-----------------|
| Input (DS4 -> Host) | DATA + INPUT | `0xA1` |
| Output (Host -> DS4) | DATA + OUTPUT | `0xA2` |
| Feature GET (DS4 -> Host) | GET_REPORT + FEATURE | `0xA3` |
| Feature SET (Host -> DS4) | SET_REPORT + FEATURE | `0x53` |

### 8.4 Step-by-Step CRC Calculation

**For a Bluetooth Input Report 0x11 (78 bytes via hidraw):**

```
Step 1: Prepend the HID header byte
  crc_input = [0xA1] + report[0..73]  (74 bytes from report, excluding last 4 CRC bytes)
  Total CRC input: 75 bytes

Step 2: Compute CRC-32 with seed 0xFFFFFFFF
  crc = CRC32(crc_input)

Step 3: Final XOR with 0xFFFFFFFF
  crc = crc ^ 0xFFFFFFFF

Step 4: Store as little-endian uint32 in bytes [74-77]
  report[74] = crc & 0xFF
  report[75] = (crc >> 8) & 0xFF
  report[76] = (crc >> 16) & 0xFF
  report[77] = (crc >> 24) & 0xFF
```

**For a Bluetooth Output Report 0x11 (78 bytes via hidraw):**

```
Step 1: Build the report (bytes [0..73], CRC bytes [74-77] are placeholders)
Step 2: Prepend CRC prefix
  crc_input = [0xA2] + report[0..73]

Step 3: Compute CRC-32
  crc = CRC32(crc_input) ^ 0xFFFFFFFF

Step 4: Store in last 4 bytes
  report[74..77] = crc as uint32 LE
```

### 8.5 DS4Windows CRC Implementation

The DS4Windows source code demonstrates the CRC computation most clearly:

**Output report CRC (sending to DS4):**
```csharp
// outputBTCrc32Head = new byte[] { 0xA2 };
int len = btOutputPayloadLen;  // typically 78

// Step 1: Compute CRC of the prefix byte 0xA2
uint calcCrc32 = ~Crc32Algorithm.Compute(outputBTCrc32Head);

// Step 2: Continue CRC over the report data (excluding last 4 CRC bytes)
calcCrc32 = ~Crc32Algorithm.CalculateBasicHash(
    ref calcCrc32, ref outputReport, 0, len - 4);

// Step 3: Store result as little-endian uint32
outputReport[len - 4] = (byte)calcCrc32;
outputReport[len - 3] = (byte)(calcCrc32 >> 8);
outputReport[len - 2] = (byte)(calcCrc32 >> 16);
outputReport[len - 1] = (byte)(calcCrc32 >> 24);
```

**Input report CRC verification:**
```csharp
// HamSeed = 2351727372 = ~CRC32(0xA1) -- precomputed seed
// This is equivalent to: CRC32_init(0xFFFFFFFF, [0xA1])

// Extract received CRC from last 4 bytes
uint recvCrc32 = btInputReport[74] |
    (uint)(btInputReport[75] << 8) |
    (uint)(btInputReport[76] << 16) |
    (uint)(btInputReport[77] << 24);

// Calculate expected CRC (using precomputed seed for 0xA1 prefix)
uint calcCrc32 = ~Crc32Algorithm.CalculateFasterBT78Hash(
    ref HamSeed, ref btInputReport, ref crcoffset, ref crcpos);

if (recvCrc32 != calcCrc32) {
    // CRC mismatch -- corrupted data
}
```

**The "HamSeed" optimization:** DS4Windows precomputes the CRC state after processing the `0xA1` prefix byte, storing it as `HamSeed = 2351727372`. This avoids recomputing the CRC of the constant prefix on every input report.

```
HamSeed = 2351727372 (decimal)
         = 0x8C2D2D7C (hex)
         = ~CRC32(seed=0xFFFFFFFF, data=[0xA1])
```

### 8.6 CRC-32 Lookup Table

The standard CRC-32 lookup table (reflected polynomial `0xEDB88320`):

```c
static const uint32_t crc32_table[256] = {
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA,
    0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
    0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
    0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC,
    0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    // ... (full 256-entry table -- see DS4Windows Crc32.cs)
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6,
    0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
};
```

**Basic CRC-32 computation:**
```c
uint32_t crc32_compute(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < length; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return crc ^ 0xFFFFFFFF;
}
```

### 8.7 CRC Validation Failure Handling

DS4Windows implements error counting for CRC validation failures:

```csharp
private const int CRC32_NUM_ATTEMPTS = 10;

// If CRC fails more than 10 consecutive times, disconnect the controller
if (inputReportErrorCount >= CRC32_NUM_ATTEMPTS) {
    // Log and disconnect -- likely a fake/incompatible DS4
    sendOutputReport(true, true);  // Kick the connection
    isDisconnecting = true;
}
```

This handles cases where third-party controllers do not properly implement CRC-32 in their Bluetooth reports.

---

## 9. Authentication Protocol

The DS4 implements a challenge-response authentication protocol used by the PS4 to verify the controller is genuine Sony hardware. This authentication is **not required for basic controller functionality on PC/Mac** but is documented here for completeness.

### 9.1 Authentication Overview

The protocol uses RSA-based digital signatures:

```
1. PS4 sends 256-byte challenge (nonce) to DS4
2. DS4 signs the challenge with its private key
3. DS4 returns signature + serial number + public key + CA signature (1040 bytes)
4. PS4 verifies the signature chain using Sony's CA public key
5. Authentication repeats periodically (~30 seconds)
```

### 9.2 Challenge Phase (PS4 -> DS4)

**SET FEATURE Report 0xF0** (5 packets, 256 bytes total):

| Byte(s) | Field | Description |
|---------|-------|-------------|
| 0 | Report ID | `0xF0` |
| 1 | Sequence Counter | Starts at `0x01`, increments per authentication cycle |
| 2 | Packet Counter | `0x00` through `0x04` (5 packets) |
| 3 | Reserved | `0x00` |
| 4-59 | Challenge Data | 56 bytes per packet (last packet: 32 bytes + 24 padding) |
| 60-63 | CRC-32 | Computed with `0x53` prefix |

Total challenge data: 4 x 56 + 32 = **256 bytes** (the nonce)

### 9.3 Response Phase (DS4 -> PS4)

**GET FEATURE Report 0xF1** (19 packets, 1040 bytes total):

| Byte(s) | Field | Description |
|---------|-------|-------------|
| 0 | Report ID | `0xF1` |
| 1 | Sequence Counter | Matches the challenge sequence |
| 2 | Packet Counter | `0x00` through `0x12` (19 packets) |
| 3 | Reserved | `0x00` |
| 4-59 | Response Data | 56 bytes per packet (last packet: 24 bytes + padding) |
| 60-63 | CRC-32 | Computed with `0xA3` prefix |

**Total response structure (1040 bytes):**
```c
struct ds4_auth_response {
    uint8_t signature[0x100];     // 256 bytes: PSS signature (DS4 private key)
    uint8_t serial_number[0x10];  // 16 bytes: Controller serial number
    uint8_t public_key_n[0x100];  // 256 bytes: DS4 RSA public key (modulus N)
    uint8_t public_key_e[0x100];  // 256 bytes: DS4 RSA public key (exponent E)
    uint8_t ca_signature[0x100];  // 256 bytes: CA signature (Sony's CA private key)
};
```

### 9.4 Status Check

**GET FEATURE Report 0xF2** (authentication readiness):

| Byte(s) | Field | Description |
|---------|-------|-------------|
| 0 | Report ID | `0xF2` |
| 1 | Sequence Counter | Current sequence |
| 2 | Status | `0x01` = not ready, `0x00` = ready |
| 3-12 | Padding | `0x00` |
| 13-16 | CRC-32 | Computed with `0xA3` prefix |

### 9.5 Periodic Re-authentication

The PS4 performs authentication at regular intervals (~30 seconds):

```
Every ~30 seconds:
  5 x SET FEATURE 0xF0 (challenge data)
  2 x GET FEATURE 0xF2 (poll for readiness)
  19 x GET FEATURE 0xF1 (retrieve response)
```

### 9.6 Implications for PC/Mac Usage

- **Authentication is NOT required** for controller input on PC/Mac
- Reading calibration (Feature Report 0x05 on BT) is sufficient to enable full reports
- Some games that communicate directly with the DS4 may attempt authentication
- Third-party controllers that lack Sony's signing keys will fail authentication but still function for standard input

---

## 10. Connection Management

### 10.1 Connection Establishment

The DS4 connection follows this sequence:

```
1. Bluetooth inquiry/scan discovers "Wireless Controller"
2. L2CAP connection to PSM 0x0011 (HID Control)
3. L2CAP connection to PSM 0x0013 (HID Interrupt)
4. Host reads Feature Report (calibration) to trigger full reports
5. DS4 begins streaming Input Report 0x11 on interrupt channel
6. Host sends Output Report 0x11 to set LED / enable feedback
```

### 10.2 Keep-Alive and Idle Behavior

- The DS4 will auto-disconnect after approximately **10 minutes** of inactivity (no button presses)
- The light bar dims gradually before disconnecting
- Sending output reports (even unchanged) can serve as a keep-alive mechanism
- DS4Windows implements a standby watchdog that sends output reports every ~4 seconds:

```csharp
bool haptime = force || standbySw.ElapsedMilliseconds >= 4000L;
```

### 10.3 Disconnection Detection

**Host-side detection:**
- Zero-byte read from the interrupt socket indicates disconnection
- Read timeout (DS4Windows uses 3000 ms for BT) triggers disconnect handling
- CRC-32 failures exceeding threshold (10 consecutive) trigger forced disconnect

**From ds4drv:**
```python
def read_report(self):
    ret = self.int_sock.recv_into(self.buf)
    if ret == 0:
        return  # Disconnection detected
```

**From DS4Windows:**
```csharp
internal const int READ_STREAM_TIMEOUT = 3000;  // 3 second timeout for BT
internal const int WARN_INTERVAL_BT = 500;      // Warn after 500ms gap
```

### 10.4 Manual Disconnection

- **PS Button long-press** (~10 seconds): Powers off the DS4
- **Programmatic disconnect** (Windows): Use `DeviceIoControl` with `IOCTL_BTH_DISCONNECT_DEVICE = 0x41000c`
- **Programmatic disconnect** (macOS): Use `IOBluetoothDevice.closeConnection()`

### 10.5 Reconnection Behavior

After a DS4 has been paired and trusted:

1. Pressing the **PS button** on a sleeping DS4 initiates reconnection
2. The DS4 attempts to connect to the last paired host
3. If the host is available, the Bluetooth stack auto-accepts the incoming connection
4. The DS4 starts in reduced mode (`0x01` reports) until the host reads calibration
5. The host must re-read calibration data after each reconnection to re-enable full reports

### 10.6 Latency Characteristics

| Connection | Typical Latency | Worst Case |
|-----------|----------------|------------|
| USB | ~4 ms | ~8 ms |
| Bluetooth (1 controller) | ~1.25 ms | ~15 ms |
| Bluetooth (2 controllers) | ~2.5 ms | ~20 ms |
| Bluetooth (4 controllers) | ~5 ms | ~35 ms |

Bluetooth can actually achieve **lower latency** than USB for a single controller due to its faster polling rate (~800 Hz vs ~250 Hz). However, worst-case latency is higher due to Bluetooth scheduling jitter.

---

## 11. Audio Reports

The DS4 supports bidirectional audio over Bluetooth using **SBC (Sub-Band Coding)** encoded audio data multiplexed with controller state in extended report formats.

### 11.1 Audio Report Types

| Report ID | Size (bytes) | Direction | Contents |
|-----------|-------------|-----------|----------|
| `0x11` | 78 | Both | Control only (no audio) |
| `0x14` | 270 | Output | Audio data only |
| `0x15` | 334 | Output | Control + audio |
| `0x17` | 462 | Output | Audio (4 SBC frames) |
| `0x18` | 526 | Output | Audio (6 SBC frames) |
| `0x19` | 547 | Both | Control + multi-frame audio |

### 11.2 Audio Multiplexing Flags

The `EnableHID` and `EnableAudio` flag bits in the BT header bytes determine which data sections are present:

| EnableHID | EnableAudio | Contents |
|-----------|------------|----------|
| 1 | 0 | Controller state only |
| 0 | 1 | Audio data only |
| 1 | 1 | Controller state + audio data |
| 0 | 0 | Invalid (no data) |

Controller state data is always placed **before** audio data when both are present.

### 11.3 SBC Audio Format

The SBC header byte encodes audio parameters:

```
Bits 7-6: Sampling frequency
  00 = 16 kHz, 01 = 32 kHz, 10 = 44.1 kHz, 11 = 48 kHz
Bits 5-4: Blocks
  00 = 4, 01 = 8, 10 = 12, 11 = 16
Bits 3-2: Channel mode
  00 = MONO, 01 = DUAL, 10 = STEREO, 11 = JOINT_STEREO
Bit 1: Allocation method
  0 = Loudness, 1 = SNR
Bit 0: Subbands
  0 = 4 subbands, 1 = 8 subbands
```

Audio quality scales with the number of connected controllers:
- 1-2 players: 32 kHz
- 3+ players: 16 kHz

---

## 12. USB vs Bluetooth Comparison

### 12.1 Input Report Comparison

| Aspect | USB (Report 0x01) | Bluetooth (Report 0x11) |
|--------|-------------------|------------------------|
| Report ID | `0x01` | `0x11` |
| Total Size | 64 bytes | 78 bytes (hidraw) / 79 (raw L2CAP) |
| BT Header Bytes | None | 2 bytes (flags at [1]-[2]) |
| Controller Data Offset | Byte [1] | Byte [3] |
| Field Offset Shift | Baseline | +2 bytes from USB |
| Touch Packets | Up to 3 | Up to 4 |
| CRC-32 | Not present | Last 4 bytes, mandatory |
| Rate | ~250 Hz (4 ms) | ~800 Hz (1.25 ms) single controller |
| Mode Switch | Immediate | After reading Feature Report 0x05 |
| Reduced Mode | No | Yes (Report 0x01, basic data only) |

### 12.2 Output Report Comparison

| Aspect | USB (Report 0x05) | Bluetooth (Report 0x11) |
|--------|-------------------|------------------------|
| Report ID | `0x05` | `0x11` |
| Total Size | 32 bytes | 78 bytes (hidraw) / 79 (raw L2CAP) |
| BT Header Bytes | None | 2 bytes (polling + flags) |
| Feature Enable Offset | Byte [1] | Byte [3] |
| Rumble Offset (Right) | Byte [4] | Byte [6] |
| Rumble Offset (Left) | Byte [5] | Byte [7] |
| LED Red Offset | Byte [6] | Byte [8] |
| LED Green Offset | Byte [7] | Byte [9] |
| LED Blue Offset | Byte [8] | Byte [10] |
| Flash On Offset | Byte [9] | Byte [11] |
| Flash Off Offset | Byte [10] | Byte [12] |
| CRC-32 | Not required | Last 4 bytes, mandatory |
| Audio Support | No | Yes (Reports 0x14-0x19) |

### 12.3 Feature Report Comparison

| Function | USB ID | BT ID | USB Size | BT Size | BT CRC |
|----------|--------|-------|----------|---------|--------|
| Calibration | `0x02` | `0x05` | 37 bytes | 41 bytes | Yes |
| Version/Date | `0xA3` | `0x06` | 49 bytes | 53 bytes | Yes |
| MAC Address (read) | `0x12` / `0x81` | `0x09` | 7-16 bytes | 20 bytes | Yes |
| MAC Address (write) | `0x13` / `0x80` | -- | 23 bytes | -- | -- |
| Debug Command | `0x08` | `0x08` | 48 bytes | 48 bytes | Yes |
| Auth Challenge | -- | `0xF0` | -- | 65 bytes | Yes |
| Auth Response | -- | `0xF1` | -- | 65 bytes | Yes |
| Auth Status | -- | `0xF2` | -- | 17 bytes | Yes |

### 12.4 Connection Comparison

| Aspect | USB | Bluetooth |
|--------|-----|-----------|
| Transport | USB 2.0 Full Speed | Bluetooth Classic BR/EDR |
| Protocol | USB HID | HID over L2CAP |
| Channels | 2 endpoints (IN+OUT) | 2 L2CAP PSMs (Control+Interrupt) |
| Pairing | Automatic (plug in) | SSP, link key exchange |
| Authentication | Via Feature Reports 0x12/0x13 | Feature Reports 0xF0/0xF1/0xF2 |
| CRC-32 | Not used for standard reports | Mandatory on BT reports |
| Audio | Not available over USB | Available (SBC encoded) |
| Max Controllers | Limited by USB ports/hubs | Up to 4 per BT adapter |
| Latency (typical) | ~4 ms | ~1.25 ms (single controller) |
| Latency (worst) | ~8 ms | ~15 ms (single controller) |

---

## 13. Code Examples

### 13.1 Parsing a Bluetooth Input Report (Swift)

```swift
import Foundation

struct DS4BluetoothInputReport {
    // BT-specific header
    let reportId: UInt8       // [0] = 0x11
    let btFlags1: UInt8       // [1] = 0xC0 typically
    let btFlags2: UInt8       // [2] = 0x00 typically

    // Analog sticks
    let leftStickX: UInt8     // [3]
    let leftStickY: UInt8     // [4]
    let rightStickX: UInt8    // [5]
    let rightStickY: UInt8    // [6]

    // Buttons
    let buttons0: UInt8       // [7]  D-Pad + Face
    let buttons1: UInt8       // [8]  Shoulders + System
    let buttons2: UInt8       // [9]  PS + Touchpad + Counter

    // Triggers
    let l2Trigger: UInt8      // [10]
    let r2Trigger: UInt8      // [11]

    // Timestamp
    let timestamp: UInt16     // [12-13] LE

    // IMU (signed 16-bit LE)
    let gyroPitch: Int16      // [15-16]
    let gyroYaw: Int16        // [17-18]
    let gyroRoll: Int16       // [19-20]
    let accelX: Int16         // [21-22]
    let accelY: Int16         // [23-24]
    let accelZ: Int16         // [25-26]

    // Status
    let batteryAndStatus: UInt8  // [32]

    // Touch
    let touchCount: UInt8     // [35]

    var enableHID: Bool { (btFlags1 & 0x80) != 0 }
    var enableCRC: Bool { (btFlags1 & 0x40) != 0 }
    var enableAudio: Bool { (btFlags2 & 0x80) != 0 }
}

func parseBTInputReport(_ data: Data) -> DS4BluetoothInputReport? {
    guard data.count >= 78 else { return nil }
    guard data[0] == 0x11 else { return nil }

    // Verify EnableHID flag
    guard (data[1] & 0x80) != 0 else { return nil }

    // Verify CRC-32 if EnableCRC is set
    if (data[1] & 0x40) != 0 {
        let receivedCRC = UInt32(data[74]) |
                         (UInt32(data[75]) << 8) |
                         (UInt32(data[76]) << 16) |
                         (UInt32(data[77]) << 24)

        // Build CRC input: 0xA1 prefix + report bytes [0..73]
        var crcInput = Data([0xA1])
        crcInput.append(data[0..<74])

        let calculatedCRC = crc32(crcInput)
        guard receivedCRC == calculatedCRC else {
            print("CRC-32 mismatch: received=\(String(format: "0x%08X", receivedCRC)) " +
                  "calculated=\(String(format: "0x%08X", calculatedCRC))")
            return nil
        }
    }

    return DS4BluetoothInputReport(
        reportId: data[0],
        btFlags1: data[1],
        btFlags2: data[2],
        leftStickX: data[3],
        leftStickY: data[4],
        rightStickX: data[5],
        rightStickY: data[6],
        buttons0: data[7],
        buttons1: data[8],
        buttons2: data[9],
        l2Trigger: data[10],
        r2Trigger: data[11],
        timestamp: UInt16(data[12]) | (UInt16(data[13]) << 8),
        gyroPitch: Int16(bitPattern: UInt16(data[15]) | (UInt16(data[16]) << 8)),
        gyroYaw: Int16(bitPattern: UInt16(data[17]) | (UInt16(data[18]) << 8)),
        gyroRoll: Int16(bitPattern: UInt16(data[19]) | (UInt16(data[20]) << 8)),
        accelX: Int16(bitPattern: UInt16(data[21]) | (UInt16(data[22]) << 8)),
        accelY: Int16(bitPattern: UInt16(data[23]) | (UInt16(data[24]) << 8)),
        accelZ: Int16(bitPattern: UInt16(data[25]) | (UInt16(data[26]) << 8)),
        batteryAndStatus: data[32],
        touchCount: data[35]
    )
}
```

### 13.2 Constructing a Bluetooth Output Report (Swift)

```swift
func buildBTOutputReport(
    rightRumble: UInt8 = 0,
    leftRumble: UInt8 = 0,
    ledRed: UInt8 = 0,
    ledGreen: UInt8 = 0,
    ledBlue: UInt8 = 0,
    flashOn: UInt8 = 0,
    flashOff: UInt8 = 0
) -> Data {
    var report = Data(count: 78)

    // Report ID
    report[0] = 0x11

    // BT flags: EnableHID + EnableCRC, poll rate = 0
    report[1] = 0xC0

    // BT flags 2
    report[2] = 0x00

    // Feature enable: rumble (0x01) + lightbar (0x02) + flash (0x04)
    report[3] = 0x07

    // Additional flags
    report[4] = 0x04

    // Rumble
    report[6] = rightRumble    // Right/weak/fast motor
    report[7] = leftRumble     // Left/strong/slow motor

    // LED color
    report[8] = ledRed
    report[9] = ledGreen
    report[10] = ledBlue

    // Flash timing
    report[11] = flashOn       // 255 = ~2.5 seconds
    report[12] = flashOff      // 255 = ~2.5 seconds

    // Calculate CRC-32
    // CRC input: 0xA2 prefix + report bytes [0..73]
    var crcInput = Data([0xA2])
    crcInput.append(report[0..<74])

    let crc = crc32(crcInput)
    report[74] = UInt8(crc & 0xFF)
    report[75] = UInt8((crc >> 8) & 0xFF)
    report[76] = UInt8((crc >> 16) & 0xFF)
    report[77] = UInt8((crc >> 24) & 0xFF)

    return report
}
```

### 13.3 CRC-32 Implementation (Swift)

```swift
/// Standard CRC-32 lookup table (polynomial 0xEDB88320, reflected)
private let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var crc = UInt32(i)
        for _ in 0..<8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc >>= 1
            }
        }
        table[i] = crc
    }
    return table
}()

/// Compute CRC-32 checksum for DS4 Bluetooth reports
/// - Parameter data: The bytes to checksum (including HID header prefix)
/// - Returns: CRC-32 value (already finalized with XOR)
func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        let index = Int((crc ^ UInt32(byte)) & 0xFF)
        crc = (crc >> 8) ^ crc32Table[index]
    }
    return crc ^ 0xFFFFFFFF
}

/// Verify CRC-32 of a received Bluetooth input report
/// - Parameter report: The complete 78-byte BT input report (hidraw format)
/// - Returns: true if CRC is valid
func verifyCRC32(report: Data) -> Bool {
    guard report.count >= 78 else { return false }

    // Extract received CRC (last 4 bytes, little-endian)
    let received = UInt32(report[74]) |
                  (UInt32(report[75]) << 8) |
                  (UInt32(report[76]) << 16) |
                  (UInt32(report[77]) << 24)

    // Compute expected CRC: prefix 0xA1 + report[0..73]
    var crcData = Data([0xA1])
    crcData.append(report[0..<74])
    let expected = crc32(crcData)

    return received == expected
}
```

### 13.4 Complete Connection Flow (Pseudocode)

```
// 1. Discover and connect
device = bluetooth_scan_for("Wireless Controller")
ctrl_channel = l2cap_connect(device, PSM=0x0011)  // HID Control
intr_channel = l2cap_connect(device, PSM=0x0013)  // HID Interrupt

// 2. Enable full reports by reading calibration
calibration = get_feature_report(ctrl_channel, report_id=0x05)
verify_crc32(calibration, prefix=0xA3)
apply_calibration(calibration)

// 3. Set initial LED color (also confirms bidirectional communication)
output_report = build_bt_output_report(ledRed=0, ledGreen=0, ledBlue=255)
write_output_report(ctrl_channel, output_report)

// 4. Main input loop
while connected:
    report = read_from(intr_channel)

    // Check report type
    if report[1] != 0x11:
        continue  // Not a full input report

    // Verify CRC-32
    if not verify_crc32(report):
        error_count += 1
        if error_count >= 10:
            disconnect()
            break
        continue

    error_count = 0

    // Check EnableHID flag
    if (report[1] & 0x80) == 0:
        continue  // No controller state in this report

    // Parse controller state (offset +2 from USB layout)
    state = parse_controller_state(report, offset=3)

    // Process inputs...
    handle_input(state)

// 5. Cleanup
close(intr_channel)
close(ctrl_channel)
```

### 13.5 Sending Output via Raw L2CAP (Python)

```python
import socket
import struct

L2CAP_PSM_HIDP_CTRL = 0x11
HIDP_TRANS_SET_REPORT = 0x50
HIDP_DATA_RTYPE_OUTPUT = 0x02

def crc32_ds4(data: bytes) -> int:
    """Standard CRC-32 (same as zlib.crc32)."""
    import zlib
    return zlib.crc32(data) & 0xFFFFFFFF

def build_bt_output(rumble_right=0, rumble_left=0,
                     led_r=0, led_g=0, led_b=0,
                     flash_on=0, flash_off=0) -> bytes:
    """Build a 77-byte output report payload (excluding report ID prefix)."""
    pkt = bytearray(77)
    pkt[0] = 0xC0       # BT flags: EnableHID + EnableCRC
    pkt[2] = 0x07       # Feature enable: rumble + LED + flash
    pkt[3] = 0x04       # Additional flags
    pkt[5] = rumble_right & 0xFF
    pkt[6] = rumble_left & 0xFF
    pkt[7] = led_r & 0xFF
    pkt[8] = led_g & 0xFF
    pkt[9] = led_b & 0xFF
    pkt[10] = flash_on & 0xFF
    pkt[11] = flash_off & 0xFF

    # Calculate CRC-32 over: 0xA2 + 0x11 + pkt[0..72]
    crc_input = bytes([0xA2, 0x11]) + bytes(pkt[:73])
    crc = crc32_ds4(crc_input)

    # Append CRC as last 4 bytes (little-endian)
    struct.pack_into('<I', pkt, 73, crc)

    return bytes(pkt)

def send_output_report(ctl_sock, report_id, data):
    """Send an output report via the HID Control channel."""
    hid_header = bytes([HIDP_TRANS_SET_REPORT | HIDP_DATA_RTYPE_OUTPUT,
                        report_id])
    ctl_sock.sendall(hid_header + data)

# Usage:
ctl_sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET,
                          socket.BTPROTO_L2CAP)
ctl_sock.connect((ds4_addr, L2CAP_PSM_HIDP_CTRL))

payload = build_bt_output(led_r=0, led_g=0, led_b=255)
send_output_report(ctl_sock, 0x11, payload)
```

---

## Sources

- [Sony DualShock 4 -- Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Sony DualShock 4/Data Structures -- Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [DS4-BT -- PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-BT)
- [DS4-USB -- PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-USB)
- [DualShock 4 -- GIMX Wiki](https://gimx.fr/wiki/index.php?title=DualShock_4)
- [DualShock 4 -- Eleccelerator Wiki](http://eleccelerator.com/wiki/index.php?title=DualShock_4)
- [dsremap Reverse Engineering Documentation](https://dsremap.readthedocs.io/en/latest/reverse.html)
- [Sony DualShock -- Gentoo Wiki](https://wiki.gentoo.org/wiki/Sony_DualShock)
- ds4drv (chrippa) -- `ds4drv/backends/bluetooth.py`, `ds4drv/device.py`
- ds4drv (clearpathrobotics) -- `ds4drv/backends/bluetooth.py`
- DS4Windows -- `DS4Library/DS4Device.cs`, `DS4Library/Crc32.cs`
