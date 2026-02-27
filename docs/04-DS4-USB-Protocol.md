# DS4 USB Protocol Reference

> Comprehensive reverse-engineered protocol documentation for the Sony DualShock 4 (DS4) controller.
> Compiled from psdevwiki, controllers.fandom.com, GIMX wiki, eleccelerator wiki, ds4drv, DS4Windows, and original firmware analysis.

> **Size Convention:** All report sizes in this document INCLUDE the Report ID byte unless explicitly noted otherwise.

---

## Table of Contents

1. [USB Device Descriptors](#1-usb-device-descriptors)
2. [Input Report 0x01 (USB)](#2-input-report-0x01-usb)
3. [Output Report 0x05 (USB)](#3-output-report-0x05-usb)
4. [Feature Reports](#4-feature-reports)
5. [HID Report Descriptor Analysis](#5-hid-report-descriptor-analysis)
6. [Data Type Reference Tables](#6-data-type-reference-tables)
7. [CRC32 Requirements](#7-crc32-requirements)
8. [Bluetooth Protocol Differences](#8-bluetooth-protocol-differences)
9. [Code Examples](#9-code-examples)

---

## 1. USB Device Descriptors

### Device Identification

| Field | Value | Description |
|-------|-------|-------------|
| Vendor ID (VID) | `0x054C` | Sony Corporation |
| Product ID (PID) v1 | `0x05C4` | DualShock 4 [CUH-ZCT1x] |
| Product ID (PID) v2 | `0x09CC` | DualShock 4 [CUH-ZCT2x] (Pro/Slim) |
| Product ID (Dongle) | `0x0BA0` | DualShock 4 USB Wireless Adapter |
| Product ID (Dongle DFU) | `0x0BA1` | Dongle in DFU mode |
| USB Version | 2.0 | Full Speed |
| Device Class | `0x00` | Defined at interface level |
| Max Packet Size | 64 bytes | Endpoint 0 |
| Power | Bus-powered | 500 mA max |

### Interface Descriptor

| Field | Value | Description |
|-------|-------|-------------|
| Interface Number | 0 | Primary HID interface |
| Interface Class | `0x03` | HID (Human Interface Device) |
| Interface Subclass | `0x00` | No subclass |
| Interface Protocol | `0x00` | None |
| Number of Endpoints | 2 | IN + OUT |

### Endpoint Descriptors

| Endpoint | Address | Type | Direction | Max Packet | Interval |
|----------|---------|------|-----------|------------|----------|
| EP1 | `0x84` | Interrupt | IN (Device to Host) | 64 bytes | 5 ms |
| EP2 | `0x03` | Interrupt | OUT (Host to Device) | 64 bytes | 5 ms |

The controller generates input reports at approximately 250 Hz (~4 ms interval), delivering a 64-byte input report on each poll.

---

## 2. Input Report 0x01 (USB)

The USB input report is 64 bytes total (including the Report ID byte). All multi-byte values are **little-endian**. Signed values use **two's complement** representation.

### 2.1 Complete Byte Map

| Byte(s) | Type | Field | Description |
|---------|------|-------|-------------|
| 0 | uint8 | Report ID | Always `0x01` |
| 1 | uint8 | Left Stick X | 0x00 = full left, 0x80 = center, 0xFF = full right |
| 2 | uint8 | Left Stick Y | 0x00 = full up, 0x80 = center, 0xFF = full down |
| 3 | uint8 | Right Stick X | 0x00 = full left, 0x80 = center, 0xFF = full right |
| 4 | uint8 | Right Stick Y | 0x00 = full up, 0x80 = center, 0xFF = full down |
| 5 | uint8 | Buttons [0] | D-Pad (bits 3:0) + Face buttons (bits 7:4) |
| 6 | uint8 | Buttons [1] | Shoulder/trigger/stick/share/options buttons |
| 7 | uint8 | Buttons [2] + Counter | PS (bit 0), Touchpad Click (bit 1), Counter (bits 7:2) |
| 8 | uint8 | L2 Trigger | 0x00 = released, 0xFF = fully pressed |
| 9 | uint8 | R2 Trigger | 0x00 = released, 0xFF = fully pressed |
| 10-11 | uint16 | Timestamp | Increments per report (~5.33 us per unit) |
| 12 | uint8 | Temperature | Sensor temperature (internal) |
| 13-14 | int16 | Gyroscope Pitch | Angular velocity around X axis (signed) |
| 15-16 | int16 | Gyroscope Yaw | Angular velocity around Y axis (signed) |
| 17-18 | int16 | Gyroscope Roll | Angular velocity around Z axis (signed) |
| 19-20 | int16 | Accelerometer X | Linear acceleration (signed) |
| 21-22 | int16 | Accelerometer Y | Linear acceleration (signed) |
| 23-24 | int16 | Accelerometer Z | Linear acceleration (signed) |
| 25-29 | uint8[5] | External Data | Extension port / headset data |
| 30 | uint8 | Power/Status | Battery level (bits 3:0) + Status flags (bits 7:4) |
| 31 | uint8 | Status2 | Connection / extension info |
| 32 | uint8 | Reserved | Unknown / padding |
| 33 | uint8 | Touch Count | Number of touch data packets (typically 0-3) |
| 34 | uint8 | Touch Pkt Counter | Sequence number for current touch packet |
| 35 | uint8 | Touch 0 ID+Active | Finger 0: Active (bit 7 = 0), ID (bits 6:0) |
| 36 | uint8 | Touch 0 X [7:0] | Finger 0 X coordinate low byte |
| 37 | uint8 | Touch 0 XY | Finger 0 X[11:8] (bits 3:0) + Y[3:0] (bits 7:4) |
| 38 | uint8 | Touch 0 Y [11:4] | Finger 0 Y coordinate high byte |
| 39 | uint8 | Touch 1 ID+Active | Finger 1: Active (bit 7 = 0), ID (bits 6:0) |
| 40 | uint8 | Touch 1 X [7:0] | Finger 1 X coordinate low byte |
| 41 | uint8 | Touch 1 XY | Finger 1 X[11:8] (bits 3:0) + Y[3:0] (bits 7:4) |
| 42 | uint8 | Touch 1 Y [11:4] | Finger 1 Y coordinate high byte |
| 43 | uint8 | Touch Pkt Counter 2 | Second touch packet sequence number |
| 44-51 | uint8[8] | Touch Packet 2 | Previous/second touch frame (same format as bytes 35-42) |
| 52 | uint8 | Touch Pkt Counter 3 | Third touch packet sequence number |
| 53-60 | uint8[8] | Touch Packet 3 | Third touch frame |
| 61-63 | uint8[3] | Padding | Zero padding |

### 2.2 Analog Sticks

All stick axes are unsigned 8-bit values (0-255) with a nominal center of `0x80` (128).

```
       0x00 (Up/Left)
         |
         |
0x00 ---0x80--- 0xFF
(Left)   |     (Right)
         |
       0xFF (Down/Right)
```

| Stick | X Byte | Y Byte | Center | Min | Max |
|-------|--------|--------|--------|-----|-----|
| Left  | 1 | 2 | 0x80 | 0x00 | 0xFF |
| Right | 3 | 4 | 0x80 | 0x00 | 0xFF |

**Deadzone Notes:**
- Physical stick variance means center may report 0x7E-0x82 at rest
- Typical firmware deadzone: none (raw values reported)
- Software deadzone of ~5-10 units recommended for application use

### 2.3 Button Bitmask Layout

#### Byte 5: D-Pad + Face Buttons

```
Bit:    7         6        5       4       3    2    1    0
     +--------+--------+-------+--------+----+----+----+----+
     |Triangle| Circle | Cross | Square |    D-Pad State    |
     +--------+--------+-------+--------+-------------------+
```

**D-Pad State (bits 3:0)** -- Hat Switch encoding:

| Value | Direction | DpadUp | DpadRight | DpadDown | DpadLeft |
|-------|-----------|--------|-----------|----------|----------|
| 0 | North | 1 | 0 | 0 | 0 |
| 1 | North-East | 1 | 1 | 0 | 0 |
| 2 | East | 0 | 1 | 0 | 0 |
| 3 | South-East | 0 | 1 | 1 | 0 |
| 4 | South | 0 | 0 | 1 | 0 |
| 5 | South-West | 0 | 0 | 1 | 1 |
| 6 | West | 0 | 0 | 0 | 1 |
| 7 | North-West | 1 | 0 | 0 | 1 |
| 8 | Released | 0 | 0 | 0 | 0 |

**Face Buttons (bits 7:4):**

| Bit | Mask | Button |
|-----|------|--------|
| 4 | `0x10` | Square |
| 5 | `0x20` | Cross (X) |
| 6 | `0x40` | Circle (O) |
| 7 | `0x80` | Triangle |

#### Byte 6: Shoulder, Trigger, Stick, Share, Options

```
Bit:  7    6      5        4      3    2    1    0
    +----+----+---------+-------+----+----+----+----+
    | R3 | L3 | Options | Share | R2 | L2 | R1 | L1 |
    +----+----+---------+-------+----+----+----+----+
```

| Bit | Mask | Button |
|-----|------|--------|
| 0 | `0x01` | L1 |
| 1 | `0x02` | R1 |
| 2 | `0x04` | L2 (digital; also has analog at byte 8) |
| 3 | `0x08` | R2 (digital; also has analog at byte 9) |
| 4 | `0x10` | Share |
| 5 | `0x20` | Options |
| 6 | `0x40` | L3 (Left Stick Press) |
| 7 | `0x80` | R3 (Right Stick Press) |

#### Byte 7: PS Button, Touchpad Click, Counter

```
Bit:  7    6    5    4    3    2    1          0
    +----+----+----+----+----+----+----------+--------+
    |        Counter (6 bits)     | Touchpad |   PS   |
    +----+----+----+----+----+----+----------+--------+
```

| Bit | Mask | Field |
|-----|------|-------|
| 0 | `0x01` | PS Button (Home) |
| 1 | `0x02` | Touchpad Click (physical press) |
| 7:2 | `0xFC` | Frame Counter (6-bit, wraps 0-63) |

### 2.4 L2/R2 Trigger Analog Values

| Byte | Field | Range | Description |
|------|-------|-------|-------------|
| 8 | L2 Trigger | 0x00 - 0xFF | 0 = released, 255 = fully depressed |
| 9 | R2 Trigger | 0x00 - 0xFF | 0 = released, 255 = fully depressed |

The trigger buttons have both digital (byte 6 bits 2-3) and analog (bytes 8-9) representations. The digital bits activate at approximately 30% pull.

### 2.5 Timestamp

**Bytes 10-11** (uint16, little-endian):

The timestamp is a 16-bit counter that increments at approximately 188 units per report at full USB polling rate. Each unit represents ~5.33 microseconds.

```
timestamp_microseconds = raw_value * 16 / 3
```

The counter wraps around at `0xFFFF`. To compute elapsed time between reports:

```
if (current >= previous):
    delta = current - previous
else:
    delta = 0xFFFF - previous + current + 1

elapsed_us = delta * 16 / 3
```

### 2.6 Gyroscope Data (IMU Angular Velocity)

**Bytes 13-18** (three int16 values, little-endian, signed):

| Bytes | Axis | Positive Direction |
|-------|------|--------------------|
| 13-14 | Pitch (X) | Tilt forward (top away from player) |
| 15-16 | Yaw (Y) | Rotate clockwise (viewed from above) |
| 17-18 | Roll (Z) | Tilt right (clockwise viewed from behind) |

**Raw Data Format:**
- Signed 16-bit integers (range: -32768 to +32767)
- Resolution: 16 LSB per degree per second (after calibration)
- To convert to degrees/sec: `angular_velocity = calibrated_value / 16.0`

**Reading the raw bytes (little-endian signed):**
```c
int16_t gyroPitch = (int16_t)(buf[13] | (buf[14] << 8));
int16_t gyroYaw   = (int16_t)(buf[15] | (buf[16] << 8));
int16_t gyroRoll  = (int16_t)(buf[17] | (buf[18] << 8));
```

**Calibration Application:**
```
calibrated = (raw - bias) * (gyroSpeed2x * GYRO_RES_IN_DEG_SEC) / (plus - minus)
```

Where `GYRO_RES_IN_DEG_SEC = 16` and calibration values come from Feature Report 0x02.

### 2.7 Accelerometer Data

**Bytes 19-24** (three int16 values, little-endian, signed):

| Bytes | Axis | Positive Direction |
|-------|------|--------------------|
| 19-20 | Accel X | Right |
| 21-22 | Accel Y | Up (away from Earth) |
| 23-24 | Accel Z | Toward player (out of back of controller) |

**Raw Data Format:**
- Signed 16-bit integers
- Resolution: 8192 LSB per g (after calibration)
- At rest: Accel Y ~ +8192 (1g from gravity)
- To convert to g: `acceleration_g = calibrated_value / 8192.0`

**Reading the raw bytes:**
```c
int16_t accelX = (int16_t)(buf[19] | (buf[20] << 8));
int16_t accelY = (int16_t)(buf[21] | (buf[22] << 8));
int16_t accelZ = (int16_t)(buf[23] | (buf[24] << 8));
```

### 2.8 Battery Level and Status

**Byte 30:**

```
Bit:  7          6       5           4         3    2    1    0
    +----------+-------+-----------+----------+----+----+----+----+
    | Reserved | Mic   | Headphone | USB Cable|    Battery Level   |
    +----------+-------+-----------+----------+--------------------+
```

| Bits | Mask | Field | Description |
|------|------|-------|-------------|
| 3:0 | `0x0F` | Battery Level | 0-8 when on battery, 0-11 when cable connected |
| 4 | `0x10` | Cable Connected | 1 = USB data cable connected |
| 5 | `0x20` | Headphones | 1 = headphones connected (3.5mm jack) |
| 6 | `0x40` | Microphone | 1 = microphone connected |
| 7 | `0x80` | Extension | 1 = external device connected |

**Battery Level Calculation:**

```
if (cable_connected):
    max_value = 11
else:
    max_value = 8

battery_percent = min(100, raw_level * 100 / max_value)
```

**Byte 31** -- Secondary Status:
- Value `0x00` = controller synced/operational
- Non-zero values indicate connection issues or pairing states
- Used by Sony Wireless Adapter to detect sync status

### 2.9 Touchpad Data

The DS4 touchpad is a capacitive surface supporting up to 2 simultaneous finger contacts.

**Touchpad Specifications:**

| Property | Value |
|----------|-------|
| Resolution X | 0 - 1919 (1920 points) |
| Resolution Y | 0 - 942 (943 points) |
| Max Fingers | 2 simultaneous |
| Physical Size | ~62 x 28 mm |
| Coordinate Origin | Top-Left (0,0) |

**Touch Data Layout (per touch packet -- 9 bytes):**

Each USB input report contains up to 3 touch data packets at bytes 33-60. The first (most current) packet is at bytes 34-42. Each packet is 9 bytes.

| Relative Offset | Field | Description |
|-----------------|-------|-------------|
| 0 | Packet Counter | Incrementing sequence number |
| 1 | Finger 0 ID + Active | Bit 7: Active (0=touching, 1=not), Bits 6:0: Tracking ID |
| 2 | Finger 0 X low | X coordinate bits [7:0] |
| 3 | Finger 0 XY | X[11:8] in bits [3:0], Y[3:0] in bits [7:4] |
| 4 | Finger 0 Y high | Y coordinate bits [11:4] |
| 5 | Finger 1 ID + Active | Bit 7: Active (0=touching, 1=not), Bits 6:0: Tracking ID |
| 6 | Finger 1 X low | X coordinate bits [7:0] |
| 7 | Finger 1 XY | X[11:8] in bits [3:0], Y[3:0] in bits [7:4] |
| 8 | Finger 1 Y high | Y coordinate bits [11:4] |

**Decoding Touch Coordinates:**

```c
// Finger 0 (bytes 35-38 in absolute report offset)
bool     touch0_active = (buf[35] & 0x80) == 0;  // bit 7 clear = active
uint8_t  touch0_id     =  buf[35] & 0x7F;         // 7-bit tracking ID
uint16_t touch0_x      = ((buf[37] & 0x0F) << 8) | buf[36];  // 12-bit X
uint16_t touch0_y      = (buf[38] << 4) | ((buf[37] & 0xF0) >> 4);  // 12-bit Y

// Finger 1 (bytes 39-42 in absolute report offset)
bool     touch1_active = (buf[39] & 0x80) == 0;
uint8_t  touch1_id     =  buf[39] & 0x7F;
uint16_t touch1_x      = ((buf[41] & 0x0F) << 8) | buf[40];
uint16_t touch1_y      = (buf[42] << 4) | ((buf[41] & 0xF0) >> 4);
```

**Touch Tracking ID:**
- The 7-bit ID (0-127) increments each time a new finger touch begins
- The ID remains constant while a finger is held down
- Used to correlate touch-began and touch-ended events

**Touch Active Flag:**
- Bit 7 of the ID byte: `0` = finger is touching, `1` = finger not touching
- Inverted logic: the "inactive" bit is set when NOT touching

---

## 3. Output Report 0x05 (USB)

The USB output report controls the controller's rumble motors, light bar LED, and light bar flash pattern. The report is 32 bytes (Report ID + 31 bytes of payload).

### 3.1 Complete Byte Map

| Byte | Type | Field | Description |
|------|------|-------|-------------|
| 0 | uint8 | Report ID | Always `0x05` |
| 1 | uint8 | Feature Flags | Bit flags to enable specific features |
| 2 | uint8 | Feature Flags 2 | Additional flags (typically `0x04`) |
| 3 | uint8 | Reserved | Padding (0x00) |
| 4 | uint8 | Rumble Right (Weak) | Light/fast motor intensity: 0x00 - 0xFF |
| 5 | uint8 | Rumble Left (Strong) | Heavy/slow motor intensity: 0x00 - 0xFF |
| 6 | uint8 | LED Red | Light bar red channel: 0x00 - 0xFF |
| 7 | uint8 | LED Green | Light bar green channel: 0x00 - 0xFF |
| 8 | uint8 | LED Blue | Light bar blue channel: 0x00 - 0xFF |
| 9 | uint8 | Flash On Duration | Light bar on-time (255 = ~2.5 seconds) |
| 10 | uint8 | Flash Off Duration | Light bar off-time (255 = ~2.5 seconds) |
| 11-18 | uint8[8] | I2C Extension Data | Data for extension port devices |
| 19 | uint8 | Volume Left | Headphone left channel volume |
| 20 | uint8 | Volume Right | Headphone right channel volume |
| 21 | uint8 | Volume Mic | Microphone volume |
| 22 | uint8 | Volume Speaker | Internal speaker volume |
| 23-24 | uint8[2] | Audio Config | Audio routing configuration |
| 25-31 | uint8[7] | Padding | Zero padding |

### 3.2 Feature Flags (Byte 1)

```
Bit:  7      6       5         4          3        2       1         0
    +------+------+---------+---------+--------+-------+---------+--------+
    |Speaker|Mic   |HP Right |HP Left  |ExtWrite| Flash |Lightbar | Rumble |
    | Vol   |Vol   |Vol      |Vol      |        |       |         |        |
    +------+------+---------+---------+--------+-------+---------+--------+
```

| Bit | Mask | Feature |
|-----|------|---------|
| 0 | `0x01` | Enable rumble motor update |
| 1 | `0x02` | Enable light bar color update |
| 2 | `0x04` | Enable light bar flash update |
| 3 | `0x08` | Enable extension port write |
| 4 | `0x10` | Enable headphone left volume |
| 5 | `0x20` | Enable headphone right volume |
| 6 | `0x40` | Enable microphone volume |
| 7 | `0x80` | Enable speaker volume |

**Common Flag Values:**
- `0x07` = Rumble + Lightbar + Flash (default for most applications)
- `0xF7` = All features enabled
- `0x03` = Rumble + Lightbar (used by some third-party controllers)

### 3.3 Rumble Motors

The DS4 contains two rumble motors with different characteristics:

| Motor | Byte | Characteristics |
|-------|------|-----------------|
| Right (Weak/Light/Fast) | 4 | Small motor, higher frequency vibration |
| Left (Strong/Heavy/Slow) | 5 | Large motor, lower frequency, stronger vibration |

- Range: 0x00 (off) to 0xFF (maximum intensity)
- Setting both to 0x00 stops rumble
- Motors can be independently controlled

### 3.4 Light Bar LED

| Byte | Channel | Range | Description |
|------|---------|-------|-------------|
| 6 | Red | 0x00 - 0xFF | Red intensity (0 = off, 255 = max) |
| 7 | Green | 0x00 - 0xFF | Green intensity |
| 8 | Blue | 0x00 - 0xFF | Blue intensity |

**Default Player Colors (PS4 assignment):**

| Player | Red | Green | Blue |
|--------|-----|-------|------|
| 1 | 0x00 | 0x00 | 0x40 | (Blue) |
| 2 | 0x40 | 0x00 | 0x00 | (Red) |
| 3 | 0x00 | 0x40 | 0x00 | (Green) |
| 4 | 0x20 | 0x00 | 0x20 | (Pink) |

### 3.5 Light Bar Flash

| Byte | Field | Description |
|------|-------|-------------|
| 9 | Flash On Duration | Time LED stays ON (units of ~10ms, 255 = ~2.5s) |
| 10 | Flash Off Duration | Time LED stays OFF |

- Setting both to `0x00` disables flashing (LED stays solid)
- The flash pattern repeats continuously
- To stop flashing: send two output reports (once to set flash values to 0, once more to ensure solid LED)

### 3.6 Audio/Volume Settings

| Byte | Field | Description |
|------|-------|-------------|
| 19 | HP Left Volume | Left headphone channel (0-255) |
| 20 | HP Right Volume | Right headphone channel (0-255) |
| 21 | Mic Volume | Microphone input volume (0-255) |
| 22 | Speaker Volume | Internal speaker output (0-255) |

Audio routing is controlled via Feature Report 0xE0 (see Section 4).

---

## 4. Feature Reports

Feature reports are read/written via HID Get Feature / Set Feature requests (or `ioctl` on Linux). These provide configuration, calibration, pairing, and firmware data.

### 4.1 Summary Table

| Report ID | Size (bytes) | Direction | Usage Page | Description |
|-----------|-------------|-----------|------------|-------------|
| 0x02 | 37 | GET | `0xFF00` | Calibration Data |
| 0x04 | 37 | GET/SET | `0xFF00` | Unknown (possibly secondary calibration) |
| 0x08 | 4 | SET | `0xFF00` | Flash memory read position |
| 0x10 | 5 | GET/SET | `0xFF00` | Unknown |
| 0x11 | 3 | GET | `0xFF00` | Flash memory data read |
| 0x12 | 16 | GET/SET | `0xFF02` | Pairing information (MAC addresses) |
| 0x13 | 23 | SET | `0xFF02` | Set pairing data (host MAC + link key) |
| 0x14 | 17 | GET | `0xFF05` | Unknown |
| 0x15 | 45 | GET | `0xFF05` | Unknown |
| 0x80 | 7 | GET/SET | `0xFF80` | Unknown (purpose not fully understood; may vary by firmware) |
| 0x81 | 7 | GET | `0xFF80` | MAC Address |
| 0x82 | 6 | GET | `0xFF80` | Unknown |
| 0x83 | 2 | GET | `0xFF80` | Unknown |
| 0x84 | 5 | GET | `0xFF80` | Unknown |
| 0x85 | 7 | GET | `0xFF80` | Unknown |
| 0x86 | 7 | GET | `0xFF80` | Unknown |
| 0x87 | 36 | GET | `0xFF80` | Unknown |
| 0x88 | 35 | GET | `0xFF80` | Unknown |
| 0x89 | 3 | GET | `0xFF80` | Unknown |
| 0x90 | 6 | GET | `0xFF80` | Unknown |
| 0x91 | 4 | GET | `0xFF80` | Unknown |
| 0x92 | 4 | GET | `0xFF80` | Unknown |
| 0x93 | 13 | GET | `0xFF80` | Unknown |
| 0xA0 | 7 | GET/SET | `0xFF80` | Test command |
| 0xA1 | 2 | SET | `0xFF80` | Bluetooth enable/disable |
| 0xA2 | 2 | SET | `0xFF80` | DFU mode activation |
| 0xA3 | 49 | GET | `0xFF80` | Firmware/Hardware Version Info |
| 0xA4 | 14 | GET | `0xFF80` | Unknown |
| 0xA5 | 22 | GET | `0xFF80` | Unknown |
| 0xA6 | 22 | GET | `0xFF80` | Unknown |
| 0xA7 | 2 | GET | Various | Unknown |
| 0xA8 | 2 | GET | Various | Unknown |
| 0xA9 | 9 | GET | Various | Unknown |
| 0xAA | 2 | GET | Various | Unknown |
| 0xAB | 58 | GET | Various | Unknown |
| 0xAC | 58 | GET | Various | Unknown |
| 0xAD | 12 | GET | Various | Unknown |
| 0xAE | 2 | GET | Various | AC Power State |
| 0xAF | 3 | GET | Various | Audio Chip Identifier (e.g., 0x1801 = WM1801) |
| 0xB0 | 64 | GET | Various | Unknown |
| 0xF0 | 64 | GET/SET | `0xFF80` | Authentication challenge |
| 0xF1 | 64 | GET/SET | `0xFF80` | Authentication response |
| 0xF2 | 16 | GET | `0xFF80` | Authentication status |

### 4.2 Report 0x02 -- Calibration Data

**Size:** 37 bytes (1 byte Report ID + 36 bytes data)
**Direction:** GET (read from device)

This is the most critical feature report. Reading it on Bluetooth triggers the switch from basic input report (0x01, 9-10 bytes) to extended input reports (0x11, 78 bytes).

> **Transport note:** On Bluetooth, the calibration report ID is `0x05` (not `0x02` as
> on USB). However, the hidraw layer transparently maps USB report ID `0x02` to BT
> report ID `0x05`, so code using hidraw can use `0x02` for both transports.

#### Byte Layout

> **Gyro calibration field ordering note:** The ordering of the gyro Plus/Minus calibration
> fields (bytes 7-18) differs between USB and Bluetooth, and even between driver
> implementations on the same transport. The USB report uses the "grouped" ordering shown
> below (all Plus values, then all Minus values: PitchPlus, YawPlus, RollPlus, PitchMinus,
> YawMinus, RollMinus). The Bluetooth calibration report (0x05) uses a "paired" ordering
> (PitchPlus, PitchMinus, YawPlus, YawMinus, RollPlus, RollMinus) -- see doc 05. The Linux
> kernel `hid-playstation.c` driver uses the paired-per-axis ordering for USB as well.
> DS4Windows implements a `useAltGyroCalib` flag to handle this discrepancy: when set, it
> swaps to the paired-per-axis interpretation. If calibration values look incorrect,
> try the alternative ordering.

| Byte(s) | Type | Field |
|---------|------|-------|
| 0 | uint8 | Report ID (0x02) |
| 1-2 | int16 | Gyro Pitch Bias |
| 3-4 | int16 | Gyro Yaw Bias |
| 5-6 | int16 | Gyro Roll Bias |
| 7-8 | int16 | Gyro Pitch Plus (positive range calibration) |
| 9-10 | int16 | Gyro Yaw Plus |
| 11-12 | int16 | Gyro Roll Plus |
| 13-14 | int16 | Gyro Pitch Minus (negative range calibration) |
| 15-16 | int16 | Gyro Yaw Minus |
| 17-18 | int16 | Gyro Roll Minus |
| 19-20 | int16 | Gyro Speed Plus |
| 21-22 | int16 | Gyro Speed Minus |
| 23-24 | int16 | Accel X Plus |
| 25-26 | int16 | Accel X Minus |
| 27-28 | int16 | Accel Y Plus |
| 29-30 | int16 | Accel Y Minus |
| 31-32 | int16 | Accel Z Plus |
| 33-34 | int16 | Accel Z Minus |
| 35-36 | int16 | Unknown |

**Alternative "paired-per-axis" interpretation (bytes 7-18):**

| Byte(s) | Type | Field |
|---------|------|-------|
| 7-8 | int16 | Gyro Pitch Plus |
| 9-10 | int16 | Gyro Pitch Minus |
| 11-12 | int16 | Gyro Yaw Plus |
| 13-14 | int16 | Gyro Yaw Minus |
| 15-16 | int16 | Gyro Roll Plus |
| 17-18 | int16 | Gyro Roll Minus |

#### Applying Calibration

**Gyroscope calibration (per axis):**

```
gyroSpeed2x = gyroSpeedPlus + gyroSpeedMinus
sensNumer   = gyroSpeed2x * 16    // 16 = GYRO_RES_IN_DEG_SEC
sensDenom   = axisPlus - axisMinus

calibrated_value = (raw - bias) * sensNumer / sensDenom
degrees_per_sec  = calibrated_value / 16.0
```

**Accelerometer calibration (per axis):**

```
accelRange = axisPlus - axisMinus
accelBias  = axisPlus - accelRange / 2
sensNumer  = 2 * 8192    // 8192 = ACC_RES_PER_G
sensDenom  = accelRange

calibrated_value = (raw - accelBias) * sensNumer / sensDenom
g_force          = calibrated_value / 8192.0
```

**Known Issue:** Some DS4 v1 controllers have an inverted yaw calibration value. If `yawSensNumer > 0` but `yawSensDenom < 0` while the other axes have positive denominators, negate the yaw denominator.

### 4.3 Report 0x12 -- Pairing Information (MAC Addresses)

**Size:** 16 bytes (1 byte Report ID + 15 bytes data)
**Direction:** GET/SET

| Byte(s) | Field |
|---------|-------|
| 0 | Report ID (0x12) |
| 1-6 | Controller MAC Address (reversed byte order) |
| 7-9 | Padding / Unknown |
| 10-15 | Host MAC Address (reversed byte order) |

**Byte Reversal:** The MAC address bytes are stored in reverse order. For example, MAC `28:51:65:11:AE:A4` is stored as `A4:AE:11:65:51:28`.

### 4.4 Report 0x81 -- MAC Address

**Size:** 7 bytes (1 byte Report ID + 6 bytes data)
**Direction:** GET

Returns the controller's Bluetooth MAC address in reversed byte order. Used by ds4drv's USB backend to identify the controller:

```python
addr = read_feature_report(0x81, 6)[1:]   # Skip report ID
addr = ["{:02x}".format(c) for c in addr]
addr = ":".join(reversed(addr)).upper()    # Reverse byte order
```

### 4.5 Report 0xA3 -- Firmware/Hardware Version Info

**Size:** 49 bytes (1 byte Report ID + 48 bytes data)
**Direction:** GET

| Byte(s) | Type | Field |
|---------|------|-------|
| 0 | uint8 | Report ID (0xA3) |
| 1-16 | char[16] | Build Date string (e.g., "Sep 21 2018") |
| 17-32 | char[16] | Build Time string (e.g., "04:50:51") |
| 33-34 | uint16 | Hardware Version (major.minor) |
| 35-38 | uint32 | Software Version (major) |
| 39-40 | uint16 | Software Version (minor) |
| 41-42 | uint16 | Software Series |
| 43-46 | uint32 | Code Size |
| 47-48 | uint16 | Unknown |

### 4.6 Report 0x08 -- Flash Memory Read Position

**Size:** 4 bytes (1 byte Report ID + 3 bytes data)
**Direction:** SET

| Byte | Field |
|------|-------|
| 0 | Report ID (0x08) |
| 1 | Always 0xFF |
| 2-3 | Flash offset (little-endian, range 0x0000 - 0x07FF) |

Sets the read pointer for subsequent Report 0x11 reads. Flash mirror is 0x800 bytes (2048 bytes). Known locations:
- `0x01E6`: IMU calibration data
- `0x06F6`: Bluetooth MAC address

### 4.7 Report 0x13 -- Set Pairing Data

**Size:** 23 bytes (1 byte Report ID + 22 bytes data)
**Direction:** SET

| Byte(s) | Field |
|---------|-------|
| 0 | Report ID (0x13) |
| 1-6 | Host MAC Address (reversed byte order) |
| 7-22 | Link Key (16 bytes) |

### 4.8 Authentication Reports (0xF0, 0xF1, 0xF2)

These reports implement the PS4 authentication challenge-response protocol:

| Report | Direction | Purpose |
|--------|-----------|---------|
| 0xF0 | SET | Send authentication challenge page |
| 0xF1 | GET | Read authentication response page |
| 0xF2 | GET | Read authentication status |

The authentication uses RSA-based cryptography. On a genuine PS4 console, the DS4 must pass authentication to be fully functional.

---

## 5. HID Report Descriptor Analysis

The following analysis is based on the descriptor in `dualshock4hid.h`.

### 5.1 Descriptor Structure Overview

```
Collection (Application) - Game Pad
  |
  +-- Input Report (ID 0x01) - 64 bytes
  |     +-- 4x 8-bit Axes (X, Y, Z, Rz)          = Left Stick X/Y, Right Stick X/Y
  |     +-- 1x 4-bit Hat Switch (0-7)              = D-Pad
  |     +-- 14x 1-bit Buttons (Button 1-14)        = All digital buttons
  |     +-- 1x 6-bit Vendor Usage (0x20)           = Counter / padding
  |     +-- 2x 8-bit Axes (Rx, Ry)                 = L2 / R2 triggers
  |     +-- 54x 8-bit Vendor Usage (0x21)           = IMU, touchpad, battery, etc.
  |
  +-- Output Report (ID 0x05) - 32 bytes
  |     +-- 31x 8-bit Vendor Usage (0x22)           = Rumble, LED, audio
  |
  +-- Feature Reports
        +-- ID 0x04: 36 bytes, Usage 0x23 (Vendor 0xFF00)
        +-- ID 0x02: 36 bytes, Usage 0x24 (Vendor 0xFF00) [Calibration]
        +-- ID 0x08:  3 bytes, Usage 0x25 (Vendor 0xFF00)
        +-- ID 0x10:  4 bytes, Usage 0x26 (Vendor 0xFF00)
        +-- ID 0x11:  2 bytes, Usage 0x27 (Vendor 0xFF00)
        +-- ID 0x12: 15 bytes, Usage 0x21 (Vendor 0xFF02) [MAC Addresses]
        +-- ID 0x13: 22 bytes, Usage 0x22 (Vendor 0xFF02) [Pairing]
        +-- ID 0x14: 16 bytes, Usage 0x20 (Vendor 0xFF05)
        +-- ID 0x15: 44 bytes, Usage 0x21 (Vendor 0xFF05)
        +-- ID 0x80:  6 bytes, Usage 0x20 (Vendor 0xFF80)
        +-- ID 0x81:  6 bytes, Usage 0x21 (Vendor 0xFF80) [MAC Address]
        +-- ID 0x82:  5 bytes, Usage 0x22 (Vendor 0xFF80)
        +-- ID 0x83:  1 byte,  Usage 0x23 (Vendor 0xFF80)
        +-- ID 0x84:  4 bytes, Usage 0x24 (Vendor 0xFF80)
        +-- ID 0x85:  6 bytes, Usage 0x25 (Vendor 0xFF80)
        +-- ID 0x86:  6 bytes, Usage 0x26 (Vendor 0xFF80)
        +-- ID 0x87: 35 bytes, Usage 0x27 (Vendor 0xFF80)
        +-- ID 0x88: 34 bytes, Usage 0x28 (Vendor 0xFF80)
        +-- ID 0x89:  2 bytes, Usage 0x29 (Vendor 0xFF80)
        +-- ID 0x90:  5 bytes, Usage X    (Vendor 0xFF80)
        +-- ID 0x91:  3 bytes, Usage Y    (Vendor 0xFF80)
        +-- ID 0x92:  3 bytes, Usage Z    (Vendor 0xFF80)
        +-- ID 0x93: 12 bytes, Usage Rx   (Vendor 0xFF80)
        +-- ID 0xA0:  6 bytes, Usage Vx   (Vendor 0xFF80)
        +-- ID 0xA1:  1 byte,  Usage Vy   (Vendor 0xFF80)
        +-- ID 0xA2:  1 byte,  Usage Vz   (Vendor 0xFF80)
        +-- ID 0xA3: 48 bytes, Usage Vbrx (Vendor 0xFF80) [Firmware Info]
        +-- ID 0xA4: 13 bytes, Usage Vbry (Vendor 0xFF80)
        +-- ID 0xA5: 21 bytes, Usage Vbrz (Vendor 0xFF80)
        +-- ID 0xA6: 21 bytes, Usage Vno  (Vendor 0xFF80)
        +-- ID 0xF0: 63 bytes, Usage Feature Notification (Vendor 0xFF80) [Auth]
        +-- ID 0xF1: 63 bytes, Usage Resolution Multiplier (Vendor 0xFF80) [Auth]
        +-- ID 0xF2: 15 bytes, Usage 0x49 (Vendor 0xFF80) [Auth Status]
        +-- ID 0xA7:  1 byte
        +-- ID 0xA8:  1 byte
        +-- ID 0xA9:  8 bytes
        +-- ID 0xAA:  1 byte
        +-- ID 0xAB: 57 bytes
        +-- ID 0xAC: 57 bytes
        +-- ID 0xAD: 11 bytes
        +-- ID 0xAE:  1 byte  [AC Power State]
        +-- ID 0xAF:  2 bytes [Audio Chip ID]
        +-- ID 0xB0: 63 bytes
```

### 5.2 Input Report Bit Layout (HID Descriptor Perspective)

The HID descriptor defines the Input Report as:

| Bits | HID Usage | Actual Mapping |
|------|-----------|----------------|
| 0-7 | X (0x30) | Left Stick X |
| 8-15 | Y (0x31) | Left Stick Y |
| 16-23 | Z (0x32) | Right Stick X |
| 24-31 | Rz (0x35) | Right Stick Y |
| 32-35 | Hat Switch (0x39) | D-Pad (4-bit, 0-7 + null) |
| 36-49 | Button 1-14 | 14 digital buttons |
| 50-55 | Vendor 0x20 (6-bit) | Frame counter + PS/Touchpad bits |
| 56-63 | Rx (0x33) | L2 Trigger |
| 64-71 | Ry (0x34) | R2 Trigger |
| 72-503 | Vendor 0x21 (54 bytes) | IMU data, touchpad, battery, etc. |

**Total Input Report:** 1 byte Report ID + 63 bytes data = 64 bytes.

### 5.3 Button Mapping (HID Button Numbers)

The HID descriptor defines 14 buttons (Button 1 through Button 14):

| HID Button | Physical Button | Byte.Bit |
|------------|----------------|----------|
| 1 | Square | 5.4 |
| 2 | Cross | 5.5 |
| 3 | Circle | 5.6 |
| 4 | Triangle | 5.7 |
| 5 | L1 | 6.0 |
| 6 | R1 | 6.1 |
| 7 | L2 (digital) | 6.2 |
| 8 | R2 (digital) | 6.3 |
| 9 | Share | 6.4 |
| 10 | Options | 6.5 |
| 11 | L3 | 6.6 |
| 12 | R3 | 6.7 |
| 13 | PS | 7.0 |
| 14 | Touchpad Click | 7.1 |

---

## 6. Data Type Reference Tables

### 6.1 Input Report 0x01 Quick Reference (USB)

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0 | 1 | uint8 | Report ID (0x01) |
| 1 | 1 | uint8 | Left Stick X |
| 2 | 1 | uint8 | Left Stick Y |
| 3 | 1 | uint8 | Right Stick X |
| 4 | 1 | uint8 | Right Stick Y |
| 5 | 1 | uint8 | D-Pad[3:0] + Square[4] + Cross[5] + Circle[6] + Triangle[7] |
| 6 | 1 | uint8 | L1[0] + R1[1] + L2d[2] + R2d[3] + Share[4] + Options[5] + L3[6] + R3[7] |
| 7 | 1 | uint8 | PS[0] + TPad[1] + Counter[7:2] |
| 8 | 1 | uint8 | L2 Trigger (analog) |
| 9 | 1 | uint8 | R2 Trigger (analog) |
| 10 | 2 | uint16 | Timestamp (LE) |
| 12 | 1 | uint8 | Temperature |
| 13 | 2 | int16 | Gyroscope Pitch (LE) |
| 15 | 2 | int16 | Gyroscope Yaw (LE) |
| 17 | 2 | int16 | Gyroscope Roll (LE) |
| 19 | 2 | int16 | Accelerometer X (LE) |
| 21 | 2 | int16 | Accelerometer Y (LE) |
| 23 | 2 | int16 | Accelerometer Z (LE) |
| 25 | 5 | uint8[5] | External / reserved |
| 30 | 1 | uint8 | Battery[3:0] + Cable[4] + HP[5] + Mic[6] + Ext[7] |
| 31 | 1 | uint8 | Status flags |
| 32 | 1 | uint8 | Reserved |
| 33 | 1 | uint8 | Touch packet count |
| 34 | 1 | uint8 | Touch packet 0 counter |
| 35 | 1 | uint8 | Touch 0 Finger 0 (active[7] + ID[6:0]) |
| 36 | 1 | uint8 | Touch 0 Finger 0 X[7:0] |
| 37 | 1 | uint8 | Touch 0 Finger 0 X[11:8][3:0] + Y[3:0][7:4] |
| 38 | 1 | uint8 | Touch 0 Finger 0 Y[11:4] |
| 39 | 1 | uint8 | Touch 0 Finger 1 (active[7] + ID[6:0]) |
| 40 | 1 | uint8 | Touch 0 Finger 1 X[7:0] |
| 41 | 1 | uint8 | Touch 0 Finger 1 X[11:8][3:0] + Y[3:0][7:4] |
| 42 | 1 | uint8 | Touch 0 Finger 1 Y[11:4] |
| 43 | 1 | uint8 | Touch packet 1 counter |
| 44-51 | 8 | -- | Touch packet 1 (same format as 35-42) |
| 52 | 1 | uint8 | Touch packet 2 counter |
| 53-60 | 8 | -- | Touch packet 2 (same format as 35-42) |
| 61-63 | 3 | uint8[3] | Padding |

### 6.2 Output Report 0x05 Quick Reference (USB)

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0 | 1 | uint8 | Report ID (0x05) |
| 1 | 1 | uint8 | Feature flags |
| 2 | 1 | uint8 | Feature flags 2 (typically 0x04) |
| 3 | 1 | uint8 | Reserved |
| 4 | 1 | uint8 | Rumble Right (weak motor) |
| 5 | 1 | uint8 | Rumble Left (strong motor) |
| 6 | 1 | uint8 | LED Red |
| 7 | 1 | uint8 | LED Green |
| 8 | 1 | uint8 | LED Blue |
| 9 | 1 | uint8 | Flash On Duration |
| 10 | 1 | uint8 | Flash Off Duration |
| 11-18 | 8 | uint8[8] | I2C Extension data |
| 19 | 1 | uint8 | Headphone Left Volume |
| 20 | 1 | uint8 | Headphone Right Volume |
| 21 | 1 | uint8 | Mic Volume |
| 22 | 1 | uint8 | Speaker Volume |
| 23-24 | 2 | uint8[2] | Audio configuration |
| 25-31 | 7 | uint8[7] | Padding |

### 6.3 Calibration Report 0x02 Quick Reference

> **Note:** See Section 4.2 for discussion of the gyro calibration field ordering
> discrepancy between USB and Bluetooth. The table below shows the "grouped" ordering
> (all-Plus-then-all-Minus). The alternative "paired-per-axis" ordering is also documented
> in Section 4.2.

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0 | 1 | uint8 | Report ID (0x02) |
| 1-2 | 2 | int16 | Gyro Pitch Bias |
| 3-4 | 2 | int16 | Gyro Yaw Bias |
| 5-6 | 2 | int16 | Gyro Roll Bias |
| 7-8 | 2 | int16 | Gyro Pitch Plus |
| 9-10 | 2 | int16 | Gyro Yaw Plus |
| 11-12 | 2 | int16 | Gyro Roll Plus |
| 13-14 | 2 | int16 | Gyro Pitch Minus |
| 15-16 | 2 | int16 | Gyro Yaw Minus |
| 17-18 | 2 | int16 | Gyro Roll Minus |
| 19-20 | 2 | int16 | Gyro Speed Plus |
| 21-22 | 2 | int16 | Gyro Speed Minus |
| 23-24 | 2 | int16 | Accel X Plus |
| 25-26 | 2 | int16 | Accel X Minus |
| 27-28 | 2 | int16 | Accel Y Plus |
| 29-30 | 2 | int16 | Accel Y Minus |
| 31-32 | 2 | int16 | Accel Z Plus |
| 33-34 | 2 | int16 | Accel Z Minus |
| 35-36 | 2 | int16 | Unknown |

---

## 7. CRC32 Requirements

### 7.1 USB vs Bluetooth

| Transport | CRC Required? | Details |
|-----------|--------------|---------|
| USB Input Reports | **No** | No CRC verification needed |
| USB Output Reports | **No** | No CRC appended |
| USB Feature Reports | **No** | No CRC |
| BT Input Reports (0x11+) | **Yes** | Last 4 bytes are CRC32 |
| BT Output Reports (0x11+) | **Yes** | Last 4 bytes must contain CRC32 |
| BT Feature Report 0x05 | **Yes** | Bluetooth calibration includes CRC |

### 7.2 CRC32 Algorithm

The DS4 uses standard CRC-32 with the following parameters:

| Parameter | Value |
|-----------|-------|
| Polynomial | `0xEDB88320` (reversed representation of `0x04C11DB7`) |
| Initial Value (Seed) | `0xFFFFFFFF` |
| Final XOR | `0xFFFFFFFF` (result is inverted) |
| Byte Order | Little-endian (LSB first in report) |

### 7.3 Bluetooth CRC Computation

For Bluetooth output reports, the CRC is computed over a synthetic header followed by the report data (excluding the last 4 CRC bytes):

```
CRC Input = [0xA2] + report_data[0 .. len-5]
```

The `0xA2` byte is the Bluetooth HID transaction header for output reports. It is NOT part of the actual report payload but must be included in the CRC computation.

For Bluetooth input reports, the header byte is `0xA1`:

```
CRC Input = [0xA1] + report_data[0 .. len-5]
```

### 7.4 CRC Placement

The 4-byte CRC is written in little-endian format at the end of the report:

```
report[len-4] = (crc >>  0) & 0xFF;
report[len-3] = (crc >>  8) & 0xFF;
report[len-2] = (crc >> 16) & 0xFF;
report[len-1] = (crc >> 24) & 0xFF;
```

### 7.5 CRC32 Lookup Table

Standard CRC-32 lookup table (polynomial `0xEDB88320`):

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
    // ... (full 256-entry table omitted for brevity)
    // Use standard CRC-32 table generation with polynomial 0xEDB88320
};
```

---

## 8. Bluetooth Protocol Differences

### 8.1 Report ID Mapping

| USB Report | BT Report | Size | Notes |
|------------|-----------|------|-------|
| 0x01 (Input) | 0x01 (Basic) | 9-10 bytes (varies by firmware; Report ID not included) | Truncated: sticks, buttons, triggers only |
| 0x01 (Input) | 0x11 (Extended) | 78 bytes | Full data + CRC; activated by reading calibration |
| 0x05 (Output) | 0x11 (Output) | 78 bytes | Full output + CRC |
| 0x02 (Calibration) | 0x05 (Calibration) | 41 bytes | Calibration data + CRC |
| 0x12 (MAC) | 0x12 (MAC) | 16 bytes | Same format |

### 8.2 Bluetooth Extended Input Report 0x11

The Bluetooth extended input report is 78 bytes total. The state data begins at byte offset 3 (after the 2 control bytes):

```
BT Report 0x11 layout:
  [0]    Report ID (0x11)
  [1]    BT HID Flags: 0xC0 = EnableCRC (bit 6) | EnableHID (bit 7),
         with optional poll rate in lower bits
  [2]    BT Flags 2: Microphone enable bits (for audio), typically 0x00
  [3..N] Same as USB Report 0x01 bytes [1..N]
  [74-77] CRC-32 (4 bytes, little-endian)
```

To parse the extended BT report using the same parser as USB, skip the first 2 bytes (or read from offset +2 relative to USB offsets).

### 8.3 Bluetooth Output Report 0x11

```
BT Output Report 0x11 (78 bytes):
  [0]    Report ID (0x11)
  [1]    BT HID Flags: 0xC0 = EnableCRC (bit 6) | EnableHID (bit 7),
         with optional poll rate in lower bits
  [2]    BT Flags 2: Microphone enable bits (for audio), typically 0x00
         for non-audio output
  [3]    Feature flags (same as USB byte 1)
  [4]    Feature flags 2 (same as USB byte 2)
  [5]    Reserved
  [6]    Rumble Right (weak motor)
  [7]    Rumble Left (strong motor)
  [8]    LED Red
  [9]    LED Green
  [10]   LED Blue
  [11]   Flash On Duration
  [12]   Flash Off Duration
  [13-73] Padding
  [74-77] CRC-32
```

### 8.4 Activating Extended Reports

On Bluetooth, the controller initially sends only basic 9-10 byte reports (varies by firmware; Report ID 0x01). To activate extended 78-byte reports (Report ID 0x11):

1. Read Feature Report 0x02 (calibration data)
2. The controller switches to sending Report ID 0x11 automatically

This also applies via the `hidraw` interface: performing a HID Get Feature for Report 0x02 triggers the switch.

### 8.5 Additional Bluetooth Report Types

| Report ID | Size | Description |
|-----------|------|-------------|
| 0x11 | 78 | Standard extended input (state data only) |
| 0x12 | 142 | State + audio data |
| 0x13 | 206 | State + more audio |
| 0x14 | 270 | State + more audio |
| 0x15 | 334 | State + more audio |
| 0x16 | 398 | State + more audio |
| 0x17 | 462 | State + more audio |
| 0x18 | 526 | State + more audio |
| 0x19 | 547 | Maximum size report |

All extended BT reports share the same state data structure in the first ~34 bytes; larger reports carry SBC-encoded audio data for the controller's speaker.

---

## 9. Code Examples

### 9.1 Parsing an Input Report (C)

```c
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

typedef struct {
    // Analog sticks (0-255, center=128)
    uint8_t left_stick_x;
    uint8_t left_stick_y;
    uint8_t right_stick_x;
    uint8_t right_stick_y;

    // Triggers (0-255)
    uint8_t l2_trigger;
    uint8_t r2_trigger;

    // D-Pad
    bool dpad_up, dpad_down, dpad_left, dpad_right;

    // Face buttons
    bool square, cross, circle, triangle;

    // Shoulder buttons
    bool l1, r1, l2_button, r2_button;

    // Stick buttons
    bool l3, r3;

    // System buttons
    bool share, options, ps, touchpad_click;

    // Frame counter (0-63)
    uint8_t frame_counter;

    // Timestamp (microseconds since last)
    uint16_t timestamp_raw;

    // Gyroscope (raw signed values)
    int16_t gyro_pitch, gyro_yaw, gyro_roll;

    // Accelerometer (raw signed values)
    int16_t accel_x, accel_y, accel_z;

    // Battery
    uint8_t battery_level;
    bool    cable_connected;
    bool    headphones;
    bool    microphone;

    // Touchpad
    struct {
        bool     active;
        uint8_t  id;
        uint16_t x;
        uint16_t y;
    } touch[2];

} DS4InputReport;

void ds4_parse_input_report(const uint8_t *buf, DS4InputReport *report) {
    // Sticks
    report->left_stick_x  = buf[1];
    report->left_stick_y  = buf[2];
    report->right_stick_x = buf[3];
    report->right_stick_y = buf[4];

    // Triggers
    report->l2_trigger = buf[8];
    report->r2_trigger = buf[9];

    // D-Pad (byte 5, lower nibble)
    uint8_t dpad = buf[5] & 0x0F;
    report->dpad_up    = (dpad == 0 || dpad == 1 || dpad == 7);
    report->dpad_right = (dpad == 1 || dpad == 2 || dpad == 3);
    report->dpad_down  = (dpad == 3 || dpad == 4 || dpad == 5);
    report->dpad_left  = (dpad == 5 || dpad == 6 || dpad == 7);

    // Face buttons (byte 5, upper nibble)
    report->square   = (buf[5] & 0x10) != 0;
    report->cross    = (buf[5] & 0x20) != 0;
    report->circle   = (buf[5] & 0x40) != 0;
    report->triangle = (buf[5] & 0x80) != 0;

    // Shoulder/trigger/stick buttons (byte 6)
    report->l1        = (buf[6] & 0x01) != 0;
    report->r1        = (buf[6] & 0x02) != 0;
    report->l2_button = (buf[6] & 0x04) != 0;
    report->r2_button = (buf[6] & 0x08) != 0;
    report->share     = (buf[6] & 0x10) != 0;
    report->options   = (buf[6] & 0x20) != 0;
    report->l3        = (buf[6] & 0x40) != 0;
    report->r3        = (buf[6] & 0x80) != 0;

    // PS + Touchpad click + Counter (byte 7)
    report->ps             = (buf[7] & 0x01) != 0;
    report->touchpad_click = (buf[7] & 0x02) != 0;
    report->frame_counter  = (buf[7] >> 2) & 0x3F;

    // Timestamp (bytes 10-11, little-endian)
    report->timestamp_raw = (uint16_t)(buf[10] | (buf[11] << 8));

    // Gyroscope (bytes 13-18, signed little-endian)
    report->gyro_pitch = (int16_t)(buf[13] | (buf[14] << 8));
    report->gyro_yaw   = (int16_t)(buf[15] | (buf[16] << 8));
    report->gyro_roll  = (int16_t)(buf[17] | (buf[18] << 8));

    // Accelerometer (bytes 19-24, signed little-endian)
    report->accel_x = (int16_t)(buf[19] | (buf[20] << 8));
    report->accel_y = (int16_t)(buf[21] | (buf[22] << 8));
    report->accel_z = (int16_t)(buf[23] | (buf[24] << 8));

    // Battery and status (byte 30)
    report->battery_level   = buf[30] & 0x0F;
    report->cable_connected = (buf[30] & 0x10) != 0;
    report->headphones      = (buf[30] & 0x20) != 0;
    report->microphone       = (buf[30] & 0x40) != 0;

    // Touchpad finger 0 (bytes 35-38)
    report->touch[0].active = (buf[35] & 0x80) == 0;
    report->touch[0].id     =  buf[35] & 0x7F;
    report->touch[0].x      = ((buf[37] & 0x0F) << 8) | buf[36];
    report->touch[0].y      = (buf[38] << 4) | ((buf[37] & 0xF0) >> 4);

    // Touchpad finger 1 (bytes 39-42)
    report->touch[1].active = (buf[39] & 0x80) == 0;
    report->touch[1].id     =  buf[39] & 0x7F;
    report->touch[1].x      = ((buf[41] & 0x0F) << 8) | buf[40];
    report->touch[1].y      = (buf[42] << 4) | ((buf[41] & 0xF0) >> 4);
}
```

### 9.2 Constructing an Output Report (C)

```c
typedef struct {
    uint8_t rumble_right;   // Weak/light/fast motor (0-255)
    uint8_t rumble_left;    // Strong/heavy/slow motor (0-255)
    uint8_t led_red;        // Light bar red (0-255)
    uint8_t led_green;      // Light bar green (0-255)
    uint8_t led_blue;       // Light bar blue (0-255)
    uint8_t flash_on;       // Flash on duration (0-255, 255=~2.5s)
    uint8_t flash_off;      // Flash off duration (0-255)
} DS4OutputState;

void ds4_build_output_report_usb(const DS4OutputState *state, uint8_t *buf) {
    memset(buf, 0, 32);

    buf[0] = 0x05;         // Report ID
    buf[1] = 0x07;         // Feature flags: rumble + lightbar + flash
    buf[2] = 0x04;         // Feature flags 2
    // buf[3] = 0x00;      // Reserved

    buf[4] = state->rumble_right;   // Right (weak) motor
    buf[5] = state->rumble_left;    // Left (strong) motor

    buf[6] = state->led_red;
    buf[7] = state->led_green;
    buf[8] = state->led_blue;

    buf[9]  = state->flash_on;
    buf[10] = state->flash_off;
}
```

### 9.3 Constructing a Bluetooth Output Report (C)

```c
uint32_t crc32_compute(const uint8_t *data, size_t len);

void ds4_build_output_report_bt(const DS4OutputState *state, uint8_t *buf) {
    memset(buf, 0, 78);

    buf[0] = 0x11;         // Report ID
    buf[1] = 0x80;         // CRC flag + poll rate (0x80 = CRC enabled)
    buf[2] = 0xFF;         // Control flags
    buf[3] = 0x07;         // Feature flags: rumble + lightbar + flash
    buf[4] = 0x04;         // Feature flags 2

    buf[6]  = state->rumble_right;
    buf[7]  = state->rumble_left;
    buf[8]  = state->led_red;
    buf[9]  = state->led_green;
    buf[10] = state->led_blue;
    buf[11] = state->flash_on;
    buf[12] = state->flash_off;

    // Compute CRC-32 over [0xA2] + buf[0..73]
    uint8_t crc_buf[75];
    crc_buf[0] = 0xA2;  // BT HID output transaction header
    memcpy(&crc_buf[1], buf, 74);

    uint32_t crc = crc32_compute(crc_buf, 75);
    buf[74] = (crc >>  0) & 0xFF;
    buf[75] = (crc >>  8) & 0xFF;
    buf[76] = (crc >> 16) & 0xFF;
    buf[77] = (crc >> 24) & 0xFF;
}
```

### 9.4 Reading Calibration Data (C)

```c
typedef struct {
    int bias;
    float scale;  // sensNumer / sensDenom
} DS4CalibAxis;

typedef struct {
    DS4CalibAxis gyro_pitch;
    DS4CalibAxis gyro_yaw;
    DS4CalibAxis gyro_roll;
    DS4CalibAxis accel_x;
    DS4CalibAxis accel_y;
    DS4CalibAxis accel_z;
} DS4Calibration;

#define GYRO_RES  16     // LSB per degree/sec
#define ACCEL_RES 8192   // LSB per g

void ds4_parse_calibration(const uint8_t *buf, DS4Calibration *cal) {
    // buf[0] is Report ID (0x02), data starts at buf[1]
    const uint8_t *d = &buf[1];

    int16_t gyro_pitch_bias  = (int16_t)(d[0]  | (d[1]  << 8));
    int16_t gyro_yaw_bias    = (int16_t)(d[2]  | (d[3]  << 8));
    int16_t gyro_roll_bias   = (int16_t)(d[4]  | (d[5]  << 8));

    int16_t gyro_pitch_plus  = (int16_t)(d[6]  | (d[7]  << 8));
    int16_t gyro_yaw_plus    = (int16_t)(d[8]  | (d[9]  << 8));
    int16_t gyro_roll_plus   = (int16_t)(d[10] | (d[11] << 8));
    int16_t gyro_pitch_minus = (int16_t)(d[12] | (d[13] << 8));
    int16_t gyro_yaw_minus   = (int16_t)(d[14] | (d[15] << 8));
    int16_t gyro_roll_minus  = (int16_t)(d[16] | (d[17] << 8));

    int16_t gyro_speed_plus  = (int16_t)(d[18] | (d[19] << 8));
    int16_t gyro_speed_minus = (int16_t)(d[20] | (d[21] << 8));
    int    gyro_speed_2x     = gyro_speed_plus + gyro_speed_minus;

    int16_t accel_x_plus  = (int16_t)(d[22] | (d[23] << 8));
    int16_t accel_x_minus = (int16_t)(d[24] | (d[25] << 8));
    int16_t accel_y_plus  = (int16_t)(d[26] | (d[27] << 8));
    int16_t accel_y_minus = (int16_t)(d[28] | (d[29] << 8));
    int16_t accel_z_plus  = (int16_t)(d[30] | (d[31] << 8));
    int16_t accel_z_minus = (int16_t)(d[32] | (d[33] << 8));

    // Gyroscope calibration
    cal->gyro_pitch.bias = gyro_pitch_bias;
    int denom = gyro_pitch_plus - gyro_pitch_minus;
    cal->gyro_pitch.scale = (denom != 0)
        ? (float)(gyro_speed_2x * GYRO_RES) / denom : 1.0f;

    cal->gyro_yaw.bias = gyro_yaw_bias;
    denom = gyro_yaw_plus - gyro_yaw_minus;
    cal->gyro_yaw.scale = (denom != 0)
        ? (float)(gyro_speed_2x * GYRO_RES) / denom : 1.0f;

    cal->gyro_roll.bias = gyro_roll_bias;
    denom = gyro_roll_plus - gyro_roll_minus;
    cal->gyro_roll.scale = (denom != 0)
        ? (float)(gyro_speed_2x * GYRO_RES) / denom : 1.0f;

    // Accelerometer calibration
    int range;

    range = accel_x_plus - accel_x_minus;
    cal->accel_x.bias = accel_x_plus - range / 2;
    cal->accel_x.scale = (range != 0)
        ? (float)(2 * ACCEL_RES) / range : 1.0f;

    range = accel_y_plus - accel_y_minus;
    cal->accel_y.bias = accel_y_plus - range / 2;
    cal->accel_y.scale = (range != 0)
        ? (float)(2 * ACCEL_RES) / range : 1.0f;

    range = accel_z_plus - accel_z_minus;
    cal->accel_z.bias = accel_z_plus - range / 2;
    cal->accel_z.scale = (range != 0)
        ? (float)(2 * ACCEL_RES) / range : 1.0f;
}

// Apply calibration to raw IMU values
void ds4_apply_calibration(const DS4Calibration *cal,
                           int16_t raw_gyro_pitch, int16_t raw_gyro_yaw, int16_t raw_gyro_roll,
                           int16_t raw_accel_x,    int16_t raw_accel_y,  int16_t raw_accel_z,
                           float *out_gyro_pitch,  float *out_gyro_yaw,  float *out_gyro_roll,
                           float *out_accel_x,     float *out_accel_y,   float *out_accel_z)
{
    // Gyro: result in LSB units at GYRO_RES per degree/sec
    *out_gyro_pitch = (raw_gyro_pitch - cal->gyro_pitch.bias) * cal->gyro_pitch.scale;
    *out_gyro_yaw   = (raw_gyro_yaw   - cal->gyro_yaw.bias)   * cal->gyro_yaw.scale;
    *out_gyro_roll  = (raw_gyro_roll  - cal->gyro_roll.bias)  * cal->gyro_roll.scale;

    // To get degrees/sec: divide by GYRO_RES (16)
    // *out_gyro_pitch /= 16.0f;

    // Accel: result in LSB units at ACCEL_RES per g
    *out_accel_x = (raw_accel_x - cal->accel_x.bias) * cal->accel_x.scale;
    *out_accel_y = (raw_accel_y - cal->accel_y.bias) * cal->accel_y.scale;
    *out_accel_z = (raw_accel_z - cal->accel_z.bias) * cal->accel_z.scale;

    // To get g: divide by ACCEL_RES (8192)
    // *out_accel_x /= 8192.0f;
}
```

### 9.5 CRC32 Implementation (C)

```c
#include <stdint.h>
#include <stddef.h>

static const uint32_t crc32_table[256] = {
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA,
    0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
    0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
    0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC,
    0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
    0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
    0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940,
    0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116,
    0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
    0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
    0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
    0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A,
    0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818,
    0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
    0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
    0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
    0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C,
    0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
    0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
    0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
    0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
    0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086,
    0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4,
    0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
    0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
    0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
    0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
    0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE,
    0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
    0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
    0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
    0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252,
    0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60,
    0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
    0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
    0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
    0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04,
    0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A,
    0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
    0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
    0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
    0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E,
    0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
    0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
    0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
    0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
    0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0,
    0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6,
    0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
};

uint32_t ds4_crc32(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return ~crc;
}

// Verify CRC on a Bluetooth input report
bool ds4_verify_bt_input_crc(const uint8_t *report, size_t len) {
    // Prepend BT HID header byte 0xA1 to CRC computation
    uint8_t header = 0xA1;
    uint32_t crc = 0xFFFFFFFF;

    // Hash the header byte
    crc = (crc >> 8) ^ crc32_table[(crc ^ header) & 0xFF];

    // Hash report bytes (excluding last 4 CRC bytes)
    for (size_t i = 0; i < len - 4; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ report[i]) & 0xFF];
    }
    crc = ~crc;

    // Compare with stored CRC (little-endian at end of report)
    uint32_t stored_crc = (uint32_t)report[len-4]
                        | ((uint32_t)report[len-3] << 8)
                        | ((uint32_t)report[len-2] << 16)
                        | ((uint32_t)report[len-1] << 24);

    return crc == stored_crc;
}
```

### 9.6 Swift/macOS Example (Using IOKit)

```swift
import IOKit.hid

struct DS4Report {
    var leftStickX: UInt8 = 0x80
    var leftStickY: UInt8 = 0x80
    var rightStickX: UInt8 = 0x80
    var rightStickY: UInt8 = 0x80

    var l2Trigger: UInt8 = 0
    var r2Trigger: UInt8 = 0

    var dpadUp = false, dpadDown = false
    var dpadLeft = false, dpadRight = false

    var square = false, cross = false
    var circle = false, triangle = false

    var l1 = false, r1 = false
    var l3 = false, r3 = false
    var share = false, options = false
    var ps = false, touchpadClick = false

    var gyroPitch: Int16 = 0
    var gyroYaw: Int16 = 0
    var gyroRoll: Int16 = 0

    var accelX: Int16 = 0
    var accelY: Int16 = 0
    var accelZ: Int16 = 0

    var batteryLevel: UInt8 = 0
    var cableConnected = false
}

func parseDS4Report(_ data: Data) -> DS4Report {
    var report = DS4Report()
    let buf = [UInt8](data)
    guard buf.count >= 64 && buf[0] == 0x01 else { return report }

    report.leftStickX  = buf[1]
    report.leftStickY  = buf[2]
    report.rightStickX = buf[3]
    report.rightStickY = buf[4]

    report.l2Trigger = buf[8]
    report.r2Trigger = buf[9]

    let dpad = buf[5] & 0x0F
    report.dpadUp    = [0, 1, 7].contains(dpad)
    report.dpadRight = [1, 2, 3].contains(dpad)
    report.dpadDown  = [3, 4, 5].contains(dpad)
    report.dpadLeft  = [5, 6, 7].contains(dpad)

    report.square   = (buf[5] & 0x10) != 0
    report.cross    = (buf[5] & 0x20) != 0
    report.circle   = (buf[5] & 0x40) != 0
    report.triangle = (buf[5] & 0x80) != 0

    report.l1      = (buf[6] & 0x01) != 0
    report.r1      = (buf[6] & 0x02) != 0
    report.share   = (buf[6] & 0x10) != 0
    report.options = (buf[6] & 0x20) != 0
    report.l3      = (buf[6] & 0x40) != 0
    report.r3      = (buf[6] & 0x80) != 0

    report.ps            = (buf[7] & 0x01) != 0
    report.touchpadClick = (buf[7] & 0x02) != 0

    report.gyroPitch = Int16(bitPattern: UInt16(buf[13]) | (UInt16(buf[14]) << 8))
    report.gyroYaw   = Int16(bitPattern: UInt16(buf[15]) | (UInt16(buf[16]) << 8))
    report.gyroRoll  = Int16(bitPattern: UInt16(buf[17]) | (UInt16(buf[18]) << 8))

    report.accelX = Int16(bitPattern: UInt16(buf[19]) | (UInt16(buf[20]) << 8))
    report.accelY = Int16(bitPattern: UInt16(buf[21]) | (UInt16(buf[22]) << 8))
    report.accelZ = Int16(bitPattern: UInt16(buf[23]) | (UInt16(buf[24]) << 8))

    report.batteryLevel   = buf[30] & 0x0F
    report.cableConnected = (buf[30] & 0x10) != 0

    return report
}

func buildDS4OutputReport(
    rumbleRight: UInt8 = 0,
    rumbleLeft: UInt8 = 0,
    ledRed: UInt8 = 0,
    ledGreen: UInt8 = 0,
    ledBlue: UInt8 = 0,
    flashOn: UInt8 = 0,
    flashOff: UInt8 = 0
) -> Data {
    var buf = [UInt8](repeating: 0, count: 32)
    buf[0]  = 0x05      // Report ID
    buf[1]  = 0x07      // Feature flags
    buf[2]  = 0x04      // Feature flags 2
    buf[4]  = rumbleRight
    buf[5]  = rumbleLeft
    buf[6]  = ledRed
    buf[7]  = ledGreen
    buf[8]  = ledBlue
    buf[9]  = flashOn
    buf[10] = flashOff
    return Data(buf)
}
```

---

## Sources

This document was compiled from the following references:

- [PS4 Developer Wiki: DS4-USB](https://www.psdevwiki.com/ps4/DS4-USB)
- [Game Controller Collective Wiki: Sony DualShock 4](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Game Controller Collective Wiki: DS4 Data Structures](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [GIMX Wiki: DualShock 4](https://gimx.fr/wiki/index.php?title=DualShock_4)
- [Eleccelerator Wiki: DualShock 4](http://eleccelerator.com/wiki/index.php?title=DualShock_4)
- [ds4drv by chrippa](https://github.com/chrippa/ds4drv) (Python reference implementation)
- [DS4Windows by Ryochan7](https://github.com/Ryochan7/DS4Windows) (C# reference implementation)
- [DualShock4 Reverse Engineering Blog by the.al](https://blog.the.al/2023/01/02/ds4-reverse-engineering-part-2.html)
- Linux kernel `hid-sony.c` driver
- Original HID Report Descriptor from `dualshock4hid.h`
